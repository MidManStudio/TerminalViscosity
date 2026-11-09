// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "equipment.odin"
// ============================================================================

package lab

// The smaller equipment of the lab: racks that small vials stand in, a first aid cabinet on
// the north wall, a scale on the north counter, and two shelves of labelled bottles on the
// south wall. What the cabinet and the scale do is in package carry; this file says where
// they are and builds what is static. Units are metres.

// Four racks of vials, two on the north counter at its west end and two on the south counter,
// each with two rows of six holes. A vial stands in a hole with its foot on the lower plate,
// under the deck. A rack is a frame, and where the vials stand is `vial_slot`.
VIAL_RACK_COUNT :: 4
VIAL_RACK_COLS :: 6
VIAL_RACK_ROWS :: 2
VIAL_SLOTS_PER_RACK :: VIAL_RACK_COLS * VIAL_RACK_ROWS
VIAL_SLOT_SPACING :: f32(0.05)
VIAL_SLOT_FLOOR :: COUNTER_HEIGHT + 0.03 // where the foot of a vial in a rack stands: the lower plate
VIAL_DECK_TOP :: COUNTER_HEIGHT + 0.06 // the top of the deck the vials pass through
VIAL_SLOT_SNAP :: f32(0.03) // how far from a hole a vial can be let go and still be drawn into it

Vial_Rack :: struct {
	x, z:  f32, // the middle of the rack, on the counter
	front: f32, // which way the player stands: 1 is toward +z, -1 toward -z
}

VIAL_RACKS :: [VIAL_RACK_COUNT]Vial_Rack{{-10.4, -7.62, 1}, {-9.6, -7.62, 1}, {-8.0, 7.62, -1}, {-7.2, 7.62, -1}}

// Where the foot of a vial in hole `slot` (0 to 11, six to a row) of rack `rack` stands. The
// first six holes are the row nearer the player, so that the vials that start in a rack, which
// are in the first holes, are the ones the crosshair can reach, and the row behind is free.
vial_slot :: proc(rack, slot: int) -> Vec3 {
	racks := VIAL_RACKS
	r := racks[rack]
	col, row := slot % VIAL_RACK_COLS, slot / VIAL_RACK_COLS
	side := row == 0 ? r.front : -r.front
	return {r.x + (f32(col) - 2.5) * VIAL_SLOT_SPACING, VIAL_SLOT_FLOOR, r.z + side * VIAL_SLOT_SPACING * 0.5}
}

// The first aid cabinet, on the north wall over the counter. The wall is at z = -8.
FIRST_AID_CENTER :: Vec3{-8.2, 1.85, -7.93}
FIRST_AID_AIM_LOW :: Vec3{-8.5, 1.5, -7.99}
FIRST_AID_AIM_HIGH :: Vec3{-7.9, 2.2, -7.82}

// The scale on the north counter, between the ice bath and the oven. A vessel whose middle is
// inside `SCALE_PLATE` stands on the plate, `SCALE_PLATE_TOP` over the counter, and is weighed.
SCALE_PLATE :: Rect {
	min_x = -0.2,
	min_z = -7.8,
	max_x = 0.2,
	max_z = -7.45,
}
SCALE_PLATE_TOP :: f32(0.07)
SCALE_AIM_LOW :: Vec3{-0.26, COUNTER_HEIGHT, -7.86}
SCALE_AIM_HIGH :: Vec3{0.26, COUNTER_HEIGHT + 0.22, -7.4}

// Two shelves of bottles on the south wall, over the south counter, east of the vial racks.
// The wall is at z = 8.
SHELF_X0 :: f32(-10.2)
SHELF_X1 :: f32(-3.0)
SHELF_Z :: f32(7.88) // the middle of a shelf board from front to back
SHELF_DEPTH :: f32(0.24)
SHELF_HEIGHTS :: [2]f32{1.85, 2.35}
SHELF_BOTTLES_PER_SHELF :: 20
SHELF_BOTTLES :: 2 * SHELF_BOTTLES_PER_SHELF

// Where the middle of the foot of bottle `i` of the shelves stands: the first twenty on the
// lower shelf from the west, then twenty on the upper.
shelf_bottle :: proc(i: int) -> Vec3 {
	row, col := i / SHELF_BOTTLES_PER_SHELF, i % SHELF_BOTTLES_PER_SHELF
	step := (SHELF_X1 - SHELF_X0) / f32(SHELF_BOTTLES_PER_SHELF - 1)
	heights := SHELF_HEIGHTS
	return {SHELF_X0 + step * f32(col), heights[row] + 0.015, SHELF_Z}
}

// Adds the boxes of the vial racks, the first aid cabinet and the scale.
add_equipment :: proc(l: ^Layout) {
	add_vial_racks(l)
	add_first_aid(l)
	add_scale(l)
}

