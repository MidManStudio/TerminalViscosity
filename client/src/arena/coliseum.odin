// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "coliseum.odin"
// ============================================================================

package arena

import "core:math"

MAX_PIECES :: 1200 // a mesh with 16-bit indices holds 2730 boxes, so this leaves room
RING_SEGMENTS :: 72 // boxes in each ring of the stands
TIER_COUNT :: 5 // rows of seating
TIER_DEPTH :: f32(1.8) // how far each tier reaches outward, in metres
WALL_INNER :: ARENA_RADIUS // the podium wall starts where the floor ends
WALL_DEPTH :: f32(0.6)
WALL_HEIGHT :: f32(2.4)
TIER_RISE :: f32(1.0) // how much higher each tier is than the one before it
FACADE_RADIUS :: f32(30.2) // the middle of the outer wall
FACADE_DEPTH :: f32(1.2)
FACADE_HEIGHT :: f32(12)
AISLE_EVERY :: 9 // every ninth box of a tier is a stair
FLOOR_FLAT :: f32(0.05) // anything this low or lower is a marking on the sand, not a thing to walk into
GATE_PROTRUSION :: f32(0.08) // how far a door and its frame stand out of the podium wall, into the arena

// A box standing in the coliseum, turned by `yaw` around the vertical axis through its
// centre. Turned by yaw, the z side of the box points along (sin yaw, cos yaw) on the floor
// and its x side along (cos yaw, -sin yaw), which `piece_corner` spells out. `emissive` and
// `gloss` mean what they do for the lab's boxes.
Piece :: struct {
	center:   Vec3,
	size:     Vec3,
	yaw:      f32,
	color:    [4]u8,
	emissive: f32,
	gloss:    f32,
}

Coliseum :: struct {
	pieces: [MAX_PIECES]Piece,
	count:  int,
}

SAND :: [4]u8{222, 196, 146, 255}
SAND_DARK :: [4]u8{196, 166, 116, 255}
STONE :: [4]u8{210, 192, 156, 255}
STONE_LIGHT :: [4]u8{228, 214, 182, 255}
STAIR :: [4]u8{150, 130, 106, 255}
DOOR :: [4]u8{92, 62, 44, 255}
DARK_OPENING :: [4]u8{74, 56, 48, 255}
SEAT_A :: [4]u8{214, 168, 120, 255}
SEAT_B :: [4]u8{194, 140, 100, 255}
SEAT_C :: [4]u8{222, 182, 134, 255}
SEAT_D :: [4]u8{204, 154, 112, 255}
BANNER_RED :: [4]u8{176, 44, 44, 255}
BANNER_BLUE :: [4]u8{44, 74, 152, 255}

piece_add :: proc(c: ^Coliseum, p: Piece) {
	if c.count == MAX_PIECES {
		return
	}
	c.pieces[c.count] = p
	c.count += 1
}

// The direction the radial (z) side of a ring piece at angle `theta` points, as a turn.
// Rotating a box by `yaw` around the vertical axis sends its z axis to (sin yaw, cos yaw),
// so a piece whose z axis must point along (cos theta, sin theta) is turned by this.
radial_yaw :: proc(theta: f32) -> f32 {
	return math.atan2(math.cos(theta), math.sin(theta))
}

// The chord of a ring of `count` boxes at `radius`: how wide each box must be to meet its
// neighbours.
ring_chord :: proc(radius: f32, count: int) -> f32 {
	return 2 * radius * math.sin(math.PI / f32(count))
}

// A ring of boxes round the middle of the arena, standing on the floor. `radius` is the
// middle of the ring's depth, and `bottom` and `top` are heights. `color_of` picks the
// colour and a lowering of the top for box `i`, so a ring can have stairs in it.
ring :: proc(c: ^Coliseum, radius, depth, bottom, top: f32, count: int, color: [4]u8, gloss: f32 = 0) {
	for i in 0 ..< count {
		ring_piece(c, i, count, radius, depth, bottom, top, color, gloss)
	}
}

ring_piece :: proc(c: ^Coliseum, i, count: int, radius, depth, bottom, top: f32, color: [4]u8, gloss: f32 = 0) {
	theta := 2 * math.PI * f32(i) / f32(count)
	piece_add(c, {
		center = {radius * math.cos(theta), (bottom + top) * 0.5, radius * math.sin(theta)},
		size   = {ring_chord(radius, count) * 1.06, top - bottom, depth},
		yaw    = radial_yaw(theta),
		color  = color,
		gloss  = gloss,
	})
}

// A single box at angle `theta` and distance `radius` from the middle, turned to face it.
at_angle :: proc(c: ^Coliseum, theta, radius: f32, size: Vec3, y: f32, color: [4]u8, emissive: f32 = 0) {
	piece_add(c, {
		center   = {radius * math.cos(theta), y, radius * math.sin(theta)},
		size     = size,
		yaw      = radial_yaw(theta),
		color    = color,
		emissive = emissive,
	})
}

