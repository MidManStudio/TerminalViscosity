// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "paint_layout.odin"
// ============================================================================

package carry

// Where everything is on the screen while drawing, as plain rectangles of x, y, width,
// and height in pixels, and what a touch at a point is on. It has no raylib in it, so
// the placing and the hit tests are tested without a window.

Hit_Kind :: enum u8 {
	None,
	Canvas, // on the tablet, to draw
	Swatch, // a color of the palette, `index` says which
	Size, // a brush, `index` says which
	Undo,
	Clear,
	Done,
	Balloon, // on the balloon, where a drag turns it
}

Paint_Layout :: struct {
	canvas:   [4]f32, // the tablet, twice as wide as high
	swatches: [16][4]f32,
	sizes:    [3][4]f32,
	undo:     [4]f32,
	clear:    [4]f32,
	done:     [4]f32,
	balloon:  [4]f32, // the part of the screen where the balloon is, and a drag turns it
}

// Places everything for a screen of `w` by `h`. The palette is two columns down the
// left, the tablet is to the right of it with the brushes, undo and clear under it, the
// done button is at the top right, and the rest of the right side is the balloon.
paint_layout :: proc(w, h: f32) -> (l: Paint_Layout) {
	m := h * 0.025
	sw := clamp(h * 0.075, 30, 64)
	gap := m * 0.4
	for k in 0 ..< 16 {
		col, row := f32(k % 2), f32(k / 2)
		l.swatches[k] = {m + col * (sw + gap), m + row * (sw + gap), sw, sw}
	}
	palette_right := m + 2 * sw + gap

	cw := min(w * 0.5, 2 * h * 0.58)
	l.canvas = {palette_right + 1.5 * m, m, cw, cw * 0.5}

	tb := clamp(h * 0.1, 36, 72)
	ty := l.canvas[1] + l.canvas[3] + m // under the tablet, whose height is the last number
	for k in 0 ..< 3 {
		l.sizes[k] = {l.canvas.x + f32(k) * (tb + gap), ty, tb, tb}
	}
	next := l.canvas.x + 3 * (tb + gap) + m
	l.undo = {next, ty, tb * 1.8, tb}
	l.clear = {next + tb * 1.8 + gap, ty, tb * 1.8, tb}

	dh := clamp(h * 0.14, 52, 110)
	l.done = {w - m - dh * 1.6, m, dh * 1.6, dh}

	bx := l.canvas.x + cw + m
	by := l.done.y + l.done.w + m
	l.balloon = {bx, by, max(w - m - bx, 0), max(h - m - by, 0)}
	return
}

in_box :: proc(b: [4]f32, x, y: f32) -> bool {
	return x >= b[0] && x <= b[0] + b[2] && y >= b[1] && y <= b[1] + b[3]
}

// What a touch at (`x`, `y`) is on, and which one of its kind. The buttons come first,
// so one that is over another area is the one that is pressed.
paint_hit :: proc(l: ^Paint_Layout, x, y: f32) -> (kind: Hit_Kind, index: int) {
	switch {
	case in_box(l.done, x, y):
		return .Done, 0
	case in_box(l.undo, x, y):
		return .Undo, 0
	case in_box(l.clear, x, y):
		return .Clear, 0
	}
	for k in 0 ..< len(l.sizes) {
		if in_box(l.sizes[k], x, y) {
			return .Size, k
		}
	}
	for k in 0 ..< len(l.swatches) {
		if in_box(l.swatches[k], x, y) {
			return .Swatch, k
		}
	}
	if in_box(l.canvas, x, y) {
		return .Canvas, 0
	}
	if in_box(l.balloon, x, y) {
		return .Balloon, 0
	}
	return .None, 0
}

// The pixel of the drawing under a point of the screen, as a position between 0 and
// the size of the canvas, and whether the point is on the tablet at all.
canvas_texel :: proc(l: ^Paint_Layout, x, y: f32) -> (tx, ty: f32, inside: bool) {
	tx = (x - l.canvas[0]) / l.canvas[2] * CANVAS_W
	ty = (y - l.canvas[1]) / l.canvas[3] * CANVAS_H
	return tx, ty, in_box(l.canvas, x, y)
}

// Where the middle of the balloon area is across the screen, from -1 at the left to
// 1 at the right, which is how far to the side the camera has to look to put the balloon there.
balloon_ndc :: proc(l: ^Paint_Layout, w: f32) -> f32 {
	return (l.balloon[0] + l.balloon[2] * 0.5) / w * 2 - 1
}
