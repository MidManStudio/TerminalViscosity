// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "apparatus_test.odin"
// ============================================================================

package lab

import bl "../balloon"
import "core:math"
import "core:testing"

full_lab :: proc() -> ^Layout {
	l := new(Layout)
	build(l)
	colors: [DISPENSER_COUNT][4]u8
	add_dispensers(l, colors)
	add_apparatus(l)
	return l
}

// Whether some counter of the layout covers the whole rectangle.
counter_covers :: proc(l: ^Layout, r: Rect) -> bool {
	for i in 0 ..< l.collider_count {
		c := l.colliders[i]
		if r.min_x >= c.min_x && r.max_x <= c.max_x && r.min_z >= c.min_z && r.max_z <= c.max_z {
			return true
		}
	}
	return false
}

@(test)
the_workstations_fit_in_the_box_limit :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, l.box_count < MAX_BOXES, "room for more")
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		testing.expect(t, abs(b.center.x) < ROOM_W * 0.5 + 0.6 && abs(b.center.z) < ROOM_D * 0.5 + 0.6, "inside the room")
	}
}

@(test)
the_sink_is_on_the_west_counter :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, SINK_BASIN), "the basin is on a counter")
	testing.expect(t, SINK_BASIN.max_x < 0, "on the west side")
}

@(test)
the_hood_is_on_the_north_counter :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, HOOD), "the hood is on a counter")
	testing.expect(t, HOOD.max_z < 0, "on the north side")
	testing.expect(t, HOOD_GLASS_LOW > COUNTER_HEIGHT + 0.3, "there is a gap under the glass for the hands")
	testing.expect(t, HOOD_GLASS_Z > HOOD.max_z, "and the glass is at the front")
}

@(test)
the_filler_stands_on_the_south_counter :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	clamp_spot := Rect{FILLER_CLAMP.x, FILLER_CLAMP.z, FILLER_CLAMP.x, FILLER_CLAMP.z}
	testing.expect(t, counter_covers(l, clamp_spot), "the clamp is over the counter")
	testing.expect(t, FILLER_CLAMP.z > 0, "on the south side")
	testing.expect(t, FILLER_CLAMP.y - 0.4 > COUNTER_HEIGHT, "a balloon hangs clear of the counter")
	testing.expect(t, FILLER_MOUTH.y > FILLER_CLAMP.y, "the funnel is above the clamp")
	testing.expect(t, FILLER_CAPTURE_LOW < FILLER_MOUTH.y && FILLER_MOUTH.y < FILLER_CAPTURE_HIGH, "the mouth is inside the capture column")
	testing.expect(t, FILLER_CAPTURE_LOW > FILLER_CLAMP.y, "which stops above the clamp, so nothing is taken from under it")
	lo, hi := FILLER_AIM_LOW, FILLER_AIM_HIGH
	inside := FILLER_MOUTH.x > lo.x && FILLER_MOUTH.x < hi.x && FILLER_MOUTH.y > lo.y && FILLER_MOUTH.y < hi.y && FILLER_MOUTH.z > lo.z && FILLER_MOUTH.z < hi.z
	testing.expect(t, inside, "the aim box holds the mouth")
	c := filler_center()
	testing.expect(t, c.x == FILLER_CLAMP.x && c.y < FILLER_CLAMP.y, "the balloon center is under the clamp")
}

@(test)
the_gauge_lights_stack_upward_beside_the_funnel :: proc(t: ^testing.T) {
	for i in 1 ..< GAUGE_LIGHTS {
		testing.expect(t, gauge_light(i).y > gauge_light(i - 1).y, "each above the last")
	}
	testing.expect(t, gauge_light(GAUGE_LIGHTS - 1).y < FILLER_AIM_HIGH.y + 0.2, "within reach of the eye")
	testing.expect(t, gauge_light(0).x > FILLER_AIM_HIGH.x, "beside the balloon, not behind it")
}

@(test)
the_workstations_do_not_overlap :: proc(t: ^testing.T) {
	testing.expect(t, !in_rect(HOOD, SINK_BASIN.min_x, SINK_BASIN.min_z), "sink and hood")
	testing.expect(t, in_rect(SINK_BASIN, (SINK_BASIN.min_x + SINK_BASIN.max_x) * 0.5, (SINK_BASIN.min_z + SINK_BASIN.max_z) * 0.5), "the middle of the basin is in it")
	testing.expect(t, !in_rect(SINK_BASIN, 0, 0), "and the middle of the room is not")
}

