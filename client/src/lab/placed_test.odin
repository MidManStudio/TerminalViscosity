// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "placed_test.odin"
// ============================================================================

package lab

import "core:strings"
import "core:testing"

// Whether two numbers are the same to a tenth of a millimetre.
placed_close :: proc(a, b: f32) -> bool {
	return abs(a - b) < 1e-4
}

placed_rect_close :: proc(a, b: Rect) -> bool {
	return placed_close(a.min_x, b.min_x) && placed_close(a.min_z, b.min_z) && placed_close(a.max_x, b.max_x) && placed_close(a.max_z, b.max_z)
}

// The lab with nothing on its counters but the fixtures, as `add_apparatus_with` makes it.
placed_lab_without_stations :: proc() -> ^Layout {
	l := new(Layout)
	build(l)
	add_apparatus_with(l, {})
	return l
}

@(test)
the_stations_start_where_they_have_always_stood :: proc(t: ^testing.T) {
	p := default_placed()
	testing.expect_value(t, p.count, 7)
	testing.expect_value(t, p.items[0].kind, Station_Kind.Hot_Plate)
	testing.expect_value(t, p.items[1].kind, Station_Kind.Ice_Bath)
	testing.expect_value(t, p.items[2].kind, Station_Kind.Scale)
	testing.expect_value(t, p.items[3], Placement{.Incinerator, 10.5, 7.63, 0})
	testing.expect_value(t, p.items[4], Placement{.Hood, -6.0, -7.63, 0})
	testing.expect_value(t, p.items[5], Placement{.Filler, 6.0, 7.63, 0})
	testing.expect_value(t, p.items[6], Placement{.Oven, 3.0, -7.63, 0})
	testing.expect(t, placed_rect_close(world_plate(p.items[0]), HOT_PLATE), "the hot plate is where HOT_PLATE is")
	testing.expect(t, placed_rect_close(world_plate(p.items[1]), ICE_BATH), "the ice bath is where ICE_BATH is")
	testing.expect(t, placed_rect_close(world_plate(p.items[2]), SCALE_PLATE), "the scale plate is where SCALE_PLATE is")
	for i in 7 ..< MAX_PLACED {
		testing.expect_value(t, p.items[i], Placement{})
	}
}

@(test)
the_starting_stations_can_all_stand_where_they_start :: proc(t: ^testing.T) {
	d := default_placed()
	built: Placed
	for i in 0 ..< d.count {
		pl := d.items[i]
		testing.expect_value(t, can_place(&built, pl.kind, pl.x, pl.z, pl.quarter), Place_Problem.None)
		testing.expect(t, placed_add(&built, pl), "added")
	}
	testing.expect_value(t, built, d)
}

@(test)
a_station_added_or_taken_away_leaves_the_rest_in_order_and_the_slot_clear :: proc(t: ^testing.T) {
	p := default_placed()
	n := p.count
	gone := placed_remove(&p, 1)
	testing.expect_value(t, gone.kind, Station_Kind.Ice_Bath)
	testing.expect_value(t, p.count, n - 1)
	testing.expect_value(t, p.items[0].kind, Station_Kind.Hot_Plate)
	testing.expect_value(t, p.items[1].kind, Station_Kind.Scale)
	testing.expect_value(t, p.items[2].kind, Station_Kind.Incinerator)
	testing.expect_value(t, p.items[3].kind, Station_Kind.Hood)
	testing.expect_value(t, p.items[4].kind, Station_Kind.Filler)
	testing.expect_value(t, p.items[5].kind, Station_Kind.Oven)
	testing.expect_value(t, p.items[n - 1], Placement{}) // the place that was the last is clear
	testing.expect_value(t, placed_remove(&p, n - 1), Placement{}) // there is no station there now
	testing.expect_value(t, placed_remove(&p, -1), Placement{})
	testing.expect_value(t, p.count, n - 1)
	testing.expect(t, !placed_add(&p, {.None, 0, 0, 0}), "a station of no kind is not added")
	testing.expect_value(t, p.count, n - 1)
	for i in n - 1 ..< MAX_PLACED {
		testing.expect(t, placed_add(&p, {.Hot_Plate, f32(i), 0, 0}), "room for it")
	}
	testing.expect_value(t, p.count, MAX_PLACED)
	testing.expect(t, !placed_add(&p, {.Hot_Plate, 20, 0, 0}), "no room for a ninth")
	testing.expect_value(t, p.count, MAX_PLACED)
}

@(test)
the_footprint_of_a_station_turns_with_it :: proc(t: ^testing.T) {
	testing.expect(t, placed_rect_close(turn_rect(station_plate(.Hot_Plate), 0), {-0.3, -0.25, 0.3, 0.25}), "not turned")
	testing.expect(t, placed_rect_close(turn_rect(station_plate(.Hot_Plate), 1), {-0.25, -0.3, 0.25, 0.3}), "a quarter swaps width and depth")
	testing.expect(t, placed_rect_close(turn_rect(station_plate(.Hot_Plate), 2), {-0.3, -0.25, 0.3, 0.25}), "a half turn is the same box")
	testing.expect(t, placed_rect_close(turn_rect(station_plate(.Hot_Plate), 3), {-0.25, -0.3, 0.25, 0.3}), "three quarters swaps them again")
	testing.expect(t, placed_rect_close(world_plate({.Hot_Plate, 1, 2, 1}), {0.75, 1.7, 1.25, 2.3}), "turned, and then moved")
	testing.expect(t, placed_rect_close(world_body({.Ice_Bath, -5, 3, 3}), {-5.28, 2.57, -4.72, 3.43}), "the body of a bath turned three quarters")
	testing.expect(t, placed_rect_close(world_body({.Scale, 0, 0, 0}), {-0.26, -0.25, 0.26, 0.25}), "the body of a scale")
	testing.expect(t, placed_rect_close(world_plate({.Scale, 0, 0, 0}), {-0.2, -0.175, 0.2, 0.175}), "the plate of a scale")
	testing.expect_value(t, station_height(.Hot_Plate), f32(0.07))
	testing.expect_value(t, station_height(.Ice_Bath), f32(0.09))
	testing.expect_value(t, station_height(.Scale), f32(0.22))
	testing.expect_value(t, station_plate(.None), Rect{})
	testing.expect_value(t, station_body(.None), Rect{})
	testing.expect_value(t, station_height(.None), f32(0))
}

