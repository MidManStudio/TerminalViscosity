// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "equipment_test.odin"
// ============================================================================

package lab

import "core:testing"

rects_overlap :: proc(a, b: Rect, margin: f32 = 0) -> bool {
	return a.min_x - margin < b.max_x && b.min_x - margin < a.max_x && a.min_z - margin < b.max_z && b.min_z - margin < a.max_z
}

// The footprint of rack `i` on the counter: its frame is a little wider than its holes.
rack_footprint :: proc(i: int) -> Rect {
	racks := VIAL_RACKS
	r := racks[i]
	w := f32(VIAL_RACK_COLS) * VIAL_SLOT_SPACING * 0.5 + 0.02
	d := f32(VIAL_RACK_ROWS) * VIAL_SLOT_SPACING * 0.5 + 0.02
	return {r.x - w, r.z - d, r.x + w, r.z + d}
}

// The footprints of the other equipment of the lab that stands on the counters.
other_footprints :: proc() -> [7]Rect {
	return {SINK_BASIN, HOOD, MIXER, HOT_PLATE, ICE_BATH, INCINERATOR, {FILLER_CLAMP.x - 0.2, 7.3, FILLER_CLAMP.x + 0.2, 8}}
}

built_room :: proc() -> ^Layout {
	l := new(Layout)
	build(l)
	add_apparatus(l)
	return l
}

@(test)
the_equipment_adds_its_boxes_and_no_collider :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	build(l)
	colliders := l.collider_count
	before := l.box_count
	add_equipment(l)
	// Four racks of two plates, four posts and twelve holes, the cabinet's six boxes, the scale's four.
	testing.expect_value(t, l.box_count, before + 4 * (2 + 4 + 12) + 6 + 4)
	testing.expect_value(t, l.collider_count, colliders)
	before = l.box_count
	colors := [][4]u8{{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}}
	add_shelves(l, colors)
	// Two boards, two brackets under each, and three boxes for each of the bottles.
	testing.expect_value(t, l.box_count, before + 2 + 4 + 3 * SHELF_BOTTLES)
	testing.expect_value(t, l.collider_count, colliders)
}

@(test)
the_whole_room_fits_in_the_box_list_with_room_to_spare :: proc(t: ^testing.T) {
	l := built_room()
	defer free(l)
	add_dispensers(l, {})
	add_shelves(l, nil)
	testing.expectf(t, l.box_count < MAX_BOXES - 50, "%v of %v boxes", l.box_count, MAX_BOXES)
	// One mesh holds at most 65535 vertices, 24 for each box.
	testing.expect(t, l.box_count * 24 < 65535, "the room is one mesh")
}

@(test)
every_rack_stands_wholly_on_a_counter_and_clear_of_everything_else :: proc(t: ^testing.T) {
	l := built_room()
	defer free(l)
	for i in 0 ..< VIAL_RACK_COUNT {
		f := rack_footprint(i)
		on_counter := false
		for c in 0 ..< l.collider_count {
			r := l.colliders[c]
			if f.min_x >= r.min_x && f.max_x <= r.max_x && f.min_z >= r.min_z && f.max_z <= r.max_z {
				on_counter = true
			}
		}
		testing.expectf(t, on_counter, "rack %d is not wholly on a counter", i)
		for j in i + 1 ..< VIAL_RACK_COUNT {
			testing.expectf(t, !rects_overlap(f, rack_footprint(j), 0.05), "racks %d and %d are too close", i, j)
		}
		for o, k in other_footprints() {
			testing.expectf(t, !rects_overlap(f, o, 0.05), "rack %d is on top of piece %d of the other equipment", i, k)
		}
		testing.expectf(t, !rects_overlap(f, {SCALE_PLATE.min_x - 0.1, SCALE_PLATE.min_z - 0.1, SCALE_PLATE.max_x + 0.1, SCALE_PLATE.max_z + 0.1}), "rack %d is on the scale", i)
	}
}

@(test)
the_scale_stands_on_the_north_counter_clear_of_the_rest :: proc(t: ^testing.T) {
	l := built_room()
	defer free(l)
	body := Rect{SCALE_PLATE.min_x - 0.05, SCALE_PLATE.min_z - 0.05, SCALE_PLATE.max_x + 0.05, SCALE_PLATE.max_z + 0.05}
	north := l.colliders[0]
	testing.expect(t, body.min_x >= north.min_x && body.max_x <= north.max_x && body.min_z >= north.min_z && body.max_z <= north.max_z, "on the north counter")
	for o, k in other_footprints() {
		testing.expectf(t, !rects_overlap(body, o, 0.05), "the scale is on top of piece %d of the other equipment", k)
	}
	// The aim box takes in the whole plate, and its front is where the display is.
	testing.expect(t, SCALE_AIM_LOW.x <= SCALE_PLATE.min_x && SCALE_AIM_HIGH.x >= SCALE_PLATE.max_x, "the aim box is wider than the plate")
	testing.expect(t, SCALE_AIM_LOW.z <= SCALE_PLATE.min_z && SCALE_AIM_HIGH.z >= SCALE_PLATE.max_z, "and deeper")
	testing.expect(t, SCALE_AIM_LOW.y == COUNTER_HEIGHT && SCALE_AIM_HIGH.y > COUNTER_HEIGHT + SCALE_PLATE_TOP, "and taller than the plate")
}

