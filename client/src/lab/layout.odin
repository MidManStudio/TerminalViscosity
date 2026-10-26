// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "layout.odin"
// ============================================================================

// Package lab is the chemistry lab as data: the boxes it is built from, the
// footprints a player cannot walk through, and the player who walks around it.
// Units are metres. It has no raylib dependency, so it is tested without a window.
package lab

Vec3 :: [3]f32

MAX_BOXES :: 96
MAX_COLLIDERS :: 8

ROOM_W :: f32(24) // along x
ROOM_D :: f32(16) // along z
ROOM_H :: f32(3.6)
COUNTER_HEIGHT :: f32(1.1)

// The bottle wall on the east side: ten dispensers in a row above a counter,
// each with a nozzle that a held vessel can be put under.
DISPENSER_COUNT :: 10
DISPENSER_SPACING :: f32(0.9)
DISPENSER_NOZZLE_X :: f32(11.55)
DISPENSER_NOZZLE_Y :: f32(1.61) // height of the tip of a nozzle

// A box to draw. `emissive` is how much it glows by its own light, from 0 to
// 1, and `gloss` is how much it reflects the room, from 0 to 1.
Box :: struct {
	center:   Vec3,
	size:     Vec3,
	color:    [4]u8,
	emissive: f32,
	gloss:    f32,
}

// A footprint on the floor that the player cannot enter.
Rect :: struct {
	min_x, min_z, max_x, max_z: f32,
}

Layout :: struct {
	boxes:          [MAX_BOXES]Box,
	box_count:      int,
	colliders:      [MAX_COLLIDERS]Rect,
	collider_count: int,
	spawn:          Vec3, // where the player starts, eye height ignored
	spawn_yaw:      f32,
}

COLOR_FLOOR :: [4]u8{196, 204, 212, 255}
COLOR_WALL :: [4]u8{224, 228, 233, 255}
COLOR_CEILING :: [4]u8{212, 218, 225, 255}
COLOR_COUNTER :: [4]u8{46, 54, 64, 255}
COLOR_COUNTER_TOP :: [4]u8{34, 78, 92, 255}
COLOR_GLOW :: [4]u8{60, 230, 215, 255}
COLOR_LIGHT :: [4]u8{255, 255, 255, 255}

add_box :: proc(l: ^Layout, center, size: Vec3, color: [4]u8, emissive: f32 = 0, gloss: f32 = 0) {
	if l.box_count == MAX_BOXES {
		return
	}
	l.boxes[l.box_count] = {center, size, color, emissive, gloss}
	l.box_count += 1
}

// A counter standing on the floor inside `area`: a glowing plinth, a dark body,
// and a light top that overhangs a little. It also blocks the player.
add_counter :: proc(l: ^Layout, area: Rect) {
	cx := (area.min_x + area.max_x) * 0.5
	cz := (area.min_z + area.max_z) * 0.5
	w := area.max_x - area.min_x
	d := area.max_z - area.min_z
	plinth := f32(0.12)
	top := f32(0.04)
	body := COUNTER_HEIGHT - plinth - top
	add_box(l, {cx, plinth * 0.5, cz}, {w - 0.1, plinth, d - 0.1}, COLOR_GLOW, 1)
	add_box(l, {cx, plinth + body * 0.5, cz}, {w, body, d}, COLOR_COUNTER)
	add_box(l, {cx, plinth + body + top * 0.5, cz}, {w + 0.04, top, d + 0.06}, COLOR_COUNTER_TOP, 0, 0.5)
	if l.collider_count < MAX_COLLIDERS {
		l.colliders[l.collider_count] = area
		l.collider_count += 1
	}
}

// Where the tip of nozzle `i` of the bottle wall is, counting from the south.
dispenser_nozzle :: proc(i: int) -> Vec3 {
	return {DISPENSER_NOZZLE_X, DISPENSER_NOZZLE_Y, (f32(i) - 4.5) * DISPENSER_SPACING}
}

