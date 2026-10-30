// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "art_test.odin"
// ============================================================================

package carry

import "../lab"
import "core:testing"

new_canvas :: proc() -> ^Canvas {
	return new(Canvas)
}

painted :: proc(c: ^Canvas, x, y: int) -> bool {
	return c.px[y * CANVAS_W + x] != 0
}

count_painted :: proc(c: ^Canvas) -> int {
	n := 0
	for p in c.px {
		if p != 0 {
			n += 1
		}
	}
	return n
}

@(test)
a_dab_is_a_round_spot_twice_as_high_as_wide_in_pixels :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_dab(c, 100, 100, 5, 7)
	area := count_painted(c)
	testing.expect(t, area > 135 && area < 180, "about the area of an ellipse of 5 by 10")
	testing.expect(t, painted(c, 100, 100), "the middle")
	testing.expect(t, painted(c, 100 + 4, 100) && !painted(c, 100 + 6, 100), "5 wide to each side")
	testing.expect(t, painted(c, 100, 100 + 9) && !painted(c, 100, 100 + 11), "10 high to each side")
	testing.expect(t, !painted(c, 100 + 4, 100 + 8), "round, not square: the corner is empty")
	testing.expect_value(t, c.px[100 * CANVAS_W + 100], 7)
}

@(test)
a_dab_at_the_seam_comes_in_on_the_other_side :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_dab(c, 1, 100, 5, 3)
	testing.expect(t, painted(c, 0, 100) && painted(c, 255, 100) && painted(c, 253, 100), "across the left edge")
	testing.expect(t, !painted(c, 240, 100), "and no further")
	right := new_canvas()
	defer free(right)
	canvas_dab(right, 254.5, 100, 5, 3)
	testing.expect(t, painted(right, 255, 100) && painted(right, 0, 100) && painted(right, 2, 100), "across the right edge")
	testing.expect_value(t, c.dirty[0], 0)
	testing.expect_value(t, c.dirty[2], CANVAS_W - 1) // the change spans the seam, so it is the whole width
}

@(test)
a_dab_at_the_top_or_bottom_is_cut_off_and_nothing_is_outside :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_dab(c, 100, 1, 5, 3)
	canvas_dab(c, 100, CANVAS_H - 1, 5, 3)
	canvas_dab(c, 100, -50, 5, 3) // wholly off
	canvas_dab(c, 100, CANVAS_H + 50, 5, 3)
	testing.expect(t, painted(c, 100, 0) && painted(c, 100, CANVAS_H - 1), "the ends")
	n := count_painted(c)
	testing.expect(t, n > 2 * 60 && n < 2 * 110, "only the part that is on the canvas, a little over half of each")
}

@(test)
what_changed_is_inside_the_dirty_rectangle_and_the_version_goes_up :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	testing.expect_value(t, c.version, 0)
	_, any := canvas_dirty_take(c)
	testing.expect(t, !any, "nothing yet")
	before := c.px
	canvas_dab(c, 30, 40, 4, 2)
	canvas_dab(c, 200, 180, 8, 9)
	canvas_line(c, 60, 60, 120, 90, 3, 5)
	testing.expect(t, c.version >= 3, "each change goes up by one")
	rect, ok := canvas_dirty_take(c)
	testing.expect(t, ok, "something changed")
	for j in 0 ..< CANVAS_H {
		for i in 0 ..< CANVAS_W {
			if c.px[j * CANVAS_W + i] != before[j * CANVAS_W + i] {
				inside := i >= rect[0] && i <= rect[2] && j >= rect[1] && j <= rect[3]
				testing.expect(t, inside, "every pixel that changed is in the rectangle")
			}
		}
	}
	_, again := canvas_dirty_take(c)
	testing.expect(t, !again, "taking it forgets it")
}

@(test)
a_line_leaves_no_gaps_and_goes_straight :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_line(c, 20, 50, 200, 50, 2, 4)
	for x in 20 ..= 200 {
		testing.expect(t, painted(c, x, 50), "no gap on the way")
	}
	d := new_canvas()
	defer free(d)
	canvas_line(d, 10, 10, 200, 160, 2, 4)
	for k in 0 ..= 100 {
		x, y := 10 + 190 * k / 100, 10 + 150 * k / 100
		testing.expect(t, painted(d, x, y), "no gap on a slant")
	}
	e := new_canvas()
	defer free(e)
	canvas_line(e, 250, 100, 5, 100, 2, 4) // right across, not the short way round the seam
	testing.expect(t, painted(e, 128, 100), "the middle of the canvas is painted")
	testing.expect(t, !painted(e, 253, 130), "and it is only a line")
}

@(test)
the_eraser_takes_paint_off_and_clear_takes_all_of_it :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_dab(c, 100, 100, 6, 5)
	testing.expect(t, painted(c, 100, 100), "painted")
	canvas_dab(c, 100, 100, 3, 0)
	testing.expect(t, !painted(c, 100, 100), "erased in the middle")
	testing.expect(t, painted(c, 100 + 5, 100), "and not outside the eraser")
	canvas_clear(c)
	testing.expect_value(t, count_painted(c), 0)
	rect, ok := canvas_dirty_take(c)
	testing.expect(t, ok && rect == [4]int{0, 0, CANVAS_W - 1, CANVAS_H - 1}, "the whole canvas changed")
}

