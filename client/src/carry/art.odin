// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "art.odin"
// ============================================================================

package carry

import "../lab"
import "core:math"

CANVAS_W :: 256 // pixels across, once round the balloon
CANVAS_H :: 256 // pixels down, from the tip to the bottom
ART_POOL :: 16 // how many drawings can exist at once
UNDO_DEPTH :: 8 // how many strokes can be taken back

// The radius of the three brushes, in pixels across the canvas. A pixel is twice as
// wide as it is high on the tablet and the balloon, so a brush is twice as many pixels
// high as it is wide to be round.
BRUSH_SIZES :: [3]f32{2, 5, 10}

// A drawing: 256 by 256 pixels, each one of the 16 colors of the palette, as the
// wire format of the arena has it. Color 0 is no paint, the bare rubber.
Canvas :: struct {
	px:        [CANVAS_W * CANVAS_H]u8,
	version:   u32, // goes up with every change, so what draws it knows to update
	dirty:     [4]int, // x0, y0, x1, y1, inclusive: what has changed since it was last taken
	has_dirty: bool,
}

// Every drawing that exists. A balloon has the id of its drawing, 0 for none, so a
// drawing goes with its balloon wherever it is put.
Art_Store :: struct {
	canvases: [ART_POOL]Canvas,
	used:     [ART_POOL]bool,
}

// Makes a blank drawing and returns its id, from 1, or 0 when there is no room.
art_new :: proc(s: ^Art_Store) -> u16 {
	for i in 0 ..< ART_POOL {
		if !s.used[i] {
			s.used[i] = true
			s.canvases[i] = {}
			return u16(i + 1)
		}
	}
	return 0
}

// The drawing with this id, or nil for 0, an id out of range, or one not in use.
art_get :: proc(s: ^Art_Store, id: u16) -> ^Canvas {
	if id == 0 || int(id) > ART_POOL || !s.used[int(id) - 1] {
		return nil
	}
	return &s.canvases[int(id) - 1]
}

art_free :: proc(s: ^Art_Store, id: u16) {
	if art_get(s, id) != nil {
		s.used[int(id) - 1] = false
	}
}

mark_dirty :: proc(c: ^Canvas, x0, y0, x1, y1: int) {
	if !c.has_dirty {
		c.dirty = {x0, y0, x1, y1}
		c.has_dirty = true
	} else {
		c.dirty = {min(c.dirty[0], x0), min(c.dirty[1], y0), max(c.dirty[2], x1), max(c.dirty[3], y1)}
	}
	c.version += 1
}

// Takes the rectangle that has changed since it was last taken, and forgets it.
canvas_dirty_take :: proc(c: ^Canvas) -> (rect: [4]int, ok: bool) {
	if !c.has_dirty {
		return {}, false
	}
	c.has_dirty = false
	return c.dirty, true
}

// One round dab of `color` with its middle at (`x`, `y`) in pixels, `r` pixels wide
// to each side and twice as many high. The canvas goes once round the balloon, so a
// dab that runs off the right edge comes in at the left, and one at the top or the
// bottom is cut off.
canvas_dab :: proc(c: ^Canvas, x, y, r: f32, color: u8) {
	ry := 2 * r
	top := max(int(math.floor(y - ry)), 0)
	bottom := min(int(math.ceil(y + ry)), CANVAS_H - 1)
	if top > bottom {
		return
	}
	left, right := CANVAS_W, 0
	for j in top ..= bottom {
		dy := (f32(j) + 0.5 - y) / ry
		if dy * dy > 1 {
			continue
		}
		half := r * math.sqrt(1 - dy * dy)
		first, last := int(math.floor(x - half)), int(math.ceil(x + half - 1))
		for i in first ..= last {
			if f32(i) + 0.5 < x - half || f32(i) + 0.5 > x + half {
				continue
			}
			col := i %% CANVAS_W
			c.px[j * CANVAS_W + col] = color
			// A dab over the seam has columns at both ends, so what changed spans the whole width.
			left, right = min(left, col), max(right, col)
		}
	}
	if right < left {
		return
	}
	mark_dirty(c, left, top, right, bottom)
}