@(test)
the_oven_is_on_the_north_counter_beside_the_hood :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, MIXER), "the oven is on a counter")
	testing.expect(t, MIXER.max_z < 0, "on the north side")
	testing.expect(t, MIXER.min_x > HOOD.max_x + 0.5, "clear of the hood")
	testing.expect(t, MIXER_TOP - COUNTER_HEIGHT < 0.6, "low enough to pour into from eye height")
}

@(test)
the_oven_ports_are_in_a_row_on_top_of_it :: proc(t: ^testing.T) {
	for i in 0 ..< MIXER_PORTS {
		p := mixer_port(i)
		testing.expect(t, in_rect(MIXER, p.x, p.z), "inside the footprint")
		testing.expect(t, p.y > MIXER_TOP, "above the top")
		if i > 0 {
			testing.expect(t, abs(p.x - mixer_port(i - 1).x - MIXER_PORT_SPACING) < 1e-4, "evenly spaced")
			testing.expect(t, MIXER_PORT_SPACING > 2 * MIXER_PORT_RADIUS + 0.1, "funnels do not touch")
		}
		lo, hi := MIXER_AIM_LOW, MIXER_AIM_HIGH
		testing.expect(t, p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y && p.z > lo.z && p.z < hi.z, "the aim box holds the port")
	}
}

@(test)
the_oven_spout_is_off_the_right_end_over_free_counter_with_a_tray_for_a_vessel :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	n := MIXER_SPOUT
	testing.expect(t, n.x > MIXER.max_x + 0.1, "off the right end of the body, clear of it")
	tray := Rect{n.x - MIXER_TRAY_RADIUS, n.z - MIXER_TRAY_RADIUS, n.x + MIXER_TRAY_RADIUS, n.z + MIXER_TRAY_RADIUS}
	testing.expect(t, counter_covers(l, tray), "the tray is wholly on the counter, so a vessel can stand on it")
	testing.expect(t, !overlap(tray, MIXER), "and not inside the oven")
	testing.expect(t, n.y - COUNTER_HEIGHT > 0.28, "a tall bottle fits under the spout")
	testing.expect(t, n.y - COUNTER_HEIGHT < 0.5, "and it is not so high that a vessel on the tray is far from it")
	testing.expect(t, MIXER_TRAY_RADIUS > 0.08, "the tray is wider than a vessel")
	for i in 0 ..< MIXER_PORTS {
		testing.expect(t, mixer_port_light(i).z > MIXER.max_z, "port lights are on the front")
	}
	for i in 0 ..< MIXER_PROGRESS_LIGHTS {
		x := mixer_progress_light(i).x
		testing.expect(t, x > MIXER.min_x && x < mixer_tank_light().x, "the strip is across the window, left of the tank light")
	}
	v := mixer_vent()
	testing.expect(t, in_rect(MIXER, v.x, v.z) && v.y >= MIXER_TOP, "the vent is on top")
	sl := mixer_spout_light()
	testing.expect(t, sl.x == n.x && sl.z == n.z && sl.y > n.y, "the light is at the tip of the spout")
}
overlap :: proc(a, b: Rect) -> bool {
	return a.min_x < b.max_x && b.min_x < a.max_x && a.min_z < b.max_z && b.min_z < a.max_z
}

@(test)
the_hot_plate_and_the_ice_bath_are_on_the_north_counter_apart_from_everything_else :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, HOT_PLATE), "the plate is on a counter")
	testing.expect(t, counter_covers(l, ICE_BATH), "the bath is on a counter")
	testing.expect(t, !overlap(HOT_PLATE, ICE_BATH), "not on each other")
	for other in ([]Rect{HOOD, MIXER}) {
		testing.expect(t, !overlap(HOT_PLATE, other) && !overlap(ICE_BATH, other), "clear of the hood and the oven")
	}
	testing.expect(t, HOT_PLATE.max_z < 0 && ICE_BATH.max_z < 0, "on the north side")
	testing.expect(t, HOT_PLATE.max_x - HOT_PLATE.min_x > 0.4 && ICE_BATH.max_x - ICE_BATH.min_x > 0.4, "big enough to stand a flask on")
}

