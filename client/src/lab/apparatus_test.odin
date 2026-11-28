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
	pl := starting_hood()
	testing.expect_value(t, pl.kind, Station_Kind.Hood)
	floor := world_plate(pl)
	testing.expect(t, counter_covers(l, floor), "the hood is on a counter")
	testing.expect(t, counter_covers(l, world_body(pl)), "and so are its sides")
	testing.expect(t, floor.max_z < 0, "on the north side")
	testing.expect(t, placed_rect_close(floor, {-6.8, -7.98, -5.2, -7.28}), "where it has always stood")
	testing.expect(t, HOOD_GLASS_LOW > COUNTER_HEIGHT + 0.3, "there is a gap under the glass for the hands")
	testing.expect(t, HOOD_GLASS_Z > HOOD.max_z - 0.02 && HOOD_GLASS_Z + 0.005 <= station_body(.Hood).max_z, "and the glass is at the front, inside the body")
}

// The hood as the lab starts.
starting_hood :: proc() -> Placement {
	p := default_placed()
	pl, _ := placed_find(&p, .Hood)
	return pl
}

@(test)
the_glass_of_the_hood_goes_round_with_it :: proc(t: ^testing.T) {
	at := Placement{.Hood, 5, 3, 0}
	want_center := [4]Vec3{{5, 1.9, 3.345}, {4.655, 1.9, 3}, {5, 1.9, 2.655}, {5.345, 1.9, 3}}
	want_size := [4]Vec3{{1.5, 0.7, 0.01}, {0.01, 0.7, 1.5}, {1.5, 0.7, 0.01}, {0.01, 0.7, 1.5}}
	for q in 0 ..< 4 {
		at.quarter = u8(q)
		c, s := hood_glass(at)
		testing.expectf(t, vec_close(c, want_center[q]), "turned %d, the glass is at %v", q, c)
		testing.expectf(t, vec_close(s, want_size[q]), "turned %d, the glass is %v", q, s)
		body := world_body(at)
		testing.expectf(t, c.x - s.x * 0.5 >= body.min_x - 0.0001 && c.x + s.x * 0.5 <= body.max_x + 0.0001 && c.z - s.z * 0.5 >= body.min_z - 0.0001 && c.z + s.z * 0.5 <= body.max_z + 0.0001, "turned %d, the glass is inside the body", q)
	}
}

@(test)
the_hoods_boxes_are_all_inside_its_body_however_it_is_turned :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	add_hood(l)
	testing.expect_value(t, l.box_count, 5) // back, two sides, roof, light
	body := station_body(.Hood)
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		testing.expectf(t, b.center.x - b.size.x * 0.5 >= body.min_x - 0.0001 && b.center.x + b.size.x * 0.5 <= body.max_x + 0.0001, "box %d is across the hood", i)
		testing.expectf(t, b.center.z - b.size.z * 0.5 >= body.min_z - 0.0001 && b.center.z + b.size.z * 0.5 <= body.max_z + 0.0001, "box %d is along it", i)
		testing.expectf(t, b.center.y - b.size.y * 0.5 >= COUNTER_HEIGHT - 0.001 && b.center.y + b.size.y * 0.5 <= station_top(.Hood) + 0.001, "box %d is between the counter and the top", i)
	}
	for q in 0 ..< 4 {
		pl := Placement{.Hood, 5, 3, u8(q)}
		built := new(Layout)
		p: Placed
		placed_add(&p, pl)
		add_placed(built, p)
		testing.expect_value(t, built.box_count, 5)
		world := world_body(pl)
		for i in 0 ..< built.box_count {
			b := built.boxes[i]
			testing.expectf(t, b.center.x - b.size.x * 0.5 >= world.min_x - 0.0001 && b.center.x + b.size.x * 0.5 <= world.max_x + 0.0001 && b.center.z - b.size.z * 0.5 >= world.min_z - 0.0001 && b.center.z + b.size.z * 0.5 <= world.max_z + 0.0001, "turned %d, box %d is outside the body", q, i)
		}
		free(built)
	}
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
	testing.expect(t, !in_rect(world_plate(starting_hood()), SINK_BASIN.min_x, SINK_BASIN.min_z), "sink and hood")
	testing.expect(t, in_rect(SINK_BASIN, (SINK_BASIN.min_x + SINK_BASIN.max_x) * 0.5, (SINK_BASIN.min_z + SINK_BASIN.max_z) * 0.5), "the middle of the basin is in it")
	testing.expect(t, !in_rect(SINK_BASIN, 0, 0), "and the middle of the room is not")
}