@(test)
a_point_is_on_a_station_only_inside_its_plate_of_that_kind :: proc(t: ^testing.T) {
	p := default_placed()
	testing.expect(t, on_station(&p, .Hot_Plate, -3.5, -7.63), "the middle of the plate")
	testing.expect(t, on_station(&p, .Hot_Plate, -3.2, -7.38), "the corner counts")
	testing.expect(t, !on_station(&p, .Hot_Plate, -3.19, -7.63), "just past the edge does not")
	testing.expect(t, !on_station(&p, .Hot_Plate, -3.5, -7.37), "nor does just past the other")
	testing.expect(t, !on_station(&p, .Ice_Bath, -3.5, -7.63), "the hot plate is not a bath")
	testing.expect(t, on_station(&p, .Ice_Bath, -2.4, -7.63), "the middle of the bath")
	testing.expect(t, on_station(&p, .Scale, 0.19, -7.625), "on the plate of the scale")
	testing.expect(t, !on_station(&p, .Scale, 0.19, -7.44), "past the plate, over the display, it is not")
	q := Placed{}
	placed_add(&q, {.Hot_Plate, 0, 0, 1}) // 0.6 along z when turned
	testing.expect(t, on_station(&q, .Hot_Plate, 0, 0.29), "turned, it reaches 0.3 along z")
	testing.expect(t, !on_station(&q, .Hot_Plate, 0.29, 0), "and not along x")
	testing.expect(t, !on_station(&q, .Hot_Plate, 5, 5), "and not elsewhere")
	empty := Placed{}
	testing.expect(t, !on_station(&empty, .Hot_Plate, -3.5, -7.63), "with no station there is nothing to stand on")
}

@(test)
the_aim_box_is_the_body_of_a_station_as_high_as_it_is :: proc(t: ^testing.T) {
	low, high := station_aim_box({.Scale, 0, -7.625, 0})
	testing.expect(t, placed_close(low.x, -0.26) && placed_close(low.y, 1.1) && placed_close(low.z, -7.875), "low corner of the scale")
	testing.expect(t, placed_close(high.x, 0.26) && placed_close(high.y, 1.32) && placed_close(high.z, -7.375), "high corner of the scale")
	low, high = station_aim_box({.Hot_Plate, 1, 2, 1})
	testing.expect(t, placed_close(low.x, 0.75) && placed_close(low.z, 1.7) && placed_close(high.x, 1.25) && placed_close(high.z, 2.3), "turned, it is still a box along the axes")
	testing.expect(t, placed_close(high.y, 1.17), "the plate is 7 cm high")
	_, high = station_aim_box({.Ice_Bath, 0, 0, 0})
	testing.expect(t, placed_close(high.y, 1.19), "the bath is 9 cm high")
}

@(test)
stations_stand_on_four_counters_and_not_on_the_bottle_wall_or_the_floor :: proc(t: ^testing.T) {
	p := Placed{}
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8, -7.63, 0), Place_Problem.None) // north counter
	testing.expect_value(t, can_place(&p, .Hot_Plate, 0, 7.63, 0), Place_Problem.None) // south counter
	testing.expect_value(t, can_place(&p, .Hot_Plate, -11.63, 5, 0), Place_Problem.None) // west counter
	testing.expect_value(t, can_place(&p, .Hot_Plate, 0, 0, 0), Place_Problem.None) // the island
	testing.expect_value(t, can_place(&p, .Hot_Plate, 11.63, 0, 0), Place_Problem.Off_Counter) // the bottle wall
	testing.expect_value(t, can_place(&p, .Hot_Plate, 0, -4, 0), Place_Problem.Off_Counter) // the floor
	testing.expect_value(t, can_place(&p, .None, 0, 0, 0), Place_Problem.Off_Counter)
}

@(test)
a_station_has_to_be_wholly_on_a_counter :: proc(t: ^testing.T) {
	p := Placed{}
	// The north counter is 0.7 deep, from z -7.98 to -7.28, and a hot plate is 0.5 deep.
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8, -7.73, 0), Place_Problem.None) // against the wall
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8, -7.74, 0), Place_Problem.Off_Counter) // a centimetre over the wall
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8, -7.53, 0), Place_Problem.None) // at the front
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8, -7.52, 0), Place_Problem.Off_Counter) // a centimetre over the front
	// The ends of the counter, and the island: 10 m long and 1.4 deep.
	testing.expect_value(t, can_place(&p, .Hot_Plate, -4.7, 0, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Hot_Plate, -4.71, 0, 0), Place_Problem.Off_Counter)
	testing.expect_value(t, can_place(&p, .Hot_Plate, 4.7, 0, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Hot_Plate, 4.71, 0, 0), Place_Problem.Off_Counter)
	// Over the gap between two counters is on neither.
	testing.expect_value(t, can_place(&p, .Hot_Plate, -11.63, -7.5, 0), Place_Problem.Off_Counter) // the corner of the north and west counters
}

