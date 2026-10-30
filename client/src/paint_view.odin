// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "paint_view.odin"
// ============================================================================

package main

import "carry"
import "core:math"
import "lab"
import rl "vendor:raylib"

PAINT_FOV :: f32(40)
PAINT_DISTANCE :: f32(0.34) // how far from the balloon the camera is while drawing

// The fingers while drawing: the one that is drawing on the tablet, the one that is
// turning the balloon, and which fingers were already down, so a finger that was there
// when drawing began, or that landed on a button, does nothing more.
Paint_Input :: struct {
	stroke_id:   int, // -1 when no finger is drawing
	turn_id:     int, // -1 when no finger is turning the balloon
	turn_last:   f32, // where that finger was across the screen last frame
	known:       [MAX_POINTERS]int,
	known_count: int,
}

paint_input_init :: proc(input: ^Paint_Input, pointers: ^Pointers) {
	input^ = {
		stroke_id = -1,
		turn_id   = -1,
	}
	paint_input_remember(input, pointers)
}

paint_input_remember :: proc(input: ^Paint_Input, pointers: ^Pointers) {
	input.known_count = pointers.count
	for i in 0 ..< pointers.count {
		input.known[i] = pointers.items[i].id
	}
}

paint_is_new :: proc(input: ^Paint_Input, id: int) -> bool {
	for i in 0 ..< input.known_count {
		if input.known[i] == id {
			return false
		}
	}
	return true
}

paint_is_down :: proc(pointers: ^Pointers, id: int) -> bool {
	for i in 0 ..< pointers.count {
		if pointers.items[i].id == id {
			return true
		}
	}
	return false
}

// What the fingers did this frame. A new finger on the tablet starts a stroke, and the
// stroke goes on with it until it lifts, held to the edge of the tablet if it leaves it. A
// new finger on a swatch or a brush chooses it, on undo or clear does that, on done
// ends the drawing, and on the balloon turns it as it moves. `turn` is how far round
// the balloon is turned, as a share of a turn, and `h` the height of the screen. The
// first stroke on a balloon makes its drawing, if there is room for one. Returns
// whether the player is done, and whether there was no room to make a drawing.
paint_touch_update :: proc(input: ^Paint_Input, pointers: ^Pointers, l: ^carry.Paint_Layout, p: ^carry.Paint, lo: ^carry.Loadout, store: ^carry.Art_Store, turn: ^f32, h: f32) -> (done, no_room: bool) {
	if input.stroke_id != -1 && !paint_is_down(pointers, input.stroke_id) {
		carry.paint_stroke_end(p)
		input.stroke_id = -1
	}
	if input.turn_id != -1 && !paint_is_down(pointers, input.turn_id) {
		input.turn_id = -1
	}
	canvas := carry.art_get(store, lo.paint.art)
	for i in 0 ..< pointers.count {
		ptr := pointers.items[i]
		if paint_is_new(input, ptr.id) {
			kind, index := carry.paint_hit(l, ptr.pos.x, ptr.pos.y)
			switch kind {
			case .None:
			case .Done:
				done = true
			case .Swatch:
				p.color = u8(index)
			case .Size:
				p.size = index
			case .Undo:
				if canvas != nil {
					carry.paint_undo(p, canvas)
				}
			case .Clear:
				if canvas != nil {
					carry.paint_clear(p, canvas)
				}
			case .Canvas:
				if canvas == nil {
					lo.paint.art = carry.art_new(store)
					canvas = carry.art_get(store, lo.paint.art)
				}
				if canvas == nil {
					no_room = true
				} else {
					tx, ty, _ := carry.canvas_texel(l, ptr.pos.x, ptr.pos.y)
					carry.paint_stroke_begin(p, canvas, tx, ty)
					input.stroke_id = ptr.id
				}
			case .Balloon:
				input.turn_id = ptr.id
				input.turn_last = ptr.pos.x
			}
		} else if ptr.id == input.stroke_id && canvas != nil {
			tx, ty, _ := carry.canvas_texel(l, ptr.pos.x, ptr.pos.y)
			carry.paint_stroke_to(p, canvas, clamp(tx, 0, carry.CANVAS_W), clamp(ty, 0, carry.CANVAS_H))
		} else if ptr.id == input.turn_id {
			// A finger moves the surface under it: round the balloon at its middle, a
			// quarter of the height of the screen from the middle to the side.
			turn^ += (ptr.pos.x - input.turn_last) / (h * 0.25 * math.TAU)
			input.turn_last = ptr.pos.x
		}
	}
	paint_input_remember(input, pointers)
	return
}

