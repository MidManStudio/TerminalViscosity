// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "art_test.odin"
// ============================================================================

package carry

import "../lab"
import "core:math"
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

@(test)
a_picture_gets_the_rectangle_only_when_it_has_everything_before_it :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_dab(c, 50, 50, 4, 3)
	have := c.version
	_, _, needed := canvas_update_for(c, have)
	testing.expect(t, !needed, "up to date needs nothing")

	canvas_dab(c, 100, 100, 4, 3)
	rect, full, any := canvas_update_for(c, have)
	testing.expect(t, any && !full, "the rectangle is enough for a picture that was up to date before it")
	testing.expect(t, rect[0] <= 100 && rect[2] >= 100 && rect[1] <= 100 && rect[3] >= 100, "and it holds the change")
	// The rectangle is taken, so another picture that is as far behind needs it all.
	rect2, full2, any2 := canvas_update_for(c, have)
	testing.expect(t, any2 && full2, "a second picture is sent the whole drawing")
	testing.expect_value(t, rect2, [4]int{0, 0, CANVAS_W - 1, CANVAS_H - 1})
}

@(test)
a_picture_that_is_further_behind_needs_the_whole_drawing :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_dab(c, 50, 50, 4, 3)
	old := c.version
	canvas_dab(c, 100, 100, 4, 3)
	_, _, _ = canvas_update_for(c, c.version - 1) // another picture takes the rectangle
	canvas_dab(c, 150, 150, 4, 3)
	_, full, any := canvas_update_for(c, old) // this one missed the change in between
	testing.expect(t, any && full, "it cannot be given just the last rectangle")
}

@(test)
the_middle_of_the_picture_faces_whoever_looks :: proc(t: ^testing.T) {
	testing.expect_value(t, facing_turn(1, 0), 0)
	testing.expect(t, abs(facing_turn(0, 1) + 0.25) < 1e-5, "from the south")
	testing.expect(t, abs(facing_turn(0, -1) - 0.25) < 1e-5, "from the north")
	testing.expect(t, abs(abs(facing_turn(-1, 0)) - 0.5) < 1e-5, "from the west")
	// What the shader does: the picture's middle is at u 0.5 on the side that faces the viewer.
	for k in 0 ..< 36 {
		a := f32(k) * 0.17
		dx, dz := math.cos(a), math.sin(a)
		u := math.atan2(dz, dx) / math.TAU + 0.5 + facing_turn(dx, dz)
		testing.expect(t, abs(u - 0.5) < 1e-4, "the middle of the picture is toward the viewer from any side")
	}
}

// Fills the pixels from `x0` up to but not including `x1`, on every row, with a color.
fill_columns :: proc(c: ^Canvas, x0, x1: int, color: u8) {
	for j in 0 ..< CANVAS_H {
		for i in x0 ..< x1 {
			c.px[j * CANVAS_W + i] = color
		}
	}
}

@(test)
blending_red_and_yellow_makes_the_colors_between_where_they_meet :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	fill_columns(c, 0, 128, 5) // red
	fill_columns(c, 128, 256, 7) // yellow
	for k in 0 ..< 6 {
		canvas_blend_dab(c, 128, 128, 10)
		canvas_blend_dab(c, 124 + f32(k), 120, 10)
	}
	between := 0
	for j in 100 ..< 156 {
		for i in 118 ..< 138 {
			if c.px[j * CANVAS_W + i] == 6 { // orange
				between += 1
			}
		}
	}
	testing.expect(t, between > 20, "orange appears where red meets yellow")
	testing.expect_value(t, c.px[128 * CANVAS_W + 20], 5) // far from the blend nothing changed
	testing.expect_value(t, c.px[128 * CANVAS_W + 230], 7)
	testing.expect_value(t, c.px[10 * CANVAS_W + 128], 7) // and outside the dab, up the boundary, too
	testing.expect_value(t, c.px[245 * CANVAS_W + 126], 5)
}

@(test)
blending_a_flat_color_or_empty_canvas_changes_nothing :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	canvas_blend_dab(c, 100, 100, 10)
	testing.expect_value(t, count_painted(c), 0)
	testing.expect(t, !c.has_dirty && c.version == 0, "and it is not even marked as changed")
	fill_columns(c, 0, 256, 9)
	before := c.px
	canvas_blend_dab(c, 100, 100, 10)
	testing.expect(t, c.px == before, "a flat color stays flat")
}