@(test)
turning_a_station_changes_what_it_takes_up :: proc(t: ^testing.T) {
	p := Placed{}
	testing.expect_value(t, can_place(&p, .Ice_Bath, 8, -7.7, 0), Place_Problem.None) // 0.56 deep fits 0.7
	testing.expect_value(t, can_place(&p, .Ice_Bath, 8, -7.7, 1), Place_Problem.Off_Counter) // turned it is 0.86 deep
	testing.expect_value(t, can_place(&p, .Ice_Bath, 8, -7.7, 2), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Ice_Bath, 8, -7.7, 3), Place_Problem.Off_Counter)
	testing.expect_value(t, can_place(&p, .Ice_Bath, -11.63, 0, 0), Place_Problem.Off_Counter) // 0.86 wide on a counter 0.7 wide
	testing.expect_value(t, can_place(&p, .Ice_Bath, -11.63, 0, 1), Place_Problem.None)
}

@(test)
a_station_is_in_the_way_of_each_fixture :: proc(t: ^testing.T) {
	p := Placed{}
	Case :: struct {
		x, z: f32,
		what: string,
	}
	cases := [?]Case {
		{-11.63, -4.2, "the sink"},
		{-11.63, -3.6, "the soap"},
		{-11.63, 2.0, "the paint station"},
		{-11.63, 1.3, "the tablet"},
		{-11.63, 3.0, "the brushes"},
		{8.8, 7.63, "the loadout rack"},
		{-10.4, -7.62, "the first vial rack"},
		{-9.6, -7.62, "the second vial rack"},
		{-8.0, 7.62, "the third vial rack"},
		{-7.2, 7.62, "the fourth vial rack"},
	}
	for c in cases {
		testing.expectf(t, can_place(&p, .Hot_Plate, c.x, c.z, 0) == .Blocked_By_Fixture, "%v is in the way", c.what)
	}
	// The oven with its spout and tray, and the fill station, are stations now, and are in the way as stations are.
	stations := [?]Case{{3.0, -7.63, "the oven"}, {4.1, -7.63, "the tray under the spout of the oven"}, {6.0, 7.63, "the fill station"}}
	d := default_placed()
	for c in stations {
		testing.expectf(t, can_place(&d, .Hot_Plate, c.x, c.z, 0) == .Blocked_By_Station, "%v is a station, and in the way", c.what)
	}
	// Clear of each, a hand's width away, it may stand.
	testing.expect_value(t, can_place(&p, .Hot_Plate, 4.5, -7.63, 0), Place_Problem.None) // past the tray of the oven
	testing.expect_value(t, can_place(&p, .Hot_Plate, 1.8, -7.63, 0), Place_Problem.None) // before the oven
	testing.expect_value(t, can_place(&p, .Hot_Plate, -7.5, -7.63, 0), Place_Problem.None) // between the hood and the vial racks
	testing.expect_value(t, can_place(&p, .Hot_Plate, 7.0, 7.63, 0), Place_Problem.None) // past the fill station
}

@(test)
every_fixture_on_a_counter_is_inside_a_keep_out :: proc(t: ^testing.T) {
	// The keep-outs were worked out by hand from the fixtures, so this checks them against what the lab builds:
	// every box that sticks up from a counter where a station could be hit must lie inside one of them.
	l := placed_lab_without_stations()
	defer free(l)
	zones, keeps := place_zones(), fixture_keepouts()
	checked := 0
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		bottom, top := b.center.y - b.size.y * 0.5, b.center.y + b.size.y * 0.5
		if top <= COUNTER_HEIGHT + 1e-4 || bottom >= COUNTER_HEIGHT + station_height(.Scale) {
			continue // the floor, the walls, the counters themselves, and what is out of the way over a station
		}
		foot := Rect{b.center.x - b.size.x * 0.5, b.center.z - b.size.z * 0.5, b.center.x + b.size.x * 0.5, b.center.z + b.size.z * 0.5}
		on_zone := false
		for z in zones {
			on_zone ||= rects_intersect(z, foot)
		}
		if !on_zone {
			continue // on the bottle wall, which no station stands on
		}
		checked += 1
		inside := false
		for k in keeps {
			inside ||= rect_inside(k, foot)
		}
		testing.expectf(t, inside, "box %d at (%.3f, %.3f) size (%.3f, %.3f) is on a counter and in no keep-out", i, b.center.x, b.center.z, b.size.x, b.size.z)
	}
	testing.expect(t, checked > 30, "the test looked at the fixtures")
}

@(test)
every_keep_out_has_an_area_and_is_on_a_counter :: proc(t: ^testing.T) {
	zones := place_zones()
	for k, i in fixture_keepouts() {
		testing.expectf(t, k.min_x < k.max_x && k.min_z < k.max_z, "keep-out %d has an area", i)
		in_a_zone := false
		for z in zones {
			in_a_zone ||= rects_intersect(z, k)
		}
		testing.expectf(t, in_a_zone, "keep-out %d is on a counter", i)
	}
}

@(test)
a_station_is_in_the_way_of_another_but_may_touch_it :: proc(t: ^testing.T) {
	p := Placed{}
	placed_add(&p, {.Hot_Plate, 8, -7.63, 0})
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8.6, -7.63, 0), Place_Problem.None) // edge to edge
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8.59, -7.63, 0), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&p, .Hot_Plate, 8, -7.63, 0), Place_Problem.Blocked_By_Station) // on top
	testing.expect_value(t, can_place(&p, .Hot_Plate, 7.4, -7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Hot_Plate, 7.41, -7.63, 0), Place_Problem.Blocked_By_Station)
	// On the island a hot plate at the middle takes 0.3 either way, a bath turned a quarter 0.28 along x, and a bath not turned 0.43.
	p2 := Placed{}
	placed_add(&p2, {.Hot_Plate, 0, 0, 0})
	testing.expect_value(t, can_place(&p2, .Ice_Bath, 0.58, 0, 1), Place_Problem.None) // touching at 0.3
	testing.expect_value(t, can_place(&p2, .Ice_Bath, 0.57, 0, 1), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&p2, .Ice_Bath, 0.73, 0, 0), Place_Problem.None) // touching at 0.3
	testing.expect_value(t, can_place(&p2, .Ice_Bath, 0.72, 0, 0), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&p2, .Ice_Bath, 0, 0.4, 0), Place_Problem.Blocked_By_Station) // 0.4 - 0.28 = 0.12 is inside the plate, which ends at 0.25
	testing.expect_value(t, can_place(&p2, .Ice_Bath, 0, 0.5, 0), Place_Problem.Off_Counter) // clear of it, but 0.5 + 0.28 is past the island, which ends at 0.7
}