@(test)
the_oven_is_on_the_north_counter_beside_the_hood :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, MIXER), "the oven is on a counter")
	testing.expect(t, MIXER.max_z < 0, "on the north side")
	testing.expect(t, MIXER.min_x > world_body(starting_hood()).max_x + 0.5, "clear of the hood")
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
	for other in ([]Rect{world_body(starting_hood()), MIXER}) {
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

vec_close :: proc(a, b: Vec3) -> bool {
	return abs(a.x - b.x) < 0.0005 && abs(a.y - b.y) < 0.0005 && abs(a.z - b.z) < 0.0005
}

// The incinerator as the lab starts, from the stations that stand.
starting_incinerator :: proc() -> Placement {
	p := default_placed()
	pl, _ := placed_find(&p, .Incinerator)
	return pl
}

@(test)
the_incinerator_starts_on_the_south_counter_clear_of_the_other_stations :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	pl := starting_incinerator()
	testing.expect_value(t, pl.kind, Station_Kind.Incinerator)
	body := world_body(pl)
	testing.expect(t, counter_covers(l, body), "it stands on the counter")
	testing.expect(t, body.min_z > 0 && body.max_z < ROOM_D * 0.5, "on the south side")
	// Clear of the fill station and every hook of the rack, by their aim boxes and their boards.
	aim_low, aim_high := station_aim_box(pl)
	testing.expect(t, !box_overlap(aim_low, aim_high, FILLER_AIM_LOW, FILLER_AIM_HIGH), "not on the fill station")
	for i in 0 ..< LOADOUT_SLOTS {
		low, high := slot_aim(i)
		testing.expectf(t, !box_overlap(aim_low, aim_high, low, high), "not on hook %d", i + 1)
	}
	last := slot_clamp(LOADOUT_SLOTS - 1).x
	testing.expect(t, body.min_x > last + 0.14 + 0.3, "a hand's width or more past the last hook")
	testing.expect(t, body.max_x < ROOM_W * 0.5 - 0.7, "and short of the bottle wall counter")
}

@(test)
the_mouth_of_the_incinerator_is_in_its_aim_box_and_over_its_body :: proc(t: ^testing.T) {
	for q in 0 ..< 4 {
		pl := Placement{.Incinerator, 3, -2, u8(q)}
		m := incinerator_mouth(pl)
		lo, hi := station_aim_box(pl)
		testing.expectf(t, m.x > lo.x && m.x < hi.x && m.y > lo.y && m.y < hi.y && m.z > lo.z && m.z < hi.z, "turned %d, the mouth is in the box the crosshair tests", q)
		body := shift_rect(turn_rect(INCINERATOR, u8(q)), pl.x, pl.z)
		testing.expectf(t, m.x - INCINERATOR_HOPPER > body.min_x && m.x + INCINERATOR_HOPPER < body.max_x, "turned %d, over the body, across", q)
		testing.expectf(t, m.z - INCINERATOR_HOPPER > body.min_z && m.z + INCINERATOR_HOPPER < body.max_z, "and along", q)
		testing.expectf(t, lo.y >= COUNTER_HEIGHT, "turned %d, the aim box starts on the counter", q)
	}
	testing.expect(t, INCINERATOR_MOUTH.y > INCINERATOR_TOP && INCINERATOR_MOUTH.y - INCINERATOR_TOP < 0.2, "the hopper stands a hand's depth over the body")
	// It has always been here.
	testing.expect(t, vec_close(incinerator_mouth(starting_incinerator()), {10.5, 1.68, 7.55}), "the mouth where it was")
}