@(test)
pixels_become_rgba_with_no_paint_see_through :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	c.px[10 * CANVAS_W + 20] = 5
	c.px[10 * CANVAS_W + 21] = 0
	c.px[11 * CANVAS_W + 20] = 9
	out: [3 * 2 * 4]u8
	canvas_to_rgba(c, 19, 10, 21, 11, out[:])
	testing.expect_value(t, out[1 * 4 + 3], 255) // (20, 10) is paint
	want := lab.palette_color(5)
	testing.expect_value(t, [4]u8{out[4], out[5], out[6], out[7]}, want)
	testing.expect_value(t, out[0 * 4 + 3], 0) // (19, 10) is bare rubber
	testing.expect_value(t, out[2 * 4 + 3], 0) // (21, 10) was erased
	testing.expect_value(t, [4]u8{out[(3 + 1) * 4], out[(3 + 1) * 4 + 1], out[(3 + 1) * 4 + 2], out[(3 + 1) * 4 + 3]}, lab.palette_color(9)) // (20, 11), the next row
	testing.expect_value(t, palette_rgba(0).a, 0)
	testing.expect_value(t, palette_rgba(15).a, 255)
}

@(test)
the_store_gives_out_ids_from_one_and_runs_out :: proc(t: ^testing.T) {
	s := new(Art_Store)
	defer free(s)
	testing.expect(t, art_get(s, 0) == nil, "0 is no drawing")
	testing.expect(t, art_get(s, 1) == nil, "none made yet")
	seen: [ART_POOL + 1]bool
	for _ in 0 ..< ART_POOL {
		id := art_new(s)
		testing.expect(t, id >= 1 && int(id) <= ART_POOL, "from 1")
		testing.expect(t, !seen[id], "no id twice")
		seen[id] = true
		testing.expect(t, art_get(s, id) != nil, "and there is a drawing for it")
	}
	testing.expect_value(t, art_new(s), 0) // full
	testing.expect(t, art_get(s, u16(ART_POOL + 1)) == nil, "out of range")
	canvas_dab(art_get(s, 5), 100, 100, 5, 3)
	art_free(s, 5)
	testing.expect(t, art_get(s, 5) == nil, "freed")
	again := art_new(s)
	testing.expect_value(t, again, 5) // the free one is the one given
	testing.expect_value(t, count_painted(art_get(s, again)), 0) // and it is blank
	art_free(s, 0) // harmless
	art_free(s, 99)
}

new_paint :: proc() -> ^Paint {
	p := new(Paint)
	paint_init(p)
	return p
}

@(test)
a_stroke_paints_with_the_chosen_color_and_brush :: proc(t: ^testing.T) {
	c, p := new_canvas(), new_paint()
	defer free(c)
	defer free(p)
	p.color, p.size = 9, 2
	paint_stroke_begin(p, c, 100, 100)
	paint_stroke_to(p, c, 160, 100)
	paint_stroke_end(p)
	testing.expect_value(t, c.px[100 * CANVAS_W + 130], 9)
	testing.expect(t, painted(c, 100, 100 + 19) && !painted(c, 100, 100 + 22), "the biggest brush, 10 wide and 20 high")
	small := new_canvas()
	defer free(small)
	p.size = 0
	paint_stroke_begin(p, small, 100, 100)
	testing.expect(t, painted(small, 100, 100 + 3) && !painted(small, 100, 100 + 5), "the smallest, 2 wide and 4 high")
}

@(test)
moving_without_a_stroke_paints_nothing :: proc(t: ^testing.T) {
	c, p := new_canvas(), new_paint()
	defer free(c)
	defer free(p)
	paint_stroke_to(p, c, 160, 100)
	testing.expect_value(t, count_painted(c), 0)
	paint_stroke_begin(p, c, 10, 10)
	paint_stroke_end(p)
	n := count_painted(c)
	paint_stroke_to(p, c, 160, 100)
	testing.expect_value(t, count_painted(c), n) // a finished stroke is not carried on
}

@(test)
undo_takes_back_strokes_in_order_and_to_the_depth_it_keeps :: proc(t: ^testing.T) {
	c, p := new_canvas(), new_paint()
	defer free(c)
	defer free(p)
	testing.expect(t, !paint_undo(p, c), "nothing to take back")
	states := new([UNDO_DEPTH + 3][CANVAS_W * CANVAS_H]u8)
	defer free(states)
	for k in 0 ..< UNDO_DEPTH + 3 {
		states[k] = c.px // what it was before stroke k
		paint_stroke_begin(p, c, f32(20 + 20 * k), 100)
		paint_stroke_to(p, c, f32(30 + 20 * k), 150)
		paint_stroke_end(p)
	}
	for k := UNDO_DEPTH + 2; k >= 3; k -= 1 {
		testing.expect(t, paint_undo(p, c), "taken back")
		testing.expect(t, c.px == states[k], "to exactly what it was before that stroke")
	}
	testing.expect(t, !paint_undo(p, c), "only the last eight are kept")
	testing.expect(t, c.px == states[3], "the oldest kept is what it was before the fourth stroke")
}

@(test)
a_clear_can_be_taken_back :: proc(t: ^testing.T) {
	c, p := new_canvas(), new_paint()
	defer free(c)
	defer free(p)
	paint_stroke_begin(p, c, 100, 100)
	paint_stroke_end(p)
	drawn := c.px
	paint_clear(p, c)
	testing.expect_value(t, count_painted(c), 0)
	testing.expect(t, paint_undo(p, c), "the clear is taken back")
	testing.expect(t, c.px == drawn, "and the drawing is back")
	testing.expect(t, paint_undo(p, c), "and the stroke before it")
	testing.expect_value(t, count_painted(c), 0)
}