@(test)
a_point_snaps_to_the_grid_in_whole_millimetres :: proc(t: ^testing.T) {
	testing.expect(t, placed_close(snap_place(0.126), 0.15), "rounds up")
	testing.expect(t, placed_close(snap_place(0.124), 0.10), "rounds down")
	testing.expect(t, placed_close(snap_place(-7.63), -7.65), "negative")
	testing.expect(t, placed_close(snap_place(-7.62), -7.60), "negative the other way")
	testing.expect_value(t, snap_place(-7.65), f32(-7650) / 1000) // exactly what is read back from the file
	testing.expect_value(t, snap_place(0), f32(0))
	testing.expect(t, placed_close(grid_ceil(-7.73), -7.70), "up to the grid")
	testing.expect(t, placed_close(grid_ceil(-7.70), -7.70), "on the grid it stays")
	testing.expect(t, placed_close(grid_floor(-7.53), -7.55), "down to the grid")
	testing.expect(t, placed_close(grid_floor(-7.55), -7.55), "on the grid it stays")
}

@(test)
the_crosshair_is_fitted_to_the_counter_it_is_on :: proc(t: ^testing.T) {
	x, z, on := fit_to_zone(.Hot_Plate, 0, 8.01, -7.63)
	testing.expect(t, on && placed_close(x, 8.0) && placed_close(z, -7.65), "in the middle of the counter it only snaps")
	x, z, on = fit_to_zone(.Hot_Plate, 0, 8, -7.3)
	testing.expect(t, on && placed_close(z, -7.55), "near the front edge the plate is moved back until it is on")
	x, z, on = fit_to_zone(.Hot_Plate, 0, 8, -7.97)
	testing.expect(t, on && placed_close(z, -7.70), "near the wall it is moved forward")
	x, z, on = fit_to_zone(.Hot_Plate, 0, 8, -7.26)
	testing.expect(t, on && placed_close(z, -7.55), "a little past the front edge is still the counter")
	x, z, on = fit_to_zone(.Hot_Plate, 0, 8, -7.2)
	testing.expect(t, !on && placed_close(z, -7.2), "well past it is not, and the point is only snapped")
	x, z, on = fit_to_zone(.Hot_Plate, 0, 12.5, -7.63)
	testing.expect(t, !on, "past the end of the counter")
	x, z, on = fit_to_zone(.Hot_Plate, 0, -11.4, -7.63)
	testing.expect(t, on && placed_close(x, -11.5 + 0.3) && placed_close(z, -7.65), "at the west end of the north counter it is moved in along x as well")
	x, z, on = fit_to_zone(.Ice_Bath, 1, 0, 0.6)
	testing.expect(t, on && placed_close(x, 0) && placed_close(z, 0.25), "a bath turned a quarter on the island")
	x, z, on = fit_to_zone(.Ice_Bath, 0, -11.6, 0)
	testing.expect(t, !on, "a bath that is wider than the counter it is aimed at does not fit it")
	x, z, on = fit_to_zone(.Ice_Bath, 1, -11.6, 0)
	testing.expect(t, on && placed_close(x, -11.6), "turned a quarter it does, as near the middle of the west counter as the grid goes")
	x, z, on = fit_to_zone(.Hot_Plate, 0, 0, 0)
	testing.expect(t, on && placed_close(x, 0) && placed_close(z, 0), "the middle of the island")
}

@(test)
what_the_crosshair_is_fitted_to_is_on_the_counter_for_every_kind_and_turn :: proc(t: ^testing.T) {
	p := Placed{}
	tried, fitted := 0, 0
	for kind in ([?]Station_Kind{.Hot_Plate, .Ice_Bath, .Scale}) {
		for q in u8(0) ..< 4 {
			for xi in -240 ..= 240 {
				for zi in -160 ..= 160 {
					x, z := f32(xi) * 0.05 + 0.013, f32(zi) * 0.05 - 0.017
					fx, fz, on := fit_to_zone(kind, q, x, z)
					tried += 1
					if !on {
						continue
					}
					fitted += 1
					if can_place(&p, kind, fx, fz, q) == .Off_Counter {
						testing.expectf(t, false, "%v turned %d fitted from (%.3f, %.3f) to (%.3f, %.3f) is not on the counter", kind, q, x, z, fx, fz)
						return
					}
				}
			}
		}
	}
	testing.expect(t, fitted > 1000 && tried > fitted, "the test tried points on and off the counters")
}

@(test)
the_stations_are_written_and_read_back_as_they_were :: proc(t: ^testing.T) {
	d := default_placed()
	text := placed_serialize(&d)
	defer delete(text)
	testing.expect_value(t, text, "placedset 7\nplaced 1 -3500 -7630 0\nplaced 2 -2400 -7630 0\nplaced 3 0 -7625 0\nplaced 4 10500 7630 0\nplaced 5 -6000 -7630 0\nplaced 6 6000 7630 0\nplaced 7 3000 -7630 0\n")
	back, found, _, rejected := placed_deserialize(text)
	testing.expect(t, found, "there was a placedset line")
	testing.expect_value(t, rejected, 0)
	testing.expect_value(t, back, d)
	// A station that was moved: a position that was snapped to the grid and turned, comes back exactly.
	p := Placed{}
	x, z, on := fit_to_zone(.Ice_Bath, 2, 3.37, 7.4)
	testing.expect(t, on && placed_close(x, 3.35) && placed_close(z, 7.6), "a bath turned a half, on the south counter, moved in until it is on")
	placed_add(&p, {.Ice_Bath, x, z, 2})
	text2 := placed_serialize(&p)
	defer delete(text2)
	back2, found2, _, _ := placed_deserialize(text2)
	testing.expect(t, found2, "found")
	testing.expect_value(t, back2, p)
}