// A line of dabs from one point to another, close enough together to leave no gaps.
// The line is straight across the canvas: it does not take the short way round the
// balloon.
canvas_line :: proc(c: ^Canvas, x0, y0, x1, y1, r: f32, color: u8) {
	dx, dy := x1 - x0, y1 - y0
	steps := max(int(math.ceil(max(abs(dx) / (r * 0.5), abs(dy) / r))), 1)
	for k in 0 ..= steps {
		t := f32(k) / f32(steps)
		canvas_dab(c, x0 + dx * t, y0 + dy * t, r, color)
	}
}

// Takes every bit of paint off.
canvas_clear :: proc(c: ^Canvas) {
	c.px = {}
	mark_dirty(c, 0, 0, CANVAS_W - 1, CANVAS_H - 1)
}

// The color of palette entry `i` as it goes to the screen: the swatch of the lab, with
// no paint see-through.
palette_rgba :: proc(i: u8) -> [4]u8 {
	c := lab.palette_color(int(i))
	if i == 0 {
		c.a = 0
	}
	return c
}

// Writes the rectangle (`x0`, `y0`) to (`x1`, `y1`), inclusive, of a drawing as RGBA
// bytes, row by row, into `out`, which must hold four bytes for each pixel.
canvas_to_rgba :: proc(c: ^Canvas, x0, y0, x1, y1: int, out: []u8) {
	n := 0
	for j in y0 ..= y1 {
		for i in x0 ..= x1 {
			rgba := palette_rgba(c.px[j * CANVAS_W + i])
			out[n], out[n + 1], out[n + 2], out[n + 3] = rgba.r, rgba.g, rgba.b, rgba.a
			n += 4
		}
	}
}

// The state of drawing: the paint and brush chosen, the stroke in progress, and the
// strokes that can be taken back.
Paint :: struct {
	color:      u8, // the palette entry, 0 for the eraser
	size:       int, // which of the brushes
	stroking:   bool,
	last:       [2]f32,
	undo:       [UNDO_DEPTH][CANVAS_W * CANVAS_H]u8,
	undo_count: int,
	undo_head:  int, // the oldest, where the ring starts
}

paint_init :: proc(p: ^Paint) {
	p.color = 5
	p.size = 1
	p.stroking = false
	p.undo_count = 0
	p.undo_head = 0
}

// Keeps a copy of the drawing to come back to.
paint_snapshot :: proc(p: ^Paint, c: ^Canvas) {
	slot: int
	if p.undo_count < UNDO_DEPTH {
		slot = (p.undo_head + p.undo_count) % UNDO_DEPTH
		p.undo_count += 1
	} else {
		slot = p.undo_head // the oldest makes way
		p.undo_head = (p.undo_head + 1) % UNDO_DEPTH
	}
	p.undo[slot] = c.px
}

// Starts a stroke at a pixel: the drawing is kept for the undo, and the first dab is made.
paint_stroke_begin :: proc(p: ^Paint, c: ^Canvas, x, y: f32) {
	paint_snapshot(p, c)
	p.stroking = true
	p.last = {x, y}
	table := BRUSH_SIZES
	canvas_dab(c, x, y, table[clamp(p.size, 0, len(table) - 1)], p.color)
}

// Carries the stroke on to a pixel. Nothing happens if no stroke was begun.
paint_stroke_to :: proc(p: ^Paint, c: ^Canvas, x, y: f32) {
	if !p.stroking {
		return
	}
	table := BRUSH_SIZES
	canvas_line(c, p.last.x, p.last.y, x, y, table[clamp(p.size, 0, len(table) - 1)], p.color)
	p.last = {x, y}
}

paint_stroke_end :: proc(p: ^Paint) {
	p.stroking = false
}

// Takes back the last stroke or clear. False if there is nothing to take back.
paint_undo :: proc(p: ^Paint, c: ^Canvas) -> bool {
	if p.undo_count == 0 {
		return false
	}
	p.undo_count -= 1
	slot := (p.undo_head + p.undo_count) % UNDO_DEPTH
	c.px = p.undo[slot]
	mark_dirty(c, 0, 0, CANVAS_W - 1, CANVAS_H - 1)
	return true
}

// Clears the drawing, after keeping it, so the clear can be taken back.
paint_clear :: proc(p: ^Paint, c: ^Canvas) {
	paint_snapshot(p, c)
	canvas_clear(c)
}