add_vial_racks :: proc(l: ^Layout) {
	racks := VIAL_RACKS
	frame := [4]u8{64, 70, 80, 255}
	hole := [4]u8{16, 20, 26, 255}
	width := f32(VIAL_RACK_COLS) * VIAL_SLOT_SPACING + 0.04
	depth := f32(VIAL_RACK_ROWS) * VIAL_SLOT_SPACING + 0.04
	for r in racks {
		add_box(l, {r.x, VIAL_SLOT_FLOOR - 0.006, r.z}, {width, 0.012, depth}, frame, 0, 0.4) // the lower plate
		add_box(l, {r.x, VIAL_DECK_TOP - 0.006, r.z}, {width, 0.012, depth}, frame, 0, 0.4) // the deck
		for sx in ([2]f32{-1, 1}) {
			for sz in ([2]f32{-1, 1}) {
				add_box(l, {r.x + sx * (width * 0.5 - 0.006), (VIAL_SLOT_FLOOR + VIAL_DECK_TOP) * 0.5 - 0.006, r.z + sz * (depth * 0.5 - 0.006)}, {0.012, VIAL_DECK_TOP - VIAL_SLOT_FLOOR, 0.012}, frame, 0, 0.4) // the posts
			}
		}
	}
	for rack in 0 ..< VIAL_RACK_COUNT {
		for slot in 0 ..< VIAL_SLOTS_PER_RACK {
			s := vial_slot(rack, slot)
			add_box(l, {s.x, VIAL_DECK_TOP + 0.0005, s.z}, {0.028, 0.001, 0.028}, hole) // a hole in the deck
		}
	}
}

add_first_aid :: proc(l: ^Layout) {
	c := FIRST_AID_CENTER
	white := [4]u8{238, 240, 242, 255}
	red := [4]u8{214, 38, 38, 255}
	front := c.z + 0.07
	add_box(l, c, {0.5, 0.6, 0.14}, white, 0, 0.5) // the cabinet
	add_box(l, {c.x, c.y, front + 0.002}, {0.012, 0.5, 0.004}, {150, 156, 164, 255}) // the seam of the doors
	add_box(l, {c.x, c.y + 0.06, front + 0.004}, {0.26, 0.07, 0.006}, red, 0.6) // the cross, across
	add_box(l, {c.x, c.y + 0.06, front + 0.004}, {0.07, 0.26, 0.006}, red, 0.6) // and up
	add_box(l, {c.x - 0.1, c.y - 0.2, front + 0.008}, {0.03, 0.03, 0.016}, COLOR_METAL, 0, 0.5) // the left handle
	add_box(l, {c.x + 0.1, c.y - 0.2, front + 0.008}, {0.03, 0.03, 0.016}, COLOR_METAL, 0, 0.5) // the right handle
}

add_scale :: proc(l: ^Layout) {
	p := SCALE_PLATE
	cx, cz := (p.min_x + p.max_x) * 0.5, (p.min_z + p.max_z) * 0.5
	w, d := p.max_x - p.min_x, p.max_z - p.min_z
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {w + 0.1, 0.04, d + 0.1}, COLOR_METAL, 0, 0.5) // the body
	add_box(l, {cx, COUNTER_HEIGHT + SCALE_PLATE_TOP - 0.015, cz}, {w, 0.03, d}, COLOR_STEEL, 0, 0.9) // the plate
	add_box(l, {cx, COUNTER_HEIGHT + 0.025, p.max_z + 0.055}, {0.2, 0.035, 0.012}, {16, 20, 26, 255}, 0, 0.6) // the display, on the front
	add_box(l, {cx, COUNTER_HEIGHT + 0.025, p.max_z + 0.062}, {0.14, 0.012, 0.004}, COLOR_GLOW, 1) // and its light
}

// Adds the two shelves of the south wall: a board and two brackets under each, and a bottle
// on each at the places `shelf_bottle` gives, a glass body in a colour, a dark cap, and a pale label
// across the front. `colors` are the colours of the bottles in turn, and are used over again
// when there are fewer of them than bottles. The labels carry no writing.
add_shelves :: proc(l: ^Layout, colors: [][4]u8) {
	heights := SHELF_HEIGHTS
	length := SHELF_X1 - SHELF_X0 + 0.5
	middle := (SHELF_X0 + SHELF_X1) * 0.5
	for h in heights {
		add_box(l, {middle, h - 0.015, SHELF_Z}, {length, 0.03, SHELF_DEPTH}, COLOR_COUNTER, 0, 0.3) // the board
		for x in ([2]f32{SHELF_X0 - 0.2, SHELF_X1 + 0.2}) {
			add_box(l, {x, h - 0.1, SHELF_Z + SHELF_DEPTH * 0.5 - 0.02}, {0.03, 0.14, 0.03}, COLOR_METAL, 0, 0.5) // a bracket
		}
	}
	label := [4]u8{240, 236, 220, 255}
	for i in 0 ..< SHELF_BOTTLES {
		b := shelf_bottle(i)
		color := len(colors) > 0 ? colors[i % len(colors)] : [4]u8{200, 200, 200, 255}
		add_box(l, {b.x, b.y + 0.11, b.z}, {0.11, 0.22, 0.11}, color, 0.25, 0.5) // the bottle
		add_box(l, {b.x, b.y + 0.235, b.z}, {0.06, 0.05, 0.06}, COLOR_METAL, 0, 0.5) // the cap
		add_box(l, {b.x, b.y + 0.11, b.z - 0.057}, {0.085, 0.09, 0.004}, label, 0.1) // the label, toward the room
	}
}