@(test)
a_file_with_no_placedset_line_says_nothing_about_stations :: proc(t: ^testing.T) {
	text := "tvstock 1\ncontainer bag 12\nplaced 1 -3500 -7630 0\n"
	p, found, _, rejected := placed_deserialize(text)
	testing.expect(t, !found, "no placedset line")
	testing.expect_value(t, p.count, 0)
	testing.expect_value(t, rejected, 0)
	_, found3, _, _ := placed_deserialize("")
	testing.expect(t, !found3, "nothing at all")
	// An empty set is a statement: nothing stands.
	p4, found4, _, _ := placed_deserialize("placedset 0\n")
	testing.expect(t, found4 && p4.count == 0, "an empty set is found, and empty")
}

@(test)
lines_that_are_no_stations_are_dropped_and_lines_that_cannot_stand_are_kept_aside :: proc(t: ^testing.T) {
	text := strings.concatenate({
		"placedset 9\n",
		"placed 9 0 0 0\n", // no such kind
		"placed 0 0 0 0\n", // a station of no kind
		"placed 1 x 0 0\n", // not a number
		"placed 1 0 0 4\n", // no such turn
		"placed 1 0 0\n", // too few fields
		"placed 1 999999 0 0\n", // far outside the lab
		"placed 1 8000 -7630 0\n", // a good one
		"placed 1 8100 -7630 0\n", // on top of it
		"placed 2 0 3000 0\n", // on the floor
		"placed 3 -11630 1800 0\n", // at the paint station
	}, context.temp_allocator)
	p, found, set_aside, rejected := placed_deserialize(text)
	testing.expect(t, found, "found")
	testing.expect_value(t, p.count, 1)
	testing.expect_value(t, p.items[0], Placement{.Hot_Plate, 8, -7.63, 0})
	testing.expect_value(t, rejected, 3)
	testing.expect_value(t, set_aside[0], Placement{.Hot_Plate, 8.1, -7.63, 0})
	testing.expect_value(t, set_aside[1], Placement{.Ice_Bath, 0, 3, 0})
	testing.expect_value(t, set_aside[2], Placement{.Scale, -11.63, 1.8, 0})
	testing.expect_value(t, set_aside[3], Placement{})
}

@(test)
a_second_placedset_line_starts_the_set_again_and_a_full_set_sets_the_rest_aside :: proc(t: ^testing.T) {
	p, found, _, _ := placed_deserialize("placedset 1\nplaced 1 8000 -7630 0\nplaced 1 8000 -7630 0\nplacedset 1\nplaced 2 8000 -7630 0\n")
	testing.expect(t, found, "found")
	testing.expect_value(t, p.count, 1)
	testing.expect_value(t, p.items[0].kind, Station_Kind.Ice_Bath)
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "placedset 9\n")
	for k in 0 ..< MAX_PLACED + 1 {
		strings.write_string(&b, "placed 1 ")
		strings.write_int(&b, -3000 + 600 * k)
		strings.write_string(&b, " 7630 0\n")
	}
	full, _, set_aside, rejected := placed_deserialize(strings.to_string(b))
	testing.expect_value(t, full.count, MAX_PLACED)
	testing.expect_value(t, rejected, 1)
	testing.expect_value(t, set_aside[0].x, f32(-3000 + 600 * MAX_PLACED) / 1000)
}

@(test)
each_station_is_built_where_it_stands_and_turned_as_it_is_turned :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	add_placed(l, default_placed())
	testing.expect_value(t, l.box_count, 64) // the plate 2, the bath 8, the scale 4, the incinerator 12, the hood 5, the filler and the oven 33
	testing.expect(t, !l.xform.on, "the transform is off again afterwards")
	plate := l.boxes[0]
	testing.expect(t, placed_close(plate.center.x, -3.5) && placed_close(plate.center.y, 1.12) && placed_close(plate.center.z, -7.63), "the hot plate is where it stood")
	testing.expect(t, placed_close(plate.size.x, 0.6) && placed_close(plate.size.z, 0.5), "and as big")
	tub := l.boxes[2]
	testing.expect(t, placed_close(tub.center.x, -2.4) && placed_close(tub.center.z, -7.63) && placed_close(tub.size.x, 0.8), "the floor of the bath")
	body := l.boxes[10]
	testing.expect(t, placed_close(body.center.x, 0) && placed_close(body.center.z, -7.625) && placed_close(body.size.x, 0.5), "the body of the scale")
}

@(test)
a_turned_station_has_its_display_on_the_side_it_is_turned_to :: proc(t: ^testing.T) {
	display :: proc(quarter: u8) -> Vec3 {
		l := new(Layout)
		defer free(l)
		p := Placed{}
		placed_add(&p, {.Scale, 0, 0, quarter})
		add_placed(l, p)
		return l.boxes[2].center // the display is the third box
	}
	d0, d1, d2, d3 := display(0), display(1), display(2), display(3)
	testing.expect(t, placed_close(d0.x, 0) && placed_close(d0.z, 0.23), "not turned, it faces +z")
	testing.expect(t, placed_close(d1.x, -0.23) && placed_close(d1.z, 0), "a quarter, it faces -x")
	testing.expect(t, placed_close(d2.x, 0) && placed_close(d2.z, -0.23), "a half, it faces -z")
	testing.expect(t, placed_close(d3.x, 0.23) && placed_close(d3.z, 0), "three quarters, it faces +x")
	testing.expect(t, placed_close(d0.y, 1.125), "at the same height whichever way")
}