// Adds the rack of the bottle wall: a backboard, and for each dispenser a bottle
// in the color of its liquid, an arm, and a nozzle. The colors are given so the
// bottles match what comes out of them.
add_dispensers :: proc(l: ^Layout, colors: [DISPENSER_COUNT][4]u8) {
	x_wall := ROOM_W * 0.5
	add_box(l, {x_wall - 0.04, 1.9, 0}, {0.08, 1.8, 9.7}, COLOR_COUNTER)
	metal := [4]u8{70, 78, 90, 255}
	for i in 0 ..< DISPENSER_COUNT {
		z := dispenser_nozzle(i).z
		add_box(l, {x_wall - 0.14, 2.15, z}, {0.2, 0.5, 0.2}, colors[i], 0.3, 0.5) // the bottle
		add_box(l, {x_wall - 0.14, 2.43, z}, {0.12, 0.06, 0.12}, metal, 0, 0.5) // its cap
		add_box(l, {(x_wall - 0.14 + DISPENSER_NOZZLE_X) * 0.5, 1.84, z}, {x_wall - 0.14 - DISPENSER_NOZZLE_X, 0.05, 0.05}, metal, 0, 0.5) // the arm
		add_box(l, {DISPENSER_NOZZLE_X, DISPENSER_NOZZLE_Y + 0.11, z}, {0.06, 0.22, 0.06}, metal, 0, 0.5) // the nozzle
	}
}

// Fills the layout: a large open room with long counters along the north, south,
// and west walls, a counter for the bottle wall on the east wall with a way
// round it at each end, an island in the middle, and rows of ceiling lights.
build :: proc(l: ^Layout) {
	l^ = {}
	half_w := ROOM_W * 0.5
	half_d := ROOM_D * 0.5
	thick := f32(0.5)

	add_box(l, {0, -thick * 0.5, 0}, {ROOM_W + 2 * thick, thick, ROOM_D + 2 * thick}, COLOR_FLOOR, 0, 1)
	add_box(l, {0, ROOM_H * 0.5, -half_d - thick * 0.5}, {ROOM_W + 2 * thick, ROOM_H, thick}, COLOR_WALL)
	add_box(l, {0, ROOM_H * 0.5, half_d + thick * 0.5}, {ROOM_W + 2 * thick, ROOM_H, thick}, COLOR_WALL)
	add_box(l, {-half_w - thick * 0.5, ROOM_H * 0.5, 0}, {thick, ROOM_H, ROOM_D}, COLOR_WALL)
	add_box(l, {half_w + thick * 0.5, ROOM_H * 0.5, 0}, {thick, ROOM_H, ROOM_D}, COLOR_WALL)
	add_box(l, {0, ROOM_H + thick * 0.5, 0}, {ROOM_W + 2 * thick, thick, ROOM_D + 2 * thick}, COLOR_CEILING)

	// Four rows of light panels, flush with the ceiling.
	for row in 0 ..< 4 {
		z := -half_d + (f32(row) + 0.5) * (ROOM_D / 4)
		for col in 0 ..< 6 {
			x := -half_w + (f32(col) + 0.5) * (ROOM_W / 6)
			add_box(l, {x, ROOM_H - 0.03, z}, {2.4, 0.06, 0.28}, COLOR_LIGHT, 1)
		}
	}

	gap := f32(0.02)
	add_counter(l, {-half_w + 0.5, -half_d + gap, half_w - 0.5, -half_d + 0.7 + gap}) // north wall
	add_counter(l, {-half_w + 0.5, half_d - 0.7 - gap, half_w - 0.5, half_d - gap}) // south wall
	add_counter(l, {-half_w + gap, -half_d + 1.2, -half_w + 0.7 + gap, half_d - 1.2}) // west wall
	add_counter(l, {-5, -0.7, 5, 0.7}) // the island
	add_counter(l, {half_w - 0.7 - gap, -4.8, half_w - gap, 4.8}) // the bottle wall

	l.spawn = {0, 0, 4.5}
	l.spawn_yaw = 0
}
