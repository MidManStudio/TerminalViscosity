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
