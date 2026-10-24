// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "interact_ui.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import "carry"

// One rounded box of a hand icon, in a unit square with y pointing down.
// `shade` darkens the box so a thumb can be told apart from the fist.
Icon_Box :: struct {
	x, y, w, h: f32,
	shade:      f32,
}

ICON_OPEN :: [?]Icon_Box {
	{0.22, 0.50, 0.56, 0.42, 1}, // palm
	{0.22, 0.14, 0.115, 0.42, 1}, // index
	{0.345, 0.06, 0.115, 0.50, 1}, // middle
	{0.47, 0.12, 0.115, 0.46, 1}, // ring
	{0.595, 0.24, 0.115, 0.34, 1}, // little
	{0.04, 0.54, 0.26, 0.13, 1}, // thumb, out to the side
}

ICON_CLOSED :: [?]Icon_Box {
	{0.20, 0.32, 0.60, 0.52, 1}, // fist
	{0.20, 0.20, 0.14, 0.24, 1}, // knuckles
	{0.355, 0.17, 0.14, 0.27, 1},
	{0.51, 0.19, 0.14, 0.25, 1},
	{0.66, 0.24, 0.14, 0.20, 1},
	{0.26, 0.60, 0.40, 0.15, 0.78}, // thumb across the front
}

// The grab button, in the bottom right corner. A finger that lands on it does
// not move or look.
grab_button :: proc(w, h: f32) -> [4]f32 {
	size := max(f32(64), h * 0.13)
	return {w - size * 1.8 - 24, h - size - 24, size * 1.8, size}
}

// The button says "grab" until something is held, and then "release". It is
// dim when there is nothing within reach to grab.
draw_grab_button :: proc(w, h: f32, state: carry.State) {
	b := grab_button(w, h)
	label: cstring = "grab"
	fill := rl.Color{255, 255, 255, 18}
	edge := rl.Color{255, 255, 255, 70}
	ink := rl.Color{255, 255, 255, 110}
	switch state {
	case .Idle:
	case .Reaching:
		fill, edge, ink = {255, 255, 255, 44}, {255, 255, 255, 150}, rl.RAYWHITE
	case .Holding:
		label = "release"
		fill, edge, ink = {60, 230, 215, 70}, {60, 230, 215, 200}, rl.RAYWHITE
	}
	rect := rl.Rectangle{b.x, b.y, b.z, b.w}
	rl.DrawRectangleRounded(rect, 0.3, 8, fill)
	rl.DrawRectangleRoundedLinesEx(rect, 0.3, 8, 2, edge)
	font := i32(b.w / 5)
	rl.DrawText(label, i32(b.x + b.z * 0.5) - rl.MeasureText(label, font) / 2, i32(b.y + b.w * 0.5) - font / 2, font, ink)
}

// Draws a hand icon with its top left corner at (x, y) and `size` pixels
// across: a dark outline first, then the fill, so it reads on any background.
draw_icon :: proc(boxes: []Icon_Box, x, y, size: f32, fill: rl.Color) {
	outline := f32(2)
	for b in boxes {
		rect := rl.Rectangle{x + b.x * size - outline, y + b.y * size - outline, b.w * size + 2 * outline, b.h * size + 2 * outline}
		rl.DrawRectangleRounded(rect, 0.45, 6, {10, 18, 26, 255})
	}
	for b in boxes {
		rect := rl.Rectangle{x + b.x * size, y + b.y * size, b.w * size, b.h * size}
		c := rl.Color{u8(f32(fill.r) * b.shade), u8(f32(fill.g) * b.shade), u8(f32(fill.b) * b.shade), 255}
		rl.DrawRectangleRounded(rect, 0.45, 6, c)
	}
}

// The crosshair dot at the middle of the screen with a hand under it: an open
// hand in white while nothing is in reach, in teal when something is, and a
// closed fist while holding.
draw_crosshair :: proc(w, h: f32, state: carry.State) {
	cx, cy := i32(w * 0.5), i32(h * 0.5)
	radius := max(f32(3), h * 0.006)
	dot := rl.Color{255, 255, 255, 235}
	hand := rl.Color{226, 232, 238, 255}
	switch state {
	case .Idle:
	case .Reaching:
		radius *= 1.6
		dot, hand = {60, 230, 215, 255}, {60, 230, 215, 255}
	case .Holding:
		hand = rl.RAYWHITE
	}
	rl.DrawCircle(cx, cy, radius + 1.5, {10, 18, 26, 170})
	rl.DrawCircle(cx, cy, radius, dot)

	size := max(f32(30), h * 0.075)
	x := f32(cx) - size * 0.5
	y := f32(cy) + radius + 8
	if state == .Holding {
		closed := ICON_CLOSED
		draw_icon(closed[:], x, y, size, hand)
	} else {
		open := ICON_OPEN
		draw_icon(open[:], x, y, size, hand)
	}
}