@(test)
the_chimney_is_over_the_back_of_the_body_and_follows_the_station_round :: proc(t: ^testing.T) {
	v := INCINERATOR_VENT
	testing.expect(t, v.y < ROOM_H - 0.5, "well short of the ceiling")
	testing.expect(t, v.x > INCINERATOR.min_x && v.x < INCINERATOR.max_x && v.z > INCINERATOR.min_z && v.z < INCINERATOR.max_z, "over the body")
	testing.expect(t, v.z > INCINERATOR_MOUTH.z + INCINERATOR_HOPPER, "behind the hopper")
	testing.expect(t, v.y > INCINERATOR_TOP + 0.3, "and clear above it, so the smoke does not start in the opening")
	testing.expect(t, vec_close(incinerator_vent(starting_incinerator()), {10.68, 2.18, 7.74}), "the chimney where it was")
	// Turned a quarter at a time, the mouth and the chimney go round the middle of the station.
	at := Placement{.Incinerator, 5, 3, 0}
	want_mouth := [4]Vec3{{5, 1.68, 2.92}, {5.08, 1.68, 3}, {5, 1.68, 3.08}, {4.92, 1.68, 3}}
	want_vent := [4]Vec3{{5.18, 2.18, 3.11}, {4.89, 2.18, 3.18}, {4.82, 2.18, 2.89}, {5.11, 2.18, 2.82}}
	for q in 0 ..< 4 {
		at.quarter = u8(q)
		testing.expectf(t, vec_close(incinerator_mouth(at), want_mouth[q]), "turned %d, the mouth is %v", q, incinerator_mouth(at))
		testing.expectf(t, vec_close(incinerator_vent(at), want_vent[q]), "turned %d, the chimney is %v", q, incinerator_vent(at))
	}
}

@(test)
the_incinerators_boxes_are_all_inside_its_body_however_it_is_turned :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	add_incinerator(l)
	testing.expect_value(t, l.box_count, 12) // lip, body, four walls, fire, door, slit, stripe, chimney, cap
	body := station_body(.Incinerator)
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		testing.expectf(t, b.center.x - b.size.x * 0.5 >= body.min_x - 0.0001 && b.center.x + b.size.x * 0.5 <= body.max_x + 0.0001, "box %d is across the incinerator", i)
		testing.expectf(t, b.center.y - b.size.y * 0.5 >= COUNTER_HEIGHT - 0.001, "box %d stands on the counter, not in it", i)
		testing.expectf(t, b.center.z - b.size.z * 0.5 >= body.min_z - 0.0001 && b.center.z + b.size.z * 0.5 <= body.max_z + 0.0001, "box %d is along it", i)
	}
	// Built where it stands and turned, the same boxes are inside the body of the station there.
	for q in 0 ..< 4 {
		pl := Placement{.Incinerator, 5, 3, u8(q)}
		built := new(Layout)
		p: Placed
		placed_add(&p, pl)
		add_placed(built, p)
		testing.expect_value(t, built.box_count, 12)
		world := world_body(pl)
		for i in 0 ..< built.box_count {
			b := built.boxes[i]
			testing.expectf(t, b.center.x - b.size.x * 0.5 >= world.min_x - 0.0001 && b.center.x + b.size.x * 0.5 <= world.max_x + 0.0001 && b.center.z - b.size.z * 0.5 >= world.min_z - 0.0001 && b.center.z + b.size.z * 0.5 <= world.max_z + 0.0001, "turned %d, box %d is outside the body", q, i)
		}
		free(built)
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
	testing.expect_value(t, l.box_count, before + 13) // the steel floor, four rims, the drain, the four parts of the faucet and the three of the soap
	for i in before ..< l.box_count {
		testing.expect(t, l.boxes[i].size.y > 0, "every box has a height")
	}
}

@(test)
the_wall_has_a_dispenser_only_at_the_mounts_that_have_one :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	colors: [DISPENSER_COUNT][4]u8
	all: [DISPENSER_COUNT]bool
	for &p in all {
		p = true
	}
	before := l.box_count
	add_dispensers_with(l, colors, all)
	testing.expect_value(t, l.box_count - before, 1 + 4 * DISPENSER_COUNT)
	build(l)
	before = l.box_count
	none: [DISPENSER_COUNT]bool
	add_dispensers_with(l, colors, none)
	testing.expect_value(t, l.box_count - before, 1 + DISPENSER_COUNT) // the board, and a plate at each mount
	build(l)
	before = l.box_count
	some := none
	some[2], some[7] = true, true
	add_dispensers_with(l, colors, some)
	testing.expect_value(t, l.box_count - before, 1 + 2 * 4 + (DISPENSER_COUNT - 2))
	build(l)
	before = l.box_count
	add_dispensers(l, colors)
	testing.expect_value(t, l.box_count - before, 1 + 4 * DISPENSER_COUNT) // as before: all of them
}

