// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "paint_layout_test.odin"
// ============================================================================

package carry

import "core:testing"

SCREENS :: [?][2]f32{{1280, 720}, {1600, 720}, {2400, 1080}, {960, 540}, {1920, 1080}, {2340, 1080}, {800, 600}}

inside_screen :: proc(b: [4]f32, w, h: f32) -> bool {
	return b[0] >= 0 && b[1] >= 0 && b[0] + b[2] <= w + 0.01 && b[1] + b[3] <= h + 0.01 && b[2] > 0 && b[3] > 0
}

overlaps :: proc(a, b: [4]f32) -> bool {
	return a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3]
}

@(test)
everything_is_on_the_screen_and_the_tablet_is_twice_as_wide_as_high :: proc(t: ^testing.T) {
	for sc in SCREENS {
		l := paint_layout(sc.x, sc.y)
		testing.expect(t, inside_screen(l.canvas, sc.x, sc.y), "the tablet")
		testing.expect(t, abs(l.canvas[2] - 2 * l.canvas[3]) < 0.01, "twice as wide as high")
		testing.expect(t, inside_screen(l.done, sc.x, sc.y), "the done button")
		testing.expect(t, inside_screen(l.undo, sc.x, sc.y) && inside_screen(l.clear, sc.x, sc.y) && inside_screen(l.blend, sc.x, sc.y), "blend, undo, and clear")
		testing.expect(t, l.clear[0] + l.clear[2] <= l.canvas[0] + l.canvas[2] + 0.01, "and the row of them stops at the edge of the tablet")
		testing.expect(t, inside_screen(l.balloon, sc.x, sc.y), "the balloon area")
		for k in 0 ..< len(l.swatches) {
			testing.expect(t, inside_screen(l.swatches[k], sc.x, sc.y), "a swatch")
		}
		for k in 0 ..< len(l.sizes) {
			testing.expect(t, inside_screen(l.sizes[k], sc.x, sc.y), "a brush")
		}
		testing.expect(t, l.canvas[2] > sc.x * 0.3, "big enough to draw on")
	}
}

@(test)
nothing_covers_anything_else :: proc(t: ^testing.T) {
	for sc in SCREENS {
		l := paint_layout(sc.x, sc.y)
		groups: [dynamic][4]f32
		defer delete(groups)
		append(&groups, l.canvas, l.undo, l.clear, l.blend, l.done, l.balloon)
		for s in l.swatches {
			append(&groups, s)
		}
		for s in l.sizes {
			append(&groups, s)
		}
		for a in 0 ..< len(groups) {
			for b in a + 1 ..< len(groups) {
				testing.expect(t, !overlaps(groups[a], groups[b]), "no two overlap")
			}
		}
	}
}

@(test)
a_touch_is_on_the_thing_under_it :: proc(t: ^testing.T) {
	l := paint_layout(1600, 720)
	centre :: proc(b: [4]f32) -> (f32, f32) {
		return b[0] + b[2] * 0.5, b[1] + b[3] * 0.5
	}
	x, y := centre(l.done)
	kind, _ := paint_hit(&l, x, y)
	testing.expect_value(t, kind, Hit_Kind.Done)
	x, y = centre(l.undo)
	kind, _ = paint_hit(&l, x, y)
	testing.expect_value(t, kind, Hit_Kind.Undo)
	x, y = centre(l.clear)
	kind, _ = paint_hit(&l, x, y)
	testing.expect_value(t, kind, Hit_Kind.Clear)
	x, y = centre(l.blend)
	kind, _ = paint_hit(&l, x, y)
	testing.expect_value(t, kind, Hit_Kind.Blend)
	for k in 0 ..< len(l.sizes) {
		x, y = centre(l.sizes[k])
		got, i := paint_hit(&l, x, y)
		testing.expect(t, got == .Size && i == k, "each brush")
	}
	for k in 0 ..< len(l.swatches) {
		x, y = centre(l.swatches[k])
		got, i := paint_hit(&l, x, y)
		testing.expect(t, got == .Swatch && i == k, "each swatch")
	}
	x, y = centre(l.canvas)
	kind, _ = paint_hit(&l, x, y)
	testing.expect_value(t, kind, Hit_Kind.Canvas)
	x, y = centre(l.balloon)
	kind, _ = paint_hit(&l, x, y)
	testing.expect_value(t, kind, Hit_Kind.Balloon)
	kind, _ = paint_hit(&l, 1, 715) // the corner is none of them
	testing.expect_value(t, kind, Hit_Kind.None)
}