@(test)
the_cabinet_is_flat_on_the_north_wall_over_the_counter_and_away_from_the_hood :: proc(t: ^testing.T) {
	c := FIRST_AID_CENTER
	testing.expect(t, abs((c.z - 0.07) - (-ROOM_D * 0.5)) < 0.001, "its back is on the wall")
	testing.expect(t, c.y - 0.3 > COUNTER_HEIGHT + 0.3, "over the counter, with room under it for what stands there")
	testing.expect(t, c.y + 0.3 < ROOM_H, "under the ceiling")
	testing.expect(t, c.x + 0.25 < HOOD.min_x - 0.2, "away from the hood")
	for o, k in other_footprints() {
		testing.expectf(t, !(c.x + 0.25 > o.min_x - 0.1 && c.x - 0.25 < o.max_x + 0.1 && o.min_z < -7.0), "the cabinet is over piece %d", k)
	}
	// The aim box is inside the cabinet's width and height, and reaches its front.
	testing.expect(t, FIRST_AID_AIM_LOW.x >= c.x - 0.3 && FIRST_AID_AIM_HIGH.x <= c.x + 0.3, "the aim box is as wide as the cabinet")
	testing.expect(t, FIRST_AID_AIM_LOW.y >= c.y - 0.35 && FIRST_AID_AIM_HIGH.y <= c.y + 0.35, "and as tall")
	testing.expect(t, FIRST_AID_AIM_HIGH.z >= c.z + 0.05, "and reaches the front")
	// The cross is on the front, which is toward the room.
	l := new(Layout)
	defer free(l)
	before := l.box_count
	add_first_aid(l)
	testing.expect_value(t, l.box_count, before + 6)
	for i in before + 2 ..= before + 3 {
		testing.expect(t, l.boxes[i].center.z > c.z + 0.07, "the cross is in front of the door")
		testing.expect(t, l.boxes[i].color == [4]u8{214, 38, 38, 255}, "and red")
	}
}

@(test)
the_shelves_are_on_the_south_wall_over_the_counter_and_clear_of_the_equipment_there :: proc(t: ^testing.T) {
	heights := SHELF_HEIGHTS
	testing.expect(t, SHELF_Z + SHELF_DEPTH * 0.5 <= ROOM_D * 0.5 + 0.001, "the boards are in the room")
	testing.expect(t, SHELF_Z + SHELF_DEPTH * 0.5 >= ROOM_D * 0.5 - 0.001, "against the wall")
	testing.expect(t, heights[0] - COUNTER_HEIGHT >= 0.6, "the lower shelf clears what stands on the counter")
	testing.expect(t, heights[1] + 0.3 < ROOM_H, "and the upper is under the ceiling")
	testing.expect(t, heights[1] - heights[0] > 0.4, "the shelves are far enough apart for the bottles")
	testing.expect(t, SHELF_X1 + 0.3 < FILLER_CLAMP.x - 0.5, "clear of the balloon filler")
	testing.expect(t, SHELF_X1 + 0.3 < SLOT_FIRST_X - 0.5, "and of the loadout rack")
	testing.expect(t, SHELF_X0 - 0.3 > -ROOM_W * 0.5, "inside the west end")
	// The bottles are apart from each other and inside the boards.
	for i in 1 ..< SHELF_BOTTLES_PER_SHELF {
		d := shelf_bottle(i).x - shelf_bottle(i - 1).x
		testing.expect(t, d > 0.3 && d < 0.4, "bottles a hand apart, wider than a bottle")
	}
	testing.expect_value(t, shelf_bottle(0).x, SHELF_X0)
	testing.expect_value(t, shelf_bottle(SHELF_BOTTLES_PER_SHELF - 1).x, SHELF_X1)
	testing.expect(t, shelf_bottle(SHELF_BOTTLES_PER_SHELF).y > shelf_bottle(0).y + 0.4, "the second twenty are on the upper shelf")
	testing.expect_value(t, shelf_bottle(SHELF_BOTTLES_PER_SHELF).x, SHELF_X0)
	// The racks of the south counter are under the shelves.
	for i in 2 ..< VIAL_RACK_COUNT {
		f := rack_footprint(i)
		testing.expect(t, f.min_x > SHELF_X0 && f.max_x < SHELF_X1, "a rack of the south counter is under the shelves")
	}
}