@(test)
the_soap_stands_on_the_counter_beside_the_basin_within_its_aim_box :: proc(t: ^testing.T) {
	s := SOAP_AT
	testing.expect_value(t, s.y, COUNTER_HEIGHT)
	testing.expect(t, !in_rect(SINK_BASIN, s.x, s.z), "not in the basin")
	testing.expect(t, s.z > SINK_BASIN.max_z && s.z < SINK_BASIN.max_z + 0.4, "just past the end of it")
	testing.expect(t, s.x >= SINK_BASIN.min_x && s.x <= SINK_BASIN.max_x, "along the middle of it")
	testing.expect(t, SOAP_AIM_LOW.x < s.x && s.x < SOAP_AIM_HIGH.x, "inside the aim box across")
	testing.expect(t, SOAP_AIM_LOW.z < s.z && s.z < SOAP_AIM_HIGH.z, "and along")
	testing.expect(t, SOAP_AIM_LOW.y <= s.y && SOAP_AIM_HIGH.y > s.y + 0.2, "and the box covers the bottle and its pump")
}

// ---- the filler and the oven, made to be moved ----

// Whether every box of a station built at `pl` is inside its body, and between the counter and its top.
boxes_inside_body :: proc(t: ^testing.T, pl: Placement, want: int) {
	l := new(Layout)
	defer free(l)
	p: Placed
	placed_add(&p, pl)
	add_placed(l, p)
	testing.expectf(t, l.box_count == want, "%v turned %d has %d boxes, not %d", pl.kind, pl.quarter, l.box_count, want)
	body := world_body(pl)
	for i in 0 ..< l.box_count {
		b := l.boxes[i]
		inside := b.center.x - b.size.x * 0.5 >= body.min_x - 0.0001 && b.center.x + b.size.x * 0.5 <= body.max_x + 0.0001 && b.center.z - b.size.z * 0.5 >= body.min_z - 0.0001 && b.center.z + b.size.z * 0.5 <= body.max_z + 0.0001
		testing.expectf(t, inside, "%v turned %d: box %d is outside the body", pl.kind, pl.quarter, i)
		testing.expectf(t, b.center.y - b.size.y * 0.5 >= COUNTER_HEIGHT - 0.001 && b.center.y + b.size.y * 0.5 <= station_top(pl.kind) + 0.001, "%v turned %d: box %d is not between the counter and the top", pl.kind, pl.quarter, i)
	}
}

@(test)
the_boxes_of_the_filler_and_the_oven_are_inside_their_bodies_as_they_start_and_at_every_turn :: proc(t: ^testing.T) {
	boxes_inside_body(t, FILLER_START, 12)
	boxes_inside_body(t, OVEN_START, 21)
	for q in 0 ..< 4 {
		boxes_inside_body(t, {.Filler, -2.0, 7.55, u8(q)}, 12)
		boxes_inside_body(t, {.Oven, -11.63, -1.5, u8(q)}, 21)
	}
}

@(test)
the_filler_and_the_oven_start_on_their_counters_where_they_have_always_stood :: proc(t: ^testing.T) {
	l := full_lab()
	defer free(l)
	testing.expect(t, counter_covers(l, world_body(FILLER_START)), "the filler is on the south counter")
	testing.expect(t, counter_covers(l, world_body(OVEN_START)), "the oven is on the north counter")
	testing.expect(t, world_body(FILLER_START).min_z > 0 && world_body(OVEN_START).max_z < 0, "one on each side")
	// A station at the place it starts is where its constants say.
	for p in ([?]Vec3{FILLER_CLAMP, FILLER_MOUTH, GAUGE_ORIGIN, MIXER_SPOUT, mixer_port(2)}) {
		testing.expect(t, vec_close(station_point(FILLER_START, p), p) && vec_close(station_point(OVEN_START, p), p), "the start is the identity")
	}
	testing.expect(t, vec_close(filler_mouth_at(FILLER_START), FILLER_MOUTH) && vec_close(mixer_spout_at(OVEN_START), MIXER_SPOUT), "mouth and spout")
	testing.expect(t, vec_close(filler_center_at(FILLER_START), filler_center()) && vec_close(mixer_vent_at(OVEN_START), mixer_vent()), "center and vent")
	for i in 0 ..< MIXER_PORTS {
		testing.expect(t, vec_close(mixer_port_at(OVEN_START, i), mixer_port(i)) && vec_close(mixer_port_light_at(OVEN_START, i), mixer_port_light(i)), "ports")
	}
	for i in 0 ..< MIXER_PROGRESS_LIGHTS {
		testing.expect(t, vec_close(mixer_progress_light_at(OVEN_START, i), mixer_progress_light(i)), "progress lights")
	}
	for i in 0 ..< GAUGE_LIGHTS {
		testing.expect(t, vec_close(gauge_light_at(FILLER_START, i), gauge_light(i)), "gauge lights")
	}
	testing.expect(t, vec_close(mixer_tank_light_at(OVEN_START), mixer_tank_light()) && vec_close(mixer_spout_light_at(OVEN_START), mixer_spout_light()) && vec_close(filler_clamp_at(FILLER_START), FILLER_CLAMP), "tank light, spout light, clamp")
}

