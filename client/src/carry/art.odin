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
	dirty_base: u32, // the version the drawing was at when that rectangle began, so a texture knows if it has everything before it
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
		c.dirty_base = c.version
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

// What a picture of the drawing that is at version `have` needs to be brought up to
// date: nothing, the rectangle that changed, or the whole drawing. The rectangle is
// only enough if the picture has everything up to when it began. When another
// picture has already taken the rectangle, or this one is further behind, the whole
// drawing is needed, or it would be left with strokes missing.
canvas_update_for :: proc(c: ^Canvas, have: u32) -> (rect: [4]int, full: bool, any: bool) {
	if have == c.version {
		return {}, false, false
	}
	if c.has_dirty && have >= c.dirty_base {
		r, _ := canvas_dirty_take(c)
		return r, false, true
	}
	return {0, 0, CANVAS_W - 1, CANVAS_H - 1}, true, true
}

// How far to turn the picture round a balloon, as a share of a turn, so that the
// middle of the picture faces along (`dx`, `dz`) on the floor, which is the way from the
// balloon to whoever is looking at it. The picture is wrapped with its middle facing +x
// when it is not turned.
facing_turn :: proc(dx, dz: f32) -> f32 {
	return -math.atan2(dz, dx) / math.TAU
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

// The pattern that decides, pixel by pixel, which of two colors a blend uses, so a
// mix of two colors comes out as a fine, even speckle and not as a harsh line.
BAYER4 :: [16]u8{0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5}
BLEND_X :: 2 // how far the blend looks to each side of a pixel, across
BLEND_Y :: 4 // and up and down, which is twice as far because a pixel is half as high

// The colors of the palette as the blend sees them: bare rubber counts as the color
// of the rubber, so paint fades into it.
palette_rgb :: proc(i: u8) -> [3]f32 {
	c := lab.palette_color(int(i))
	return {f32(c.r), f32(c.g), f32(c.b)}
}

// One dab of the blending pen. Each pixel inside the dab, the same round shape as a
// brush makes, is moved toward the average of the pixels round it: the average color
// is found, the two nearest colors of the palette are taken, and the pixel is the nearer
// of them or the other by a pattern of dither that gets more even the nearer the average
// is to the half way. A pixel that is the same as all those round it does not change,
// so blending empty canvas or a flat color does nothing, and where two colors meet there
// is a band of the mixed colors, which is orange between red and yellow. It reads what
// the canvas was before the dab, so the result does not depend on the order of pixels.
canvas_blend_dab :: proc(c: ^Canvas, x, y, r: f32) {
	ry := 2 * r
	top := max(int(math.floor(y - ry)), 0)
	bottom := min(int(math.ceil(y + ry)), CANVAS_H - 1)
	if top > bottom {
		return
	}
	first, last := int(math.floor(x - r)), int(math.ceil(x + r - 1))
	width := last - first + 1
	if width <= 0 || width > 64 {
		return
	}
	// What each pixel is to become, worked out from the canvas as it is now.
	result: [64 * (CANVAS_H)]u8
	changed := false
	left, right := CANVAS_W, 0
	bayer := BAYER4
	for j in top ..= bottom {
		dy := (f32(j) + 0.5 - y) / ry
		if dy * dy > 1 {
			continue
		}
		half := r * math.sqrt(1 - dy * dy)
		for i in first ..= last {
			if f32(i) + 0.5 < x - half || f32(i) + 0.5 > x + half {
				continue
			}
			col := i %% CANVAS_W
			sum: [3]f32
			n: f32
			for jj in max(j - BLEND_Y, 0) ..= min(j + BLEND_Y, CANVAS_H - 1) {
				for ii in i - BLEND_X ..= i + BLEND_X {
					sum += palette_rgb(c.px[jj * CANVAS_W + ii %% CANVAS_W])
					n += 1
				}
			}
			avg := sum / n
			best, second := 0, 0
			best_d, second_d := f32(1e30), f32(1e30)
			for k in 0 ..< lab.PALETTE_SIZE {
				d := avg - palette_rgb(u8(k))
				dist := d.x * d.x + d.y * d.y + d.z * d.z
				if dist < best_d {
					second, second_d = best, best_d
					best, best_d = k, dist
				} else if dist < second_d {
					second, second_d = k, dist
				}
			}
			pick := best
			total := math.sqrt(best_d) + math.sqrt(second_d)
			if total > 0 {
				share := math.sqrt(best_d) / total // 0 when the average is a palette color, 0.5 half way
				if share > (f32(bayer[(j & 3) * 4 + (col & 3)]) + 0.5) / 16 {
					pick = second
				}
			}
			result[(j - top) * 64 + (i - first)] = u8(pick)
			old := c.px[j * CANVAS_W + col]
			if old != u8(pick) {
				changed = true
				left, right = min(left, col), max(right, col)
			}
		}
	}
	if !changed {
		return
	}
	for j in top ..= bottom {
		dy := (f32(j) + 0.5 - y) / ry
		if dy * dy > 1 {
			continue
		}
		half := r * math.sqrt(1 - dy * dy)
		for i in first ..= last {
			if f32(i) + 0.5 < x - half || f32(i) + 0.5 > x + half {
				continue
			}
			c.px[j * CANVAS_W + i %% CANVAS_W] = result[(j - top) * 64 + (i - first)]
		}
	}
	mark_dirty(c, left, top, right, bottom)
}

// A line of blending dabs from one point to another.
canvas_blend_line :: proc(c: ^Canvas, x0, y0, x1, y1, r: f32) {
	dx, dy := x1 - x0, y1 - y0
	steps := max(int(math.ceil(max(abs(dx) / (r * 0.5), abs(dy) / r))), 1)
	for k in 0 ..= steps {
		t := f32(k) / f32(steps)
		canvas_blend_dab(c, x0 + dx * t, y0 + dy * t, r)
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

// What the pen does: lays down the chosen paint, or blends what is there.
Tool :: enum u8 {
	Brush,
	Blend,
}

// The state of drawing: the paint and brush chosen, the stroke in progress, and the
// strokes that can be taken back.
Paint :: struct {
	tool:       Tool,
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
	p.tool = .Brush
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
	r := table[clamp(p.size, 0, len(table) - 1)]
	if p.tool == .Blend {
		canvas_blend_dab(c, x, y, r)
	} else {
		canvas_dab(c, x, y, r, p.color)
	}
}

// Carries the stroke on to a pixel. Nothing happens if no stroke was begun.
paint_stroke_to :: proc(p: ^Paint, c: ^Canvas, x, y: f32) {
	if !p.stroking {
		return
	}
	table := BRUSH_SIZES
	r := table[clamp(p.size, 0, len(table) - 1)]
	if p.tool == .Blend {
		canvas_blend_line(c, p.last.x, p.last.y, x, y, r)
	} else {
		canvas_line(c, p.last.x, p.last.y, x, y, r, p.color)
	}
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
