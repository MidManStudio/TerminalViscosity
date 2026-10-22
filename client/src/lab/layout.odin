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
COUNTER_HEIGHT :: f32(0.9)

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
COLOR_COUNTER_TOP :: [4]u8{208, 214, 220, 255}
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

// Fills the layout: a large open room with long counters along three walls, one
// island in the middle, and rows of ceiling lights. The east wall is left
// clear so there is a way in.
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

	l.spawn = {0, 0, 4.5}
	l.spawn_yaw = 0
}