@(test)
the_parts_of_the_filler_and_the_oven_go_round_with_them :: proc(t: ^testing.T) {
	f := Placement{.Filler, 5, 3, 0}
	want_mouth := [4]Vec3{{5, 1.68, 2.82}, {5.18, 1.68, 3}, {5, 1.68, 3.18}, {4.82, 1.68, 3}}
	want_light := [4]Vec3{{5.3, 1.28, 2.875}, {5.125, 1.28, 3.3}, {4.7, 1.28, 3.125}, {4.875, 1.28, 2.7}}
	for q in 0 ..< 4 {
		f.quarter = u8(q)
		testing.expectf(t, vec_close(filler_mouth_at(f), want_mouth[q]), "turned %d, the mouth is %v", q, filler_mouth_at(f))
		testing.expectf(t, vec_close(gauge_light_at(f, 0), want_light[q]), "turned %d, the first light is %v", q, gauge_light_at(f, 0))
	}
	o := Placement{.Oven, 5, 3, 0}
	want_port0 := [4]Vec3{{4.4, 1.69, 3}, {5, 1.69, 2.4}, {5.6, 1.69, 3}, {5, 1.69, 3.6}}
	want_port3 := [4]Vec3{{5.6, 1.69, 3}, {5, 1.69, 3.6}, {4.4, 1.69, 3}, {5, 1.69, 2.4}}
	want_spout := [4]Vec3{{6.02, 1.45, 3}, {5, 1.45, 4.02}, {3.98, 1.45, 3}, {5, 1.45, 1.98}}
	for q in 0 ..< 4 {
		o.quarter = u8(q)
		testing.expectf(t, vec_close(mixer_port_at(o, 0), want_port0[q]), "turned %d, port 1 is %v", q, mixer_port_at(o, 0))
		testing.expectf(t, vec_close(mixer_port_at(o, 3), want_port3[q]), "turned %d, port 4 is %v", q, mixer_port_at(o, 3))
		testing.expectf(t, vec_close(mixer_spout_at(o), want_spout[q]), "turned %d, the spout is %v", q, mixer_spout_at(o))
	}
	// A flat light keeps facing the way the station faces, so a quarter turn swaps its width and depth.
	testing.expect(t, vec_close(station_size({.Oven, 0, 0, 0}, {0.14, 0.05, 0.012}), {0.14, 0.05, 0.012}), "not turned")
	testing.expect(t, vec_close(station_size({.Oven, 0, 0, 1}, {0.14, 0.05, 0.012}), {0.012, 0.05, 0.14}), "turned a quarter")
	testing.expect(t, vec_close(station_size({.Oven, 0, 0, 2}, {0.14, 0.05, 0.012}), {0.14, 0.05, 0.012}), "turned half")
	testing.expect(t, vec_close(station_size({.Oven, 0, 0, 3}, {0.14, 0.05, 0.012}), {0.012, 0.05, 0.14}), "turned three quarters")
}

@(test)
a_point_goes_to_a_station_and_back_for_every_kind_and_every_turn :: proc(t: ^testing.T) {
	p := Vec3{7.1, 1.4, 2.2}
	for kind in Station_Kind {
		for q in 0 ..< 4 {
			pl := Placement{kind, 3.3, -2.1, u8(q)}
			back := station_to_start(pl, station_point(pl, p))
			testing.expectf(t, vec_close(back, p), "%v turned %d: %v is not %v", kind, q, back, p)
		}
	}
	// A direction is only turned, never moved, and what is up stays up.
	testing.expect(t, vec_close(station_dir_to_start({.Oven, 9, 9, 1}, {1, 0.5, 0}), {0, 0.5, -1}), "a quarter turn sends +x to -z when it is turned back")
	testing.expect(t, vec_close(station_dir_to_start({.Oven, 9, 9, 3}, {0, 0, 1}), {-1, 0, 0}), "and three quarters sends +z to -x")
	testing.expect(t, vec_close(station_dir_to_start({.Oven, 9, 9, 0}, {0.3, -0.4, 0.5}), {0.3, -0.4, 0.5}), "not turned")
}
