// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "apparatus_test.odin"
// ============================================================================

package lab

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
the_oven_spout_is_out_in_front_with_room_for_a_vessel :: proc(t: ^testing.T) {
	testing.expect(t, MIXER_SPOUT.z > MIXER.max_z, "in front of the body")
	testing.expect(t, MIXER_SPOUT.x > MIXER.min_x && MIXER_SPOUT.x < MIXER.max_x, "along its front")
	testing.expect(t, MIXER_SPOUT.y - COUNTER_HEIGHT > 0.28, "a tall bottle fits under it")
	testing.expect(t, MIXER_SPOUT.y < MIXER_TOP, "under the top")
	for i in 0 ..< MIXER_PORTS {
		testing.expect(t, mixer_port_light(i).z > MIXER.max_z, "port lights are on the front")
	}
	for i in 0 ..< MIXER_PROGRESS_LIGHTS {
		x := mixer_progress_light(i).x
		testing.expect(t, x > MIXER.min_x && x < mixer_tank_light().x, "the strip is across the window, left of the tank light")
	}
	v := mixer_vent()
	testing.expect(t, in_rect(MIXER, v.x, v.z) && v.y >= MIXER_TOP, "the vent is on top")
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