@(test)
the_paint_station_is_on_the_west_counter_with_room_for_a_hanging_balloon :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	spot := Rect{PAINT_CLAMP.x, PAINT_CLAMP.z, PAINT_CLAMP.x, PAINT_CLAMP.z}
	testing.expect(t, counter_covers(l, spot), "the clamp is over the counter")
	testing.expect(t, PAINT_CLAMP.x < 0, "on the west side")
	testing.expect(t, abs(PAINT_CLAMP.z - (SINK_BASIN.min_z + SINK_BASIN.max_z) * 0.5) > 1, "well away from the sink")
	testing.expect(t, PAINT_CLAMP.y - PAINT_DROP - COUNTER_HEIGHT > 0.2, "the balloon hangs clear of the counter")
	lo, hi := PAINT_AIM_LOW, PAINT_AIM_HIGH
	inside := PAINT_CLAMP.x > lo.x && PAINT_CLAMP.x < hi.x && PAINT_CLAMP.y > lo.y && PAINT_CLAMP.y < hi.y && PAINT_CLAMP.z > lo.z && PAINT_CLAMP.z < hi.z
	testing.expect(t, inside, "the aim box holds the clamp")
	testing.expect(t, PAINT_CLAMP.y - PAINT_DROP > lo.y, "and the bottom of the balloon")
}

@(test)
the_palette_has_sixteen_different_colors :: proc(t: ^testing.T) {
	testing.expect_value(t, PALETTE_SIZE, 16)
	for a in 0 ..< PALETTE_SIZE {
		for b in a + 1 ..< PALETTE_SIZE {
			testing.expect(t, palette_color(a) != palette_color(b), "no two the same")
		}
	}
	testing.expect_value(t, palette_color(-3), palette_color(0)) // out of range counts as the end
	testing.expect_value(t, palette_color(99), palette_color(PALETTE_SIZE - 1))
}

@(test)
the_loadout_rack_has_a_hook_for_each_slot_on_the_south_counter :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, LOADOUT_SLOTS >= 1, "at least one slot")
	for i in 0 ..< LOADOUT_SLOTS {
		c := slot_clamp(i)
		testing.expect(t, counter_covers(l, Rect{c.x, c.z, c.x, c.z}), "the hook is over the counter")
		testing.expect(t, c.z > 0, "on the south side")
		testing.expect(t, c.y - 0.2 - COUNTER_HEIGHT > 0.2, "a balloon hangs clear of the counter")
		lo, hi := slot_aim(i)
		testing.expect(t, c.x > lo.x && c.x < hi.x && c.y > lo.y && c.y < hi.y && c.z > lo.z && c.z < hi.z, "the aim box holds the hook")
		if i > 0 {
			_, prev_hi := slot_aim(i - 1)
			testing.expect(t, lo.x >= prev_hi.x - 1e-4, "aim boxes do not overlap, so one slot is aimed at")
			testing.expect(t, SLOT_SPACING > 0.3, "room for balloons side by side")
			testing.expect(t, slot_light(i).x > slot_light(i - 1).x, "lights in order")
		}
	}
	first_lo, _ := slot_aim(0)
	testing.expect(t, first_lo.x > GAUGE_ORIGIN.x + 0.1, "clear of the gauge of the fill station")
	_, last_hi := slot_aim(LOADOUT_SLOTS - 1)
	testing.expect(t, last_hi.x < ROOM_W * 0.5 - 0.5, "and inside the counter")
}

@(test)
the_tablet_is_twice_as_wide_as_high_beside_the_clamp_and_within_reach_of_the_aim :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, abs(TABLET_W - 2 * TABLET_H) < 1e-4, "twice as wide as high")
	spot := Rect{TABLET_CENTER.x, TABLET_CENTER.z, TABLET_CENTER.x, TABLET_CENTER.z}
	testing.expect(t, counter_covers(l, spot), "on the west counter")
	lo, hi := TABLET_AIM_LOW, TABLET_AIM_HIGH
	c := TABLET_CENTER
	testing.expect(t, c.x > lo.x && c.x < hi.x && c.y > lo.y && c.y < hi.y && c.z > lo.z && c.z < hi.z, "the aim box holds the screen")
	testing.expect(t, c.z - TABLET_W * 0.5 >= lo.z && c.z + TABLET_W * 0.5 <= hi.z, "all of it, across")
	testing.expect(t, c.y - TABLET_H * 0.5 >= lo.y && c.y + TABLET_H * 0.5 <= hi.y, "and up and down")
	testing.expect(t, hi.z < PAINT_AIM_LOW.z, "its aim box is apart from that of the clamp, so each is aimed at alone")
	testing.expect(t, c.z + TABLET_W * 0.5 < PAINT_CLAMP.z - 0.1, "and the tablet does not touch the clamp")
}

