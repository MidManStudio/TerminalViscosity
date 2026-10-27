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
