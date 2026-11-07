// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "arena_ui.odin"
// ============================================================================

package main

import "arena"
import "carry"
import "chem"
import "core:fmt"
import rl "vendor:raylib"

SLOT_GAP :: f32(14)

// Formats into a buffer the caller owns and returns it as C text, so a label costs no
// allocation. What does not fit is cut off.
text_in :: proc(buf: []u8, format: string, args: ..any) -> cstring {
	line := fmt.bprintf(buf[:len(buf) - 1], format, ..args)
	buf[len(line)] = 0
	return cstring(raw_data(buf))
}

// The button in the lab that goes to the arena, under the liquid speed button.
arena_button :: proc(w, h: f32) -> [4]f32 {
	b := speed_button(w, h)
	return {b.x, b.y + b.w + 12, b.z, b.w}
}

draw_arena_button :: proc(w, h: f32) {
	draw_button(arena_button(w, h), "arena", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
}

// Radius of the fire stick in pixels. It is a round stick a thumb can rest on and push.
fire_radius :: proc(w, h: f32) -> f32 {
	return max(f32(60), min(w, h) * 0.12)
}

// The box of the fire stick, in the bottom right corner, that a finger can land on to press it. A
// finger that lands anywhere in the box holds the stick, even in a corner the circle leaves out,
// and the finger may then wander as far as it likes.
throw_button :: proc(w, h: f32) -> [4]f32 {
	r := fire_radius(w, h)
	return {w - r * 2 - 24, h - r * 2 - 24, r * 2, r * 2}
}

// The middle of the fire stick, and its radius.
fire_stick :: proc(w, h: f32) -> (center: [2]f32, radius: f32) {
	b := throw_button(w, h)
	return {b.x + b.z * 0.5, b.y + b.w * 0.5}, b.z * 0.5
}

// The jump button sits just above the fire stick, a little narrower than it.
arena_jump_button :: proc(w, h: f32) -> [4]f32 {
	g := throw_button(w, h)
	height := g.z * 0.55
	return {g.x + g.z * 0.1, g.y - height - 16, g.z * 0.8, height}
}

// The slot buttons are a row of squares just left of the fire stick, slot 0 farthest, level with
// the bottom of the stick.
slot_button :: proc(w, h: f32, i: int) -> [4]f32 {
	g := throw_button(w, h)
	side := g.z * 0.55
	return {g.x - f32(carry.LOADOUT_SLOTS - i) * (side + SLOT_GAP), g.y + g.w - side, side, side}
}

draw_arena_jump_button :: proc(w, h: f32, unavailable: bool) {
	fill := rl.Color{10, 18, 28, 190}
	edge := rl.Color{230, 236, 242, 220}
	ink := rl.RAYWHITE
	if unavailable {
		fill, edge, ink = {10, 18, 28, 120}, {200, 210, 222, 100}, {200, 210, 222, 150}
	}
	draw_button(arena_jump_button(w, h), "jump", fill, edge, ink)
}

// What the fire stick says, and whether it would start a throw now. A stick that is bright can be
// used and one that is dim cannot, and it is so before it is touched.
throw_label :: proc(t: ^arena.Thrower, slots: ^[carry.LOADOUT_SLOTS]arena.Slot, down: bool) -> (label: cstring, ready: bool) {
	switch {
	case down:
		return "knocked out", false
	case t.charging:
		return "release", true
	case !arena.slot_usable(slots, t.selected):
		return "no balloon", false
	case t.cooldown > 0:
		return "wait", false
	}
	return "throw", true
}

// The fire stick: a round base, a ring that fills up as the throw charges, and a knob that follows
// the finger. `push` is where the finger is, from -1 to 1 on each axis, and `held` whether one is down.
draw_throw_button :: proc(w, h: f32, t: ^arena.Thrower, slots: ^[carry.LOADOUT_SLOTS]arena.Slot, down: bool, held: bool, push: [2]f32) {
	label, ready := throw_label(t, slots, down)
	fill := rl.Color{10, 18, 28, 150}
	edge := rl.Color{200, 210, 222, 110}
	ink := rl.Color{200, 210, 222, 160}
	if ready {
		fill, edge, ink = {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE
	}
	if t.charging {
		fill = {30, 130, 120, 245}
	}
	c, r := fire_stick(w, h)
	cx, cy := i32(c.x), i32(c.y)
	rl.DrawCircle(cx, cy, r, fill)
	rl.DrawRing(c, r * 0.9, r, 0, 360, 48, edge)
	if t.charging {
		// The power so far: a gold ring that fills clockwise from the top.
		rl.DrawRing(c, r * 0.9, r, -90, -90 + 360 * t.charge, 48, {255, 214, 120, 255})
	}
	font := i32(r * 0.26)
	rl.DrawText(label, cx - rl.MeasureText(label, font) / 2 + 1, cy - font / 2 + 2, font, {0, 0, 0, 220})
	rl.DrawText(label, cx - rl.MeasureText(label, font) / 2, cy - font / 2, font, ink)
	if held {
		// The knob follows the finger, and stays inside the base.
		travel := r * 0.55
		rl.DrawCircle(cx + i32(push.x * travel), cy + i32(push.y * travel), r * 0.34, {255, 255, 255, 110})
		rl.DrawCircleLines(cx + i32(push.x * travel), cy + i32(push.y * travel), r * 0.34, {255, 255, 255, 200})
	}
}

// The box of the local player's hit point bar: top left, under the three lines of text.
health_bar :: proc(w, h: f32) -> [4]f32 {
	text := max(f32(18), h / 36)
	return {20, 20 + text * 3 + 24, max(f32(160), w * 0.22), 22}
}

// The local player's hit points as a bar, red as it runs low.
draw_health_bar :: proc(w, h: f32, hp: u8) {
	b := health_bar(w, h)
	bar := rl.Rectangle{b.x, b.y, b.z, b.w}
	frac := f32(hp) / f32(arena.MAX_HEALTH)
	color := rl.Color{80, 220, 120, 255}
	if frac <= 0.5 {
		color = {240, 190, 60, 255}
	}
	if frac <= 0.25 {
		color = {235, 70, 60, 255}
	}
	rl.DrawRectangleRec(bar, {10, 18, 28, 190})
	rl.DrawRectangleRec({bar.x, bar.y, bar.width * frac, bar.height}, color)
	rl.DrawRectangleLinesEx(bar, 2, {230, 236, 242, 220})
	buf: [16]u8
	text := text_in(buf[:], "%d", hp)
	size := i32(bar.height * 0.9)
	rl.DrawText(text, i32(bar.x + bar.width * 0.5) - rl.MeasureText(text, size) / 2, i32(bar.y) + 1, size, rl.RAYWHITE)
}

// A small red cross around the crosshair for a moment, to say that a balloon of the player's hurt someone.
draw_hit_marker :: proc(w, h: f32, amount: f32) {
	if amount <= 0 {
		return
	}
	cx, cy := w * 0.5, h * 0.5
	near := max(f32(10), h * 0.02)
	far := near * 2
	color := rl.Color{235, 60, 50, u8(clamp(amount, 0, 1) * 255)}
	for sx in ([2]f32{-1, 1}) {
		for sy in ([2]f32{-1, 1}) {
			rl.DrawLineEx({cx + sx * near, cy + sy * near}, {cx + sx * far, cy + sy * far}, 4, color)
		}
	}
}

draw_slot_button :: proc(w, h: f32, i: int, slot: arena.Slot, selected: bool) {
	b := slot_button(w, h, i)
	rect := rl.Rectangle{b.x, b.y, b.z, b.w}
	edge := selected ? rl.Color{255, 255, 255, 255} : rl.Color{200, 210, 222, 110}
	rl.DrawRectangleRounded(rect, 0.2, 8, {10, 18, 28, slot.used ? 215 : 130})
	if slot.used {
		c := chem.compound_color(slot.compound)
		swatch := rl.Rectangle{b.x + b.z * 0.18, b.y + b.w * 0.2, b.z * 0.64, b.w * 0.5}
		rl.DrawRectangleRounded(swatch, 0.4, 8, {u8(c.x * 255), u8(c.y * 255), u8(c.z * 255), 255})
	}
	rl.DrawRectangleRoundedLinesEx(rect, 0.2, 8, selected ? 5 : 3, edge)
	font := i32(b.w * 0.2)
	number_buf: [8]u8
	number := text_in(number_buf[:], "%d", i + 1)
	rl.DrawText(number, i32(b.x) + 8, i32(b.y) + 6, font, slot.used ? rl.RAYWHITE : rl.Color{200, 210, 222, 140})
	if slot.used {
		text_buf: [16]u8
		text := text_in(text_buf[:], "%d ml", slot.ml)
		small := i32(b.w * 0.16)
		rl.DrawText(text, i32(b.x + b.z * 0.5) - rl.MeasureText(text, small) / 2, i32(b.y + b.w * 0.76), small, rl.RAYWHITE)
	} else {
		draw_text_centered("empty", i32(b.x + b.z * 0.5), i32(b.y + b.w * 0.42), i32(b.w * 0.17), {200, 210, 222, 150})
	}
}

// A small cross in the middle of the screen: where a thrown balloon starts out heading.
draw_arena_crosshair :: proc(w, h: f32) {
	cx, cy := i32(w * 0.5), i32(h * 0.5)
	arm := i32(max(f32(8), h * 0.014))
	ink := rl.Color{20, 28, 40, 230}
	rl.DrawLine(cx - arm, cy, cx + arm, cy, ink)
	rl.DrawLine(cx, cy - arm, cx, cy + arm, ink)
	rl.DrawCircle(cx, cy, 2, {255, 255, 255, 240})
}