@(test)
no_paint_is_swatch_zero :: proc(t: ^testing.T) {
	// Swatch 0 is the bare rubber and the eraser, so it must look like the rubber,
	// which is light, and not like a paint.
	r := palette_color(0)
	testing.expect(t, r.r > 180 && r.g > 180 && r.b > 180, "pale")
}

// How far below its tip a balloon hangs once it has settled, at the settings of the paint
// station: the frequency and substeps are `STATION_FREQUENCY` and `STATION_SUBSTEPS` of
// `filler_view.odin`, which the main package owns and this one cannot read, so they are
// repeated here and must be kept the same by hand. `fill` is the fill the body is given.
settled_depth :: proc(fill: f32) -> f32 {
	b := new(bl.Balloon)
	defer free(b)
	cfg := bl.default_config()
	cfg.frequency = 4
	cfg.substeps = 6
	bl.init(b, cfg)
	b.floor_y = -1000
	scale := math.pow(1000 * 1e-6 / b.rest_volume, 1.0 / 3.0) // the rest volume of a balloon is 1000 ml
	bl.reset(b, -b.rest_pos[bl.TIP])
	bl.set_fill(b, fill)
	for _ in 0 ..< 600 {
		bl.pin(b, bl.TIP, {0, 0, 0})
		bl.step(b, 1.0 / 60)
	}
	lo, _ := bl.bounds(b)
	return -lo.y * scale
}

@(test)
the_cradle_stands_clear_below_a_balloon_hanging_at_any_fill :: proc(t: ^testing.T) {
	// From the slack balloon of an empty one, through full, to the stretched one just before it pops.
	for fill in ([]f32{0.55, 0.775, 1.0, 1.35}) {
		depth := settled_depth(fill)
		bottom := PAINT_CLAMP.y - depth
		cradle_top := paint_cradle().y + CLAMP_HALF_HEIGHT
		testing.expectf(t, depth <= PAINT_DROP, "at fill %v the balloon hangs %.3f m, further than PAINT_DROP %.3f", fill, depth, PAINT_DROP)
		testing.expectf(t, bottom > cradle_top + 0.01, "at fill %v the bottom of the balloon is at %.3f and the cradle reaches up to %.3f", fill, bottom, cradle_top)
	}
}

@(test)
the_cradle_is_below_the_bottom_of_a_balloon_and_above_the_counter :: proc(t: ^testing.T) {
	c := paint_cradle()
	testing.expect(t, c.y < PAINT_CLAMP.y - PAINT_DROP, "lower than the balloon reaches")
	testing.expect(t, c.y - CLAMP_HALF_HEIGHT - COUNTER_HEIGHT > 0.15, "and clear of the counter, room for a hand")
	lo, hi := PAINT_AIM_LOW, PAINT_AIM_HIGH
	testing.expect(t, c.y > lo.y && c.y < hi.y && c.x > lo.x && c.x < hi.x && c.z > lo.z && c.z < hi.z, "inside the box the crosshair tests for the station")
	// The boxes of the cradle are really there, at that height.
	l := full_lab()
	defer free(l)
	found := 0
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		if abs(b.center.y - c.y) < 1e-4 && abs(b.center.x - c.x) < 0.05 && abs(b.center.z - c.z) < 0.05 {
			found += 1
		}
	}
	testing.expect_value(t, found, 4) // the four walls of the clamp
}

box_overlap :: proc(a_lo, a_hi, b_lo, b_hi: Vec3) -> bool {
	return a_lo.x < b_hi.x && b_lo.x < a_hi.x && a_lo.y < b_hi.y && b_lo.y < a_hi.y && a_lo.z < b_hi.z && b_lo.z < a_hi.z
}

@(test)
the_incinerator_is_on_the_south_counter_clear_of_the_other_stations :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, INCINERATOR), "it stands on the counter")
	testing.expect(t, INCINERATOR.min_z > 0 && INCINERATOR.max_z < ROOM_D * 0.5, "on the south side")
	// Clear of the fill station and every hook of the rack, by their aim boxes and their boards.
	testing.expect(t, !box_overlap(INCINERATOR_AIM_LOW, INCINERATOR_AIM_HIGH, FILLER_AIM_LOW, FILLER_AIM_HIGH), "not on the fill station")
	for i in 0 ..< LOADOUT_SLOTS {
		low, high := slot_aim(i)
		testing.expectf(t, !box_overlap(INCINERATOR_AIM_LOW, INCINERATOR_AIM_HIGH, low, high), "not on hook %d", i + 1)
	}
	last := slot_clamp(LOADOUT_SLOTS - 1).x
	testing.expect(t, INCINERATOR.min_x > last + 0.14 + 0.3, "a hand's width or more past the last hook")
	testing.expect(t, INCINERATOR.max_x < ROOM_W * 0.5 - 0.7, "and short of the bottle wall counter")
}