// The camera while drawing: close to the balloon in the clamp, looking along the
// counter at it, turned a little to the side so that the balloon is in the middle of the
// part of the screen left for it, and not in the middle of the screen.
paint_camera :: proc(w, h: f32) -> rl.Camera3D {
	l := carry.paint_layout(w, h)
	n := carry.balloon_ndc(&l, w)
	half := PAINT_DISTANCE * math.tan(PAINT_FOV * 0.5 * math.RAD_PER_DEG) * (w / h)
	c := lab.PAINT_CLAMP
	y := c.y - lab.PAINT_DROP * 0.5
	z := c.z + n * half // to the left, which is south here, of the balloon, so it is drawn to the right
	return rl.Camera3D{position = {c.x + PAINT_DISTANCE, y, z}, target = {c.x, y, z}, up = {0, 1, 0}, fovy = PAINT_FOV, projection = .PERSPECTIVE}
}

// The screen while drawing, over the picture of the balloon: the tablet, the palette,
// the brushes, undo and clear, and a done button that is always there.
draw_paint_ui :: proc(w, h: f32, lv: ^Loadout_View, lo: ^carry.Loadout, p: ^carry.Paint) {
	l := carry.paint_layout(w, h)
	margin := h * 0.025
	rl.DrawRectangle(0, 0, i32(l.canvas[0] + l.canvas[2] + margin), i32(h), {8, 12, 18, 200})

	// The tablet.
	rect := rl.Rectangle{l.canvas[0], l.canvas[1], l.canvas[2], l.canvas[3]}
	rubber := lab.palette_color(0)
	rl.DrawRectangleRec(rect, {rubber.r, rubber.g, rubber.b, 255})
	if lv.paint.art.loaded && lv.paint.art.art_id != 0 {
		src := rl.Rectangle{0, 0, carry.CANVAS_W, carry.CANVAS_H}
		rl.DrawTexturePro(lv.paint.art.tex, src, rect, {0, 0}, 0, rl.WHITE)
	}
	rl.DrawRectangleLinesEx(rect, 3, {230, 236, 242, 255})

	// The palette. The first swatch is no paint, the eraser, and is crossed out.
	for k in 0 ..< len(l.swatches) {
		b := l.swatches[k]
		c := lab.palette_color(k)
		r := rl.Rectangle{b[0], b[1], b[2], b[3]}
		rl.DrawRectangleRec(r, {c.r, c.g, c.b, 255})
		if k == 0 {
			rl.DrawLineEx({b[0] + 6, b[1] + 6}, {b[0] + b[2] - 6, b[1] + b[3] - 6}, 3, {150, 60, 60, 255})
			rl.DrawLineEx({b[0] + b[2] - 6, b[1] + 6}, {b[0] + 6, b[1] + b[3] - 6}, 3, {150, 60, 60, 255})
		}
		chosen := int(p.color) == k
		rl.DrawRectangleLinesEx(r, chosen ? 5 : 2, chosen ? rl.Color{255, 255, 255, 255} : rl.Color{20, 28, 38, 255})
	}

	// The brushes, drawn as dots of their sizes.
	radii := [3]f32{0.2, 0.32, 0.46}
	for k in 0 ..< len(l.sizes) {
		b := l.sizes[k]
		chosen := p.size == k
		rl.DrawRectangleRounded({b[0], b[1], b[2], b[3]}, 0.3, 8, chosen ? rl.Color{14, 74, 74, 230} : rl.Color{10, 18, 28, 190})
		rl.DrawRectangleRoundedLinesEx({b[0], b[1], b[2], b[3]}, 0.3, 8, 3, chosen ? rl.Color{60, 230, 215, 255} : rl.Color{230, 236, 242, 200})
		c := lab.palette_color(int(p.color))
		rl.DrawCircle(i32(b[0] + b[2] * 0.5), i32(b[1] + b[3] * 0.5), b[2] * radii[k], {c.r, c.g, c.b, 255})
	}
	can_undo := p.undo_count > 0
	draw_button(l.undo, "undo", can_undo ? rl.Color{10, 18, 28, 190} : rl.Color{10, 18, 28, 110}, rl.Color{230, 236, 242, 200}, can_undo ? rl.RAYWHITE : rl.Color{230, 236, 242, 110})
	draw_button(l.clear, "clear", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
	draw_button(l.done, "done", {120, 30, 30, 235}, {255, 120, 110, 255}, rl.RAYWHITE)

	size := i32(max(f32(16), h * 0.03))
	draw_text_centered("drag on the balloon to turn it", i32(l.balloon[0] + l.balloon[2] * 0.5), i32(l.balloon[1] + l.balloon[3] - f32(size) * 1.6), size, {230, 236, 242, 255})
	if !lo.paint.used {
		draw_text_centered("no balloon in the clamp", i32(l.canvas[0] + l.canvas[2] * 0.5), i32(l.canvas[1] + l.canvas[3] * 0.5), size, {60, 70, 84, 255})
	}
}
