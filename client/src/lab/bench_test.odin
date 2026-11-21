// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "bench_test.odin"
// ============================================================================

package lab

import "core:testing"

@(test)
the_bench_as_the_lab_starts_has_the_stations_where_they_have_always_stood :: proc(t: ^testing.T) {
	b := default_bench()
	testing.expect_value(t, b.spots[1], Bench_Kind.Hot_Plate)
	testing.expect_value(t, b.spots[2], Bench_Kind.Ice_Bath)
	testing.expect_value(t, b.spots[4], Bench_Kind.Scale)
	for i in 0 ..< BENCH_SPOTS {
		if i != 1 && i != 2 && i != 4 {
			testing.expect_value(t, b.spots[i], Bench_Kind.None)
		}
	}
	testing.expect(t, rect_near(bench_rect(.Hot_Plate, 1), HOT_PLATE), "the hot plate where it was")
	testing.expect(t, rect_near(bench_rect(.Ice_Bath, 2), ICE_BATH), "the ice bath where it was")
	testing.expect(t, rect_near(bench_rect(.Scale, 4), SCALE_PLATE), "the scale where it was")
}

rect_near :: proc(a, b: Rect) -> bool {
	near :: proc(x, y: f32) -> bool {
		return abs(x - y) < 1e-5
	}
	return near(a.min_x, b.min_x) && near(a.min_z, b.min_z) && near(a.max_x, b.max_x) && near(a.max_z, b.max_z)
}

@(test)
the_spots_are_apart_and_clear_of_the_hood_and_the_oven :: proc(t: ^testing.T) {
	for i in 0 ..< BENCH_SPOTS {
		wide := bench_rect(.Ice_Bath, i) // the widest station
		testing.expect(t, wide.min_x > HOOD.max_x, "east of the hood")
		testing.expect(t, wide.max_x < MIXER.min_x, "west of the oven")
		if i > 0 {
			prev := bench_rect(.Ice_Bath, i - 1)
			testing.expect(t, wide.min_x > prev.max_x, "clear of the one before")
		}
		for kind in ([3]Bench_Kind{.Hot_Plate, .Ice_Bath, .Scale}) {
			r := bench_rect(kind, i)
			testing.expect(t, r.min_z >= -7.9 && r.max_z <= -7.3, "along the back of the north counter")
		}
	}
}

@(test)
a_spot_that_does_not_exist_is_the_nearest_one :: proc(t: ^testing.T) {
	testing.expect_value(t, bench_spot_x(-4), bench_spot_x(0))
	testing.expect_value(t, bench_spot_x(99), bench_spot_x(BENCH_SPOTS - 1))
}

@(test)
a_point_is_on_a_station_only_where_one_of_that_kind_stands :: proc(t: ^testing.T) {
	b := default_bench()
	r := bench_rect(.Hot_Plate, 1)
	mx, mz := (r.min_x + r.max_x) * 0.5, (r.min_z + r.max_z) * 0.5
	testing.expect(t, on_bench(&b, .Hot_Plate, mx, mz), "on the plate")
	testing.expect(t, !on_bench(&b, .Ice_Bath, mx, mz), "not the bath")
	testing.expect(t, !on_bench(&b, .Scale, mx, mz), "nor the scale")
	// Move the plate to spot 0: the old place is bare and the new one is on it.
	b.spots[1], b.spots[0] = .None, .Hot_Plate
	testing.expect(t, !on_bench(&b, .Hot_Plate, mx, mz), "the old place is bare")
	r0 := bench_rect(.Hot_Plate, 0)
	testing.expect(t, on_bench(&b, .Hot_Plate, (r0.min_x + r0.max_x) * 0.5, mz), "the new place has it")
	testing.expect(t, !on_bench(&b, .Hot_Plate, r0.max_x + 0.05, mz), "just past its edge is not on it")
	testing.expect(t, !on_bench(&b, .Hot_Plate, mx, mz + 1), "nor is the middle of the room")
}

@(test)
the_aim_box_of_a_station_covers_its_footprint_and_its_height :: proc(t: ^testing.T) {
	for kind in ([3]Bench_Kind{.Hot_Plate, .Ice_Bath, .Scale}) {
		for i in 0 ..< BENCH_SPOTS {
			r := bench_rect(kind, i)
			low, high := bench_aim_box(kind, i)
			testing.expect(t, low.x <= r.min_x && high.x >= r.max_x, "across")
			testing.expect(t, low.z <= r.min_z && high.z >= r.max_z, "and along")
			testing.expect_value(t, low.y, COUNTER_HEIGHT)
			testing.expect(t, high.y > COUNTER_HEIGHT + 0.05, "and up")
		}
	}
	// The scale's box is the one it has always had, at its spot.
	low, high := bench_aim_box(.Scale, 4)
	testing.expect_value(t, low, SCALE_AIM_LOW)
	testing.expect_value(t, high, SCALE_AIM_HIGH)
}

@(test)
the_bench_builds_each_station_and_a_plate_for_each_empty_spot :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	before := l.box_count
	add_bench(l, default_bench())
	// The hot plate's two, the ice bath's eight, the scale's four, and a plate at each of the three empty spots.
	testing.expect_value(t, l.box_count - before, 2 + 8 + 4 + 3)
	build(l)
	before = l.box_count
	add_bench(l, Bench{})
	testing.expect_value(t, l.box_count - before, BENCH_SPOTS) // nothing but plates
	build(l)
	before = l.box_count
	full := Bench{{.Scale, .Scale, .Hot_Plate, .Ice_Bath, .None, .Scale}}
	add_bench(l, full)
	testing.expect_value(t, l.box_count - before, 4 + 4 + 2 + 8 + 1 + 4)
}

@(test)
a_station_is_built_where_its_spot_is :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	before := l.box_count
	b: Bench
	b.spots[5] = .Hot_Plate
	add_bench(l, b)
	r := bench_rect(.Hot_Plate, 5)
	found := false
	for i in before ..< l.box_count {
		bx := l.boxes[i]
		if bx.size.y > 0.03 && bx.size.y < 0.05 && bx.size.x > 0.55 { // the body of the plate
			found = true
			testing.expect(t, bx.center.x > r.min_x && bx.center.x < r.max_x, "over its spot")
		}
	}
	testing.expect(t, found, "the plate is there")
}