@(test)
the_mouth_of_the_incinerator_is_in_its_aim_box_and_over_its_body :: proc(t: ^testing.T) {
	m := INCINERATOR_MOUTH
	lo, hi := INCINERATOR_AIM_LOW, INCINERATOR_AIM_HIGH
	testing.expect(t, m.x > lo.x && m.x < hi.x && m.y > lo.y && m.y < hi.y && m.z > lo.z && m.z < hi.z, "the mouth is in the box the crosshair tests")
	testing.expect(t, m.x - INCINERATOR_HOPPER > INCINERATOR.min_x && m.x + INCINERATOR_HOPPER < INCINERATOR.max_x, "over the body, across")
	testing.expect(t, m.z - INCINERATOR_HOPPER > INCINERATOR.min_z && m.z + INCINERATOR_HOPPER < INCINERATOR.max_z, "and along")
	testing.expect(t, m.y > INCINERATOR_TOP && m.y - INCINERATOR_TOP < 0.2, "the hopper stands a hand's depth over the body")
	testing.expect(t, lo.y >= COUNTER_HEIGHT, "the aim box starts on the counter")
}

@(test)
the_chimney_is_inside_the_room_and_over_the_back_of_the_body :: proc(t: ^testing.T) {
	v := incinerator_vent()
	testing.expect(t, v.y < ROOM_H - 0.5, "well short of the ceiling")
	testing.expect(t, v.x > INCINERATOR.min_x && v.x < INCINERATOR.max_x && v.z > INCINERATOR.min_z && v.z < INCINERATOR.max_z, "over the body")
	testing.expect(t, v.z > INCINERATOR_MOUTH.z + INCINERATOR_HOPPER, "behind the hopper")
	testing.expect(t, v.y > INCINERATOR_TOP + 0.3, "and clear above it, so the smoke does not start in the opening")
}

@(test)
the_incinerators_boxes_are_all_in_place :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	before := l.box_count
	add_incinerator(l)
	testing.expect_value(t, l.box_count, before + 12) // lip, body, four walls, fire, door, slit, stripe, chimney, cap
	for i in before ..< l.box_count {
		b := l.boxes[i]
		testing.expectf(t, b.center.x - b.size.x * 0.5 >= INCINERATOR.min_x - 0.1 && b.center.x + b.size.x * 0.5 <= INCINERATOR.max_x + 0.1, "box %d is across the incinerator", i - before)
		testing.expectf(t, b.center.y - b.size.y * 0.5 >= COUNTER_HEIGHT - 0.001, "box %d stands on the counter, not in it", i - before)
		testing.expectf(t, b.center.z - b.size.z * 0.5 >= INCINERATOR.min_z - 0.03 && b.center.z + b.size.z * 0.5 <= INCINERATOR.max_z + 0.1, "box %d is along it", i - before)
	}
}


@(test)
the_faucet_is_a_tap_over_the_basin_with_room_under_it_and_is_built :: proc(t: ^testing.T) {
	n := SINK_NOZZLE
	testing.expect(t, in_rect(SINK_BASIN, n.x, n.z), "the tip is over the basin")
	testing.expect(t, n.y > COUNTER_HEIGHT + 0.3 && n.y < 1.8, "with room for a flask under it, and in reach")
	testing.expect_value(t, TAP_COUNT, DISPENSER_COUNT + 1)
	testing.expect_value(t, SINK_TAP, DISPENSER_COUNT)
	testing.expect_value(t, tap_nozzle(SINK_TAP), SINK_NOZZLE)
	for i in 0 ..< DISPENSER_COUNT {
		testing.expect_value(t, tap_nozzle(i), dispenser_nozzle(i))
	}
	l := new(Layout)
	defer free(l)
	build(l)
	before := l.box_count
	add_sink(l)
	testing.expect_value(t, l.box_count, before + 10) // the steel floor, four rims, the drain, and the four parts of the faucet
	for i in before ..< l.box_count {
		testing.expect(t, l.boxes[i].size.y > 0, "every box has a height")
	}
}