// Fills the coliseum: a sand floor with rings drawn on it, a podium wall with four gates,
// five tiers of seats cut by stairs, and a tall outer wall with openings, columns, and
// banners. Everything above the sand is outside `ARENA_RADIUS`.
coliseum_build :: proc(c: ^Coliseum) {
	c^ = {}
	reach := FACADE_RADIUS + FACADE_DEPTH

	// The sand, one slab under everything, and rings drawn on it.
	piece_add(c, {center = {0, -0.25, 0}, size = {reach * 2 + 2, 0.5, reach * 2 + 2}, color = SAND, gloss = 0.05})
	ring(c, ARENA_RADIUS - 0.5, 0.4, 0, 0.02, 64, SAND_DARK)
	ring(c, 7, 0.3, 0, 0.02, 48, SAND_DARK)

	// The podium wall.
	ring(c, WALL_INNER + WALL_DEPTH * 0.5, WALL_DEPTH, 0, WALL_HEIGHT, RING_SEGMENTS, STONE, 0.1)

	// The tiers: each is higher than the last, and every ninth box is a stair, a little
	// lower and darker, so the seats read as blocks.
	for k in 0 ..< TIER_COUNT {
		inner := WALL_INNER + WALL_DEPTH + f32(k) * TIER_DEPTH
		top := WALL_HEIGHT + f32(k + 1) * TIER_RISE
		for i in 0 ..< RING_SEGMENTS {
			if i % AISLE_EVERY == 0 {
				ring_piece(c, i, RING_SEGMENTS, inner + TIER_DEPTH * 0.5, TIER_DEPTH, 0, top - 0.15, STAIR)
				continue
			}
			block := i / AISLE_EVERY
			even := (k + block) % 2 == 0
			color := even ? SEAT_A : SEAT_B
			if block % 2 == 1 {
				color = even ? SEAT_C : SEAT_D
			}
			ring_piece(c, i, RING_SEGMENTS, inner + TIER_DEPTH * 0.5, TIER_DEPTH, 0, top, color)
		}
	}

	// The outer wall, and the ledge along its top.
	ring(c, FACADE_RADIUS, FACADE_DEPTH, 0, FACADE_HEIGHT, RING_SEGMENTS, STONE_LIGHT, 0.1)
	ring(c, FACADE_RADIUS, FACADE_DEPTH + 0.5, FACADE_HEIGHT, FACADE_HEIGHT + 0.6, RING_SEGMENTS, STONE)

	// Dark openings and columns along the inside of the outer wall, above the seats.
	face := FACADE_RADIUS - FACADE_DEPTH * 0.5
	for i in 0 ..< RING_SEGMENTS / 2 {
		theta := 2 * math.PI * (f32(i) + 0.5) / f32(RING_SEGMENTS / 2)
		at_angle(c, theta, face - 0.1, {1.2, 2.8, 0.2}, 9.6, DARK_OPENING)
		at_angle(c, theta + math.PI / f32(RING_SEGMENTS / 2), face - 0.25, {0.5, 4.6, 0.5}, 9.7, STONE)
	}

	// Four gates in the podium wall, at the compass points: a door between two pillars
	// under a lintel. Banners hang above them on the outer wall.
	for g in 0 ..< 4 {
		theta := math.PI * 0.5 * f32(g)
		door_r := WALL_INNER - GATE_PROTRUSION + 0.15
		frame_r := WALL_INNER - GATE_PROTRUSION + 0.25
		at_angle(c, theta, door_r, {3.0, 2.0, 0.3}, 1.0, DOOR)
		for side in ([2]f32{-1, 1}) {
			// A pillar to the side of the door: along the wall is the direction (-sin, cos).
			sx := -math.sin(theta) * side * 1.8
			sz := math.cos(theta) * side * 1.8
			piece_add(c, {
				center = {frame_r * math.cos(theta) + sx, 1.15, frame_r * math.sin(theta) + sz},
				size   = {0.5, 2.3, 0.5},
				yaw    = radial_yaw(theta),
				color  = STONE_LIGHT,
			})
		}
		at_angle(c, theta, frame_r, {4.3, 0.4, 0.5}, 2.2, STONE_LIGHT)
		banner := g % 2 == 0 ? BANNER_RED : BANNER_BLUE
		at_angle(c, theta, FACADE_RADIUS - FACADE_DEPTH * 0.5 - 0.05, {2.2, 5.0, 0.1}, 8.4, banner)
	}
}

// The rotated footprint of a piece from above, as the distance from the middle of the arena
// to the nearest point of it. Used to check that nothing tall stands on the sand.
piece_distance :: proc(p: Piece) -> f32 {
	// The origin, in the box's own axes: rotate by -yaw. A box turned by yaw has its x axis
	// along (cos yaw, -sin yaw) and its z axis along (sin yaw, cos yaw).
	s, co := math.sin(p.yaw), math.cos(p.yaw)
	rel := Vec3{-p.center.x, 0, -p.center.z}
	lx := rel.x * co - rel.z * s
	lz := rel.x * s + rel.z * co
	nx := clamp(lx, -p.size.x * 0.5, p.size.x * 0.5)
	nz := clamp(lz, -p.size.z * 0.5, p.size.z * 0.5)
	return math.sqrt((lx - nx) * (lx - nx) + (lz - nz) * (lz - nz))
}

piece_top :: proc(p: Piece) -> f32 {
	return p.center.y + p.size.y * 0.5
}

// The corner `i` (0 to 3, going round) of the top of a piece, in the world. The mesh builder
// and the tests both use it, so the turn is defined in one place.
piece_corner :: proc(p: Piece, i: int, y: f32) -> Vec3 {
	sx := (i == 0 || i == 3) ? f32(-1) : 1
	sz := (i < 2) ? f32(-1) : 1
	lx, lz := sx * p.size.x * 0.5, sz * p.size.z * 0.5
	s, co := math.sin(p.yaw), math.cos(p.yaw)
	return {p.center.x + lx * co + lz * s, y, p.center.z - lx * s + lz * co}
}