@(test)
the_lab_has_room_for_as_many_stations_as_there_can_be :: proc(t: ^testing.T) {
	l := placed_lab_without_stations()
	defer free(l)
	before := l.box_count
	p := Placed{}
	for k in 0 ..< MAX_PLACED {
		placed_add(&p, {.Ice_Bath, f32(k), 0, 0})
	}
	add_placed(l, p)
	testing.expect_value(t, l.box_count, before + 8 * MAX_PLACED)
	testing.expect(t, l.box_count < MAX_BOXES, "none of them was dropped for want of room")
	// The lab as `add_apparatus` makes it has the seven stations that it starts with, 64 boxes of them.
	l2 := new(Layout)
	defer free(l2)
	build(l2)
	add_apparatus(l2)
	testing.expect_value(t, l2.box_count, before + 64)
}

@(test)
a_point_is_on_a_counter_with_a_little_to_spare_past_its_edge :: proc(t: ^testing.T) {
	testing.expect_value(t, zone_at(8, -7.6), 0) // the north counter
	testing.expect_value(t, zone_at(0, 7.6), 1) // the south counter
	testing.expect_value(t, zone_at(-11.6, 0), 2) // the west counter
	testing.expect_value(t, zone_at(0, 0), 3) // the island
	testing.expect_value(t, zone_at(11.63, 0), -1) // the counter of the bottle wall is no zone
	testing.expect_value(t, zone_at(0, -4), -1) // the floor
	testing.expect_value(t, zone_at(8, -7.25), 0) // 3 cm past the front edge is still on it
	testing.expect_value(t, zone_at(8, -7.2), -1) // 8 cm is not
	testing.expect_value(t, zone_at(-11.53, -7.6), 0) // and past the end of the counter
	testing.expect_value(t, zone_at(-11.6, -7.6), -1) // the corner is on neither of the counters that meet there
	testing.expect_value(t, zone_at(11.53, -7.6), 0) // 3 cm past the east end of the north counter
	testing.expect_value(t, zone_at(11.6, -7.6), -1)
	testing.expect_value(t, zone_at(8, -8.01), 0) // and 1 cm past the wall behind it
	testing.expect_value(t, zone_at(8, -8.05), -1)
	testing.expect_value(t, zone_at(5.03, 0), 3) // 3 cm past the end of the island
	testing.expect_value(t, zone_at(5.1, 0), -1)
}

@(test)
the_incinerator_stands_on_a_counter_where_there_is_room_and_nowhere_else :: proc(t: ^testing.T) {
	p := default_placed()
	// Between the fill station and the loadout rack there is room for it, and turned a quarter as well.
	testing.expect_value(t, can_place(&p, .Incinerator, 7.3, 7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Incinerator, 7.3, 7.63, 1), Place_Problem.None)
	// On the north counter too, clear of the stations there.
	testing.expect_value(t, can_place(&p, .Incinerator, 6.0, -7.63, 0), Place_Problem.None)
	// Not on the floor, not on the fill station, and not on the station that is there.
	testing.expect_value(t, can_place(&p, .Incinerator, 7.3, 4.0, 0), Place_Problem.Off_Counter)
	testing.expect_value(t, can_place(&p, .Incinerator, 6.0, 7.63, 0), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&p, .Incinerator, 10.5, 7.63, 0), Place_Problem.Blocked_By_Station)
	// Where the incinerator stands, nothing else may, and a hot plate beside it, a hand's width off, may.
	testing.expect_value(t, can_place(&p, .Hot_Plate, 10.5, 7.63, 0), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&p, .Hot_Plate, 11.15, 7.63, 0), Place_Problem.None)
}

@(test)
no_vessel_stands_on_the_incinerator_and_it_is_found_by_kind :: proc(t: ^testing.T) {
	testing.expect(t, !station_has_plate(.Incinerator) && !station_has_plate(.None), "no plate")
	for kind in ([?]Station_Kind{.Hot_Plate, .Ice_Bath, .Scale}) {
		testing.expectf(t, station_has_plate(kind), "%v has a plate", kind)
	}
	p := default_placed()
	// The middle of the incinerator is on no plate.
	testing.expect(t, !on_station(&p, .Incinerator, 10.5, 7.63), "a vessel at its middle is not on it")
	found, ok := placed_find(&p, .Incinerator)
	testing.expect(t, ok && found.x == 10.5 && found.z == 7.63, "found where it stands")
	testing.expect_value(t, placed_count_of(&p, .Incinerator), 1)
	placed_remove(&p, 3)
	_, ok = placed_find(&p, .Incinerator)
	testing.expect(t, !ok, "gone once it is taken away")
	testing.expect_value(t, placed_count_of(&p, .Incinerator), 0)
	testing.expect_value(t, placed_count_of(&p, .Hot_Plate), 1)
}

@(test)
an_incinerator_turned_is_written_and_read_back :: proc(t: ^testing.T) {
	p: Placed
	placed_add(&p, {.Incinerator, 7.3, 7.63, 3})
	text := placed_serialize(&p)
	defer delete(text)
	testing.expect_value(t, text, "placedset 1\nplaced 4 7300 7630 3\n")
	back, found, _, rejected := placed_deserialize(text)
	testing.expect(t, found && rejected == 0, "read with nothing set aside")
	testing.expect_value(t, back.count, 1)
	testing.expect_value(t, back.items[0], Placement{.Incinerator, 7.3, 7.63, 3})
}