@(test)
blending_changes_only_inside_the_dab_and_marks_what_it_changed :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	fill_columns(c, 0, 128, 5)
	fill_columns(c, 128, 256, 7)
	before := c.px
	canvas_blend_dab(c, 128, 128, 5)
	rect, ok := canvas_dirty_take(c)
	testing.expect(t, ok, "something changed")
	changed := 0
	for j in 0 ..< CANVAS_H {
		for i in 0 ..< CANVAS_W {
			if c.px[j * CANVAS_W + i] != before[j * CANVAS_W + i] {
				changed += 1
				inside := i >= rect[0] && i <= rect[2] && j >= rect[1] && j <= rect[3]
				testing.expect(t, inside, "every pixel that changed is in the rectangle")
				dx, dy := (f32(i) + 0.5 - 128) / 5, (f32(j) + 0.5 - 128) / 10
				testing.expect(t, dx * dx + dy * dy <= 1.01, "and inside the dab")
			}
		}
	}
	testing.expect(t, changed > 0, "the meeting was blended")
}

@(test)
blending_works_across_the_seam :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	fill_columns(c, 0, 128, 5)
	fill_columns(c, 128, 256, 7)
	// The edges of the canvas are one meridian, red at the left and yellow at the right.
	for k in 0 ..< 6 {
		canvas_blend_dab(c, 0.5, 128, 10)
		canvas_blend_dab(c, 255.5, 130 - f32(k), 10)
	}
	left_side, right_side := 0, 0
	for j in 100 ..< 156 {
		for i in 0 ..< 6 {
			if c.px[j * CANVAS_W + i] == 6 {
				left_side += 1
			}
		}
		for i in 250 ..< 256 {
			if c.px[j * CANVAS_W + i] == 6 {
				right_side += 1
			}
		}
	}
	testing.expect(t, c.px[128 * CANVAS_W] != 7, "the pixel at the very left is a mix, not all yellow, so it saw the red beside it too")
	testing.expect(t, c.px[128 * CANVAS_W + 255] != 5, "and the one at the very right is not all red")
	testing.expect(t, left_side > 5, "red at the left edge took some of the yellow from across the seam")
	testing.expect(t, right_side > 5, "and yellow at the right edge took some of the red")
}

@(test)
blending_works_up_and_down_too :: proc(t: ^testing.T) {
	c := new_canvas()
	defer free(c)
	for j in 0 ..< CANVAS_H {
		for i in 0 ..< CANVAS_W {
			c.px[j * CANVAS_W + i] = j < 128 ? 5 : 7 // red above, yellow below
		}
	}
	for k in 0 ..< 6 {
		canvas_blend_dab(c, 100 + f32(k) * 4, 128, 10)
	}
	between := 0
	for j in 110 ..< 146 {
		for i in 90 ..< 130 {
			if c.px[j * CANVAS_W + i] == 6 {
				between += 1
			}
		}
	}
	testing.expect(t, between > 20, "orange where the red meets the yellow, whichever way the edge runs")
	testing.expect_value(t, c.px[20 * CANVAS_W + 100], 5)
	testing.expect_value(t, c.px[240 * CANVAS_W + 100], 7)
}

@(test)
the_blending_pen_lays_down_no_paint_of_its_own_and_can_be_taken_back :: proc(t: ^testing.T) {
	c, p := new_canvas(), new_paint()
	defer free(c)
	defer free(p)
	fill_columns(c, 0, 128, 5)
	fill_columns(c, 128, 256, 7)
	before := c.px
	p.tool, p.color, p.size = .Blend, 9, 2 // green is chosen, which must not be put down
	paint_stroke_begin(p, c, 100, 128)
	paint_stroke_to(p, c, 160, 128)
	paint_stroke_end(p)
	testing.expect(t, c.px != before, "it blended")
	green := 0
	for px in c.px {
		if px == 9 {
			green += 1
		}
	}
	testing.expect_value(t, green, 0)
	testing.expect(t, paint_undo(p, c), "a blend is taken back")
	testing.expect(t, c.px == before, "to what it was")
	p.tool = .Brush
	paint_stroke_begin(p, c, 100, 128)
	paint_stroke_end(p)
	testing.expect_value(t, c.px[128 * CANVAS_W + 100], 9) // and with the brush the chosen paint goes down
}
