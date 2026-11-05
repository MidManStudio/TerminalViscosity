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

// The throw button sits where the grab button does in the lab.
throw_button :: proc(w, h: f32) -> [4]f32 {
	return grab_button(w, h)
}

// The slot buttons are a row of squares just left of the throw button, slot 0 farthest.
slot_button :: proc(w, h: f32, i: int) -> [4]f32 {
	g := throw_button(w, h)
	side := g.w
	return {g.x - f32(carry.LOADOUT_SLOTS - i) * (side + SLOT_GAP), g.y, side, g.w}
}

// What the throw button says, and whether it would throw now. A button that is bright
// can be used and one that is dim cannot, and it is so before it is pressed.
throw_label :: proc(t: ^arena.Thrower, slots: ^[carry.LOADOUT_SLOTS]arena.Slot) -> (label: cstring, ready: bool) {
	switch {
	case t.charging:
		return "release", true
	case !arena.slot_usable(slots, t.selected):
		return "no balloon", false
	case t.cooldown > 0:
		return "wait", false
	}
	return "throw", true
}

draw_throw_button :: proc(w, h: f32, t: ^arena.Thrower, slots: ^[carry.LOADOUT_SLOTS]arena.Slot) {
	label, ready := throw_label(t, slots)
	fill := rl.Color{10, 18, 28, 150}
	edge := rl.Color{200, 210, 222, 110}
	ink := rl.Color{200, 210, 222, 160}
	if ready {
		fill, edge, ink = {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE
	}
	if t.charging {
		fill = {30, 130, 120, 245}
	}
	b := throw_button(w, h)
	draw_button(b, label, fill, edge, ink)
	if t.charging {
		// The power so far, along the bottom of the button: a bar that fills left to right. It
		// is inside the button because the jump button is just above it.
		bar := rl.Rectangle{b.x + b.z * 0.08, b.y + b.w - b.w * 0.2, b.z * 0.84, b.w * 0.09}
		rl.DrawRectangleRec(bar, {10, 18, 28, 220})
		rl.DrawRectangleRec({bar.x, bar.y, bar.width * t.charge, bar.height}, {255, 214, 120, 255})
		rl.DrawRectangleLinesEx(bar, 2, {230, 236, 242, 220})
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