@(test)
the_edges_of_the_tablet_are_the_edges_of_the_drawing :: proc(t: ^testing.T) {
	l := paint_layout(1600, 720)
	tx, ty, in_ := canvas_texel(&l, l.canvas[0], l.canvas[1])
	testing.expect(t, in_ && tx == 0 && ty == 0, "the top left")
	tx, ty, in_ = canvas_texel(&l, l.canvas[0] + l.canvas[2], l.canvas[1] + l.canvas[3])
	testing.expect(t, in_ && abs(tx - CANVAS_W) < 1e-3 && abs(ty - CANVAS_H) < 1e-3, "the bottom right")
	tx, ty, in_ = canvas_texel(&l, l.canvas[0] + l.canvas[2] * 0.5, l.canvas[1] + l.canvas[3] * 0.5)
	testing.expect(t, abs(tx - CANVAS_W * 0.5) < 1e-3 && abs(ty - CANVAS_H * 0.5) < 1e-3, "the middle")
	_, _, in_ = canvas_texel(&l, l.canvas[0] - 5, l.canvas[1] + 10)
	testing.expect(t, !in_, "outside the tablet")
}

@(test)
the_balloon_is_on_the_left_of_the_screen :: proc(t: ^testing.T) {
	for sc in SCREENS {
		l := paint_layout(sc.x, sc.y)
		n := balloon_ndc(&l, sc.x)
		testing.expect(t, n < -0.2 && n > -1, "to the left of the middle and on the screen")
	}
}

inside_box :: proc(inner, outer: [4]f32) -> bool {
	return inner[0] >= outer[0] - 0.01 && inner[1] >= outer[1] - 0.01 && inner[0] + inner[2] <= outer[0] + outer[2] + 0.01 && inner[1] + inner[3] <= outer[1] + outer[3] + 0.01
}

@(test)
everything_to_draw_with_is_down_the_right_side_and_the_balloon_and_done_are_on_the_left :: proc(t: ^testing.T) {
	for sc in SCREENS {
		l := paint_layout(sc.x, sc.y)
		// The balloon area ends before the tablet begins, so nothing is over the balloon.
		testing.expect(t, l.balloon[0] + l.balloon[2] + sc.y * 0.02 <= l.panel[0], "the balloon is left of the panel, with a gap")
		testing.expect(t, l.done[0] + l.done[2] <= l.canvas[0], "and so is the done button")
		testing.expect(t, l.done[0] < sc.x * 0.2 && l.done[1] < sc.y * 0.1, "the done button is in the top left corner")
		// The palette is to the right of the tablet, with the first swatch in its left column.
		for k in 0 ..< len(l.swatches) {
			testing.expect(t, l.swatches[k][0] >= l.canvas[0] + l.canvas[2] + sc.y * 0.02, "a swatch is right of the tablet, with a gap")
		}
		testing.expect(t, l.swatches[0][0] < l.swatches[1][0] && l.swatches[0][1] == l.swatches[1][1], "swatch 0 is left of swatch 1, as before")
		testing.expect(t, l.swatches[1][0] + l.swatches[1][2] <= sc.x, "and the palette stops at the edge of the screen")
		// The backing covers all the tools and none of the balloon or the done button.
		testing.expect(t, inside_box(l.canvas, l.panel) && inside_box(l.undo, l.panel) && inside_box(l.clear, l.panel) && inside_box(l.blend, l.panel), "the panel backs the tablet and its buttons")
		for k in 0 ..< len(l.swatches) {
			testing.expect(t, inside_box(l.swatches[k], l.panel), "and the palette")
		}
		for k in 0 ..< len(l.sizes) {
			testing.expect(t, inside_box(l.sizes[k], l.panel), "and the brushes")
		}
		testing.expect(t, !overlaps(l.balloon, l.panel) && !overlaps(l.done, l.panel), "but not the balloon or the done button")
		testing.expect(t, abs(l.panel[0] + l.panel[2] - sc.x) < 0.01 && l.panel[3] == sc.y, "the panel runs to the right edge and the full height")
	}
}

@(test)
the_tablet_does_not_vanish_on_a_screen_that_is_nearly_square :: proc(t: ^testing.T) {
	// Not a shape the game is played on. But when the balloon takes what it needs, the tablet
	// stops at 0.3 of the width and is still a tablet, and the layout does not run off the screen.
	l := paint_layout(600, 600)
	testing.expect(t, abs(l.canvas[2] - 180) < 0.01, "the tablet stops at 0.3 of the width")
	testing.expect(t, inside_screen(l.canvas, 600, 600) && abs(l.canvas[2] - 2 * l.canvas[3]) < 0.01, "and is still on the screen and twice as wide as high")
	l = paint_layout(800, 600)
	testing.expect(t, l.canvas[2] > 240 && l.canvas[2] < 400, "a 4 by 3 screen gets a smaller tablet than the 2 by 1 phone, so the balloon fits")
}

@(test)
the_balloon_has_room_on_every_screen :: proc(t: ^testing.T) {
	for sc in SCREENS {
		l := paint_layout(sc.x, sc.y)
		testing.expect(t, l.balloon[2] >= sc.y * 0.55, "wide enough to see and turn a balloon in: 0.55 of the screen height")
		testing.expect(t, l.balloon[3] > sc.y * 0.5, "and tall enough")
		testing.expect(t, l.canvas[2] >= sc.x * 0.3 - 0.01, "without taking the tablet down below 0.3 of the width")
		testing.expect(t, abs(l.canvas[2] - 2 * l.canvas[3]) < 0.01, "and it is still twice as wide as high")
	}
}