@(test)
the_hood_stands_on_a_counter_turned_or_not_and_not_under_what_hangs_over_it :: proc(t: ^testing.T) {
	p := default_placed()
	placed_remove(&p, 4) // the hood is picked up
	testing.expect_value(t, can_place(&p, .Hood, -6.0, -7.63, 0), Place_Problem.None) // where it was
	testing.expect_value(t, can_place(&p, .Hood, -11.63, -1.5, 1), Place_Problem.None) // turned, on the west counter
	testing.expect_value(t, can_place(&p, .Hood, -11.63, -1.5, 0), Place_Problem.Off_Counter) // not turned, it is wider than that counter is deep
	testing.expect_value(t, can_place(&p, .Hood, 0.0, 4.0, 0), Place_Problem.Off_Counter) // not on the floor
	// Under the shelves and under the first aid cabinet it cannot stand, nor can the incinerator with its chimney.
	testing.expect_value(t, can_place(&p, .Hood, -6.0, 7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Hood, -8.2, -7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Incinerator, -6.0, 7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Incinerator, -8.2, -7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Incinerator, -3.0, 7.63, 0), Place_Problem.Blocked_By_Fixture) // the east end of the shelves
	// A station that stays under them may stand there, and so may the incinerator once it is past the end of the shelves.
	testing.expect_value(t, can_place(&p, .Hot_Plate, -6.0, 7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Hot_Plate, -8.2, -7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Scale, -6.0, 7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Incinerator, -2.0, 7.63, 0), Place_Problem.None)
	// Where the hood stands, nothing else may.
	d := default_placed()
	testing.expect_value(t, can_place(&d, .Hot_Plate, -6.0, -7.63, 0), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&d, .Hot_Plate, -5.2, -7.63, 0), Place_Problem.Blocked_By_Station) // against its side, which is part of it
	testing.expect_value(t, can_place(&d, .Hot_Plate, -4.8, -7.63, 0), Place_Problem.None)
}

@(test)
a_station_is_as_high_as_its_highest_part :: proc(t: ^testing.T) {
	testing.expect(t, abs(station_top(.Hot_Plate) - 1.17) < 0.001 && abs(station_top(.Ice_Bath) - 1.19) < 0.001 && abs(station_top(.Scale) - 1.32) < 0.001, "the low stations")
	testing.expect(t, abs(station_top(.Incinerator) - 2.22) < 0.001, "the incinerator, to the top of its chimney")
	testing.expect(t, abs(station_top(.Hood) - 2.33) < 0.001, "the hood, to the top of its roof")
	testing.expect_value(t, station_top(.None), COUNTER_HEIGHT)
	testing.expect_value(t, station_height(.Hood), HOOD_TOP - COUNTER_HEIGHT)
	testing.expect(t, station_has_plate(.Hood), "a vessel stands in the hood")
	testing.expect(t, placed_rect_close(world_plate({.Hood, -6, -7.63, 0}), {-6.8, -7.98, -5.2, -7.28}), "its floor")
	testing.expect(t, placed_rect_close(world_body({.Hood, -6, -7.63, 0}), {-6.85, -7.98, -5.15, -7.28}), "its body, with the sides")
	testing.expect(t, placed_rect_close(world_body({.Hood, -11.63, 0, 1}), {-11.98, -0.85, -11.28, 0.85}), "turned a quarter it is as deep as the west counter")
}

@(test)
everything_that_hangs_over_a_counter_is_no_lower_than_its_overhead_keep_out_says :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	add_apparatus(l)
	colors: [SHELF_BOTTLES][4]u8
	for i in 0 ..< SHELF_BOTTLES {
		colors[i] = {200, 200, 200, 255}
	}
	add_shelves(l, colors[:])
	for over, k in overhead_keepouts() {
		lowest := f32(100)
		for i in 0 ..< l.box_count {
			b := l.boxes[i]
			bottom := b.center.y - b.size.y * 0.5
			in_area := b.center.x + b.size.x * 0.5 > over.area.min_x && b.center.x - b.size.x * 0.5 < over.area.max_x && b.center.z + b.size.z * 0.5 > over.area.min_z && b.center.z - b.size.z * 0.5 < over.area.max_z
			if in_area && bottom > 1.4 {
				lowest = min(lowest, bottom)
			}
		}
		testing.expectf(t, lowest >= over.bottom - 0.001, "overhead %d has a box at %v, under the %v that it says", k, lowest, over.bottom)
		testing.expectf(t, lowest - over.bottom < 0.25, "overhead %d says %v and its lowest box is at %v", k, over.bottom, lowest)
	}
}

@(test)
a_hood_turned_is_written_and_read_back :: proc(t: ^testing.T) {
	p: Placed
	placed_add(&p, {.Hood, -11.63, -1.5, 1})
	text := placed_serialize(&p)
	defer delete(text)
	testing.expect_value(t, text, "placedset 1\nplaced 5 -11630 -1500 1\n")
	back, found, _, rejected := placed_deserialize(text)
	testing.expect(t, found && rejected == 0, "read with nothing set aside")
	testing.expect_value(t, back.items[0], Placement{.Hood, -11.63, -1.5, 1})
}

@(test)
a_station_as_deep_as_its_counter_fits_in_the_one_place_there_is :: proc(t: ^testing.T) {
	// The hood is 0.7 m deep and the counters are 0.7 m, so no point of the 5 cm grid has room for it.
	fx, fz, on := fit_to_zone(.Hood, 0, -6.02, -7.6)
	testing.expect(t, on && near_f(fx, -6.0) && near_f(fz, -7.63), "the hood on the north counter, flush, along it on the grid")
	fx, fz, on = fit_to_zone(.Hood, 1, -11.6, -1.52)
	testing.expect(t, on && near_f(fx, -11.63) && near_f(fz, -1.5), "turned, on the west counter")
	fx, fz, on = fit_to_zone(.Hood, 0, -11.6, -1.5)
	testing.expect(t, !on, "not turned it is wider than the west counter is deep")
	testing.expect_value(t, zone_at(-11.6, -1.5), 2)
	// What fit_to_zone gives can stand, and a hood put where it fits is taken as being on the counter.
	p: Placed
	fx, fz, on = fit_to_zone(.Hood, 0, -6.0, -7.6)
	testing.expect_value(t, can_place(&p, .Hood, fx, fz, 0), Place_Problem.None)
	fx, fz, on = fit_to_zone(.Hood, 1, -11.6, -1.5)
	testing.expect_value(t, can_place(&p, .Hood, fx, fz, 1), Place_Problem.None)
}

