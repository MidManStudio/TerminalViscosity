// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "paint_layout.odin"
// ============================================================================

package carry

// The share of the height of the screen that the balloon area has to be wide: the balloon spans
// 0.525 of it, and the rest is margin to turn it in.
BALLOON_SPAN :: f32(0.58)

// Where everything is on the screen while drawing, as plain rectangles of x, y, width,
// and height in pixels, and what a touch at a point is on. It has no raylib in it, so
// the placing and the hit tests are tested without a window.

Hit_Kind :: enum u8 {
	None,
	Canvas, // on the tablet, to draw
	Swatch, // a color of the palette, `index` says which
	Size, // a brush, `index` says which
	Blend, // the blending pen
	Undo,
	Clear,
	Done,
	Balloon, // on the balloon, where a drag turns it
}

Paint_Layout :: struct {
	panel:    [4]f32, // the dark backing of everything to draw with, from the left edge of the tablet to the right edge of the screen
	canvas:   [4]f32, // the tablet, twice as wide as high
	swatches: [16][4]f32,
	sizes:    [3][4]f32,
	blend:    [4]f32,
	undo:     [4]f32,
	clear:    [4]f32,
	done:     [4]f32,
	balloon:  [4]f32, // the part of the screen where the balloon is, and a drag turns it
}

// Places everything for a screen of `w` by `h`. Everything to draw with is down the right
// side: the palette is two columns against the right edge, the tablet is to the left of it
// with the brushes, the blending pen, undo, and clear under it, and a dark panel backs them
// all. The rest of the left side is the balloon, with the done button at its top left. The
// owner asked for it this way round, with the balloon on the left.
paint_layout :: proc(w, h: f32) -> (l: Paint_Layout) {
	m := h * 0.025
	sw := clamp(h * 0.075, 30, 64)
	gap := m * 0.4
	palette_w := 2 * sw + gap
	palette_x := w - m - palette_w
	for k in 0 ..< 16 {
		col, row := f32(k % 2), f32(k / 2)
		l.swatches[k] = {palette_x + col * (sw + gap), m + row * (sw + gap), sw, sw}
	}

	// The tablet is as wide as half the screen, or as the height allows for a tablet twice as
	// wide as high, but never so wide that the balloon is squeezed. The balloon, 12 cm across, is
	// 0.525 of the height of the screen across at the distance the drawing view looks from, so it
	// needs `BALLOON_SPAN` of the height with a margin, which the self-test checks by projecting
	// it. A screen that is wide for its height never feels this. One that is nearly square does.
	// The tablet keeps at least 0.3 of the width, so it never disappears.
	cw := min(w * 0.5, 2 * h * 0.58)
	cw = min(cw, w - 4.5 * m - palette_w - BALLOON_SPAN * h)
	cw = max(cw, w * 0.3)
	l.canvas = {palette_x - 1.5 * m - cw, m, cw, cw * 0.5}
	l.panel = {l.canvas[0] - m, 0, w - (l.canvas[0] - m), h}

	// Three brushes and three wider buttons in a row under the tablet, made smaller if the
	// screen is narrow, so the row never reaches past the tablet.
	tb := min(clamp(h * 0.1, 36, 72), (cw - m - 6 * gap) / 7.5)
	ty := l.canvas[1] + l.canvas[3] + m // under the tablet, whose height is the last number
	for k in 0 ..< 3 {
		l.sizes[k] = {l.canvas.x + f32(k) * (tb + gap), ty, tb, tb}
	}
	next := l.canvas.x + 3 * (tb + gap) + m
	l.blend = {next, ty, tb * 1.5, tb}
	l.undo = {next + (tb * 1.5 + gap), ty, tb * 1.5, tb}
	l.clear = {next + 2 * (tb * 1.5 + gap), ty, tb * 1.5, tb}

	dh := clamp(h * 0.14, 52, 110)
	l.done = {m, m, dh * 1.6, dh}

	bx := m
	by := l.done.y + l.done.w + m
	l.balloon = {bx, by, max(l.panel[0] - m - bx, 0), max(h - m - by, 0)}
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
	case in_box(l.blend, x, y):
		return .Blend, 0
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
// 1 at the right, which is how far to the side the camera has to look to put the balloon
// there. It is negative now, because the balloon is on the left.
balloon_ndc :: proc(l: ^Paint_Layout, w: f32) -> f32 {
	return (l.balloon[0] + l.balloon[2] * 0.5) / w * 2 - 1
}