@(test)
each_bottle_is_a_coloured_body_a_cap_and_a_label_on_the_side_toward_the_room :: proc(t: ^testing.T) {
	l := new(Layout)
	defer free(l)
	colors := [][4]u8{{255, 10, 10, 255}, {10, 255, 10, 255}, {10, 10, 255, 255}}
	add_shelves(l, colors)
	for i in 0 ..< SHELF_BOTTLES {
		body := l.boxes[6 + 3 * i]
		cap := l.boxes[6 + 3 * i + 1]
		label := l.boxes[6 + 3 * i + 2]
		b := shelf_bottle(i)
		testing.expect_value(t, body.color, colors[i % 3])
		testing.expect(t, body.emissive > 0, "a bottle glows a little, like those of the bottle wall")
		testing.expect(t, cap.center.y > body.center.y + body.size.y * 0.5 - 0.001, "the cap is on top")
		testing.expect(t, cap.size.x < body.size.x, "and narrower")
		testing.expect(t, label.center.z < body.center.z - body.size.z * 0.5, "the label is on the face toward the room")
		testing.expect(t, label.size.x < body.size.x && label.color == [4]u8{240, 236, 220, 255}, "pale, and narrower than the bottle")
		testing.expect(t, abs(body.center.x - b.x) < 0.001 && body.center.y - body.size.y * 0.5 >= b.y - 0.001, "the bottle stands on its board")
	}
	// With no colours given the bottles are plain, and nothing goes wrong.
	plain := new(Layout)
	defer free(plain)
	add_shelves(plain, nil)
	testing.expect_value(t, plain.boxes[6].color, [4]u8{200, 200, 200, 255})
}

@(test)
the_numbers_of_the_equipment_are_the_documented_ones :: proc(t: ^testing.T) {
	testing.expect_value(t, VIAL_RACK_COUNT, 4)
	testing.expect_value(t, VIAL_RACK_COLS, 6)
	testing.expect_value(t, VIAL_RACK_ROWS, 2)
	testing.expect_value(t, VIAL_SLOT_SPACING, f32(0.05))
	testing.expect(t, abs(VIAL_SLOT_FLOOR - COUNTER_HEIGHT - 0.03) < 1e-5, "a vial's foot is 3 cm over the counter")
	testing.expect(t, abs(VIAL_DECK_TOP - COUNTER_HEIGHT - 0.06) < 1e-5, "and the deck 6 cm")
	testing.expect_value(t, VIAL_SLOT_SNAP, f32(0.03))
	testing.expect_value(t, SCALE_PLATE_TOP, f32(0.07))
	testing.expect(t, abs(SCALE_PLATE.max_x - SCALE_PLATE.min_x - 0.4) < 1e-5 && abs(SCALE_PLATE.max_z - SCALE_PLATE.min_z - 0.35) < 1e-5, "the plate is 40 cm by 35 cm")
	testing.expect(t, abs(SCALE_PLATE.min_x + SCALE_PLATE.max_x) < 1e-5, "and centred at x = 0")
	testing.expect_value(t, SHELF_BOTTLES, 40)
	heights := SHELF_HEIGHTS
	testing.expect_value(t, heights[0], f32(1.85))
	testing.expect_value(t, heights[1], f32(2.35))
}

@(test)
the_racks_face_the_player_who_stands_at_the_counter_and_the_first_holes_are_the_near_row :: proc(t: ^testing.T) {
	racks := VIAL_RACKS
	// The north counter is walked up to from the south, so its racks face +z, and the south counter's face -z.
	testing.expect_value(t, racks[0].front, f32(1))
	testing.expect_value(t, racks[1].front, f32(1))
	testing.expect_value(t, racks[2].front, f32(-1))
	testing.expect_value(t, racks[3].front, f32(-1))
	for rack in 0 ..< VIAL_RACK_COUNT {
		near_row, far_row := vial_slot(rack, 0), vial_slot(rack, VIAL_RACK_COLS)
		testing.expect(t, abs(near_row.z - racks[rack].z - racks[rack].front * 0.025) < 1e-5, "the first row is 2.5 cm toward the player")
		testing.expect(t, abs(far_row.z - racks[rack].z + racks[rack].front * 0.025) < 1e-5, "and the second 2.5 cm away")
	}
}