near_f :: proc(a, b: f32) -> bool {
	return abs(a - b) < 0.0006
}

@(test)
one_axis_of_a_fit_is_the_grid_in_the_range_or_the_middle_of_a_range_without_a_grid_point :: proc(t: ^testing.T) {
	v, ok := fit_axis(-1.02, 1.02, 0.5) // room: the grid point asked for
	testing.expect(t, ok && near_f(v, 0.5), "roomy")
	v, ok = fit_axis(-1.02, 1.02, 3.0) // pushed in to the last grid point
	testing.expect(t, ok && near_f(v, 1.0), "pushed in at the high end")
	v, ok = fit_axis(-1.02, 1.02, -3.0)
	testing.expect(t, ok && near_f(v, -1.0), "and at the low end")
	v, ok = fit_axis(-7.64, -7.62, -7.6) // 2 cm of room and no grid point in it: the middle
	testing.expect(t, ok && near_f(v, -7.63), "the middle of the room there is")
	v, ok = fit_axis(-7.63, -7.63, -7.6) // none at all: that one place
	testing.expect(t, ok && near_f(v, -7.63), "the one place")
	v, ok = fit_axis(-7.63, -7.63005, -7.6) // 0.05 mm short, which still touches
	testing.expect(t, ok && near_f(v, -7.63), "a hair short is still a fit")
	v, ok = fit_axis(-7.62, -7.64, -7.6) // 2 cm too big
	testing.expect(t, !ok && near_f(v, -7.6), "too big, and the point is given back")
}

@(test)
the_filler_and_the_oven_are_tall_stations_without_a_plate_that_stand_where_there_is_room :: proc(t: ^testing.T) {
	testing.expect(t, !station_has_plate(.Filler) && !station_has_plate(.Oven), "no vessel stands on either")
	testing.expect(t, abs(station_top(.Filler) - 1.75) < 0.001 && abs(station_top(.Oven) - 1.7) < 0.001, "heights")
	p := default_placed()
	for i := p.count - 1; i >= 0; i -= 1 {
		if p.items[i].kind == .Filler || p.items[i].kind == .Oven {
			placed_remove(&p, i) // both are picked up
		}
	}
	// Back where they started.
	testing.expect_value(t, can_place(&p, .Filler, 6.0, 7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Oven, 3.0, -7.63, 0), Place_Problem.None)
	// Past the end of the shelves, and on the west counter turned so that the front looks east.
	testing.expect_value(t, can_place(&p, .Filler, -2.0, 7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Oven, -11.63, -1.5, 3), Place_Problem.None)
	testing.expect_value(t, can_place(&p, .Oven, -11.63, -1.5, 0), Place_Problem.Off_Counter) // not turned it is wider than the counter is deep
	// Under the shelves and the cabinet neither may stand, as the hood may not.
	testing.expect_value(t, can_place(&p, .Filler, -6.0, 7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Oven, -8.2, -7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Filler, -8.2, -7.63, 0), Place_Problem.Blocked_By_Fixture)
	// Not on the loadout rack or the paint station, which stay where they are.
	testing.expect_value(t, can_place(&p, .Filler, 8.8, 7.63, 0), Place_Problem.Blocked_By_Fixture)
	testing.expect_value(t, can_place(&p, .Oven, -11.63, 2.0, 3), Place_Problem.Blocked_By_Fixture)
	// Where the oven stands, with its spout and tray, nothing else may, and a hand's width past the tray it may.
	d := default_placed()
	testing.expect_value(t, can_place(&d, .Hot_Plate, 4.1, -7.63, 0), Place_Problem.Blocked_By_Station)
	testing.expect_value(t, can_place(&d, .Hot_Plate, 4.5, -7.63, 0), Place_Problem.None)
	testing.expect_value(t, can_place(&d, .Hot_Plate, 6.3, 7.63, 0), Place_Problem.Blocked_By_Station) // the gauge of the filler
	testing.expect_value(t, can_place(&d, .Hot_Plate, 7.0, 7.63, 0), Place_Problem.None)
}

@(test)
the_filler_and_the_oven_are_written_and_read_back_turned :: proc(t: ^testing.T) {
	p: Placed
	placed_add(&p, {.Filler, -2.0, 7.55, 1})
	placed_add(&p, {.Oven, -11.63, -1.5, 3})
	text := placed_serialize(&p)
	defer delete(text)
	testing.expect_value(t, text, "placedset 2\nplaced 6 -2000 7550 1\nplaced 7 -11630 -1500 3\n")
	back, found, _, rejected := placed_deserialize(text)
	testing.expect(t, found && rejected == 0, "read with nothing set aside")
	testing.expect_value(t, back.items[0], Placement{.Filler, -2.0, 7.55, 1})
	testing.expect_value(t, back.items[1], Placement{.Oven, -11.63, -1.5, 3})
}

@(test)
the_aim_box_of_a_station_stands_from_the_counter_to_the_height_of_the_station :: proc(t: ^testing.T) {
	kinds := [?]Station_Kind{.Filler, .Oven, .Hood, .Incinerator}
	heights := [?]f32{0.64, 0.6, 1.15, 0.62}
	for kind, i in kinds {
		testing.expectf(t, abs(station_height(kind) - heights[i]) < 0.001, "%v is %v high", kind, station_height(kind))
		low, high := station_aim_box(Placement{kind, 3, 4, 0})
		testing.expectf(t, low.y == COUNTER_HEIGHT && abs(high.y - (COUNTER_HEIGHT + heights[i])) < 0.001, "the aim box of %v", kind)
	}
}
