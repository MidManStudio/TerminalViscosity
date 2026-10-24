// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "shapes.odin"
// ============================================================================

package carry

import "core:math"

MAX_SHAPE_VERTS :: 512
MAX_SHAPE_INDICES :: 1536
SHAPE_SEGMENTS :: 14 // steps around a shape that is turned on a lathe
VESSEL_WALL :: f32(0.006) // glass thickness, in metres

// A triangle mesh as plain arrays, with a color for each vertex. The client
// copies it into a raylib mesh. Keeping it here means its winding and normals
// can be tested without a window.
Shape :: struct {
	positions:   [MAX_SHAPE_VERTS]Vec3,
	normals:     [MAX_SHAPE_VERTS]Vec3,
	colors:      [MAX_SHAPE_VERTS][4]u8,
	indices:     [MAX_SHAPE_INDICES]u16,
	vert_count:  int,
	index_count: int,
	gloss:       f32, // how much the lab shader reflects the room from it, 0 to 1
}

push_vertex :: proc(s: ^Shape, p, n: Vec3, c: [4]u8) {
	if s.vert_count >= MAX_SHAPE_VERTS {
		return
	}
	s.positions[s.vert_count] = p
	s.normals[s.vert_count] = n
	s.colors[s.vert_count] = c
	s.vert_count += 1
}

push_triangle :: proc(s: ^Shape, a, b, c: u16) {
	if s.index_count + 3 > MAX_SHAPE_INDICES {
		return
	}
	s.indices[s.index_count], s.indices[s.index_count + 1], s.indices[s.index_count + 2] = a, b, c
	s.index_count += 3
}

// Turns a profile (radius, height pairs) around the vertical axis. Each pair of
// neighbouring points becomes a band with its own color and its own slope, so
// corners stay sharp while the shading is smooth around the shape. The profile
// runs up the outside and down the inside, so the outward normal of a band is
// to the right of the direction of travel.
lathe_build :: proc(s: ^Shape, profile: [][2]f32, band_colors: [][4]u8, segments: int) {
	for i in 0 ..< len(profile) - 1 {
		a, b := profile[i], profile[i + 1]
		dr, dy := b.x - a.x, b.y - a.y
		length := math.sqrt(dr * dr + dy * dy)
		if length < 1e-6 {
			continue
		}
		nr, ny := dy / length, -dr / length
		first := s.vert_count
		for k in 0 ..= segments {
			angle := f32(k) / f32(segments) * math.TAU
			c, sn := math.cos(angle), math.sin(angle)
			n := Vec3{nr * c, ny, nr * sn}
			push_vertex(s, {a.x * c, a.y, a.x * sn}, n, band_colors[i])
			push_vertex(s, {b.x * c, b.y, b.x * sn}, n, band_colors[i])
		}
		for k in 0 ..< segments {
			lo0 := u16(first + k * 2)
			up0 := lo0 + 1
			lo1 := lo0 + 2
			up1 := lo0 + 3
			// Counter-clockwise seen from outside: the next step around is to the left.
			push_triangle(s, lo1, lo0, up0)
			push_triangle(s, lo1, up0, up1)
		}
	}
}

// A cube one unit on each side, centered on the origin, in one color. The
// client scales it to draw the parts of the hands.
box_build :: proc(s: ^Shape, color: [4]u8) {
	s^ = {}
	// Outward normal, then two tangents that turn toward each other the right
	// way round, so the corners come out counter-clockwise seen from outside.
	faces := [6][3]Vec3 {
		{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
		{{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
		{{0, 1, 0}, {0, 0, 1}, {1, 0, 0}},
		{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
		{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
		{{0, 0, -1}, {0, 1, 0}, {1, 0, 0}},
	}
	corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	for f in faces {
		n, t, b := f[0], f[1], f[2]
		first := s.vert_count
		for c in corners {
			push_vertex(s, n * 0.5 + t * (c.x * 0.5) + b * (c.y * 0.5), n, color)
		}
		push_triangle(s, u16(first), u16(first + 1), u16(first + 2))
		push_triangle(s, u16(first), u16(first + 2), u16(first + 3))
	}
}

LIQUID_INSET :: f32(0.0006) // keeps the liquid just inside the glass so the two never fight over a pixel
CAP_OVERHANG :: f32(0.004) // how far a bottle cap is wider than the neck

glass_tint :: proc(k: Kind) -> [4]u8 {
	switch k {
	case .Beaker:
		return {178, 214, 230, 255}
	case .Flask:
		return {186, 226, 205, 255}
	case .Bottle:
		return {205, 188, 150, 255}
	}
	return {200, 220, 230, 255}
}

// The outline of the outside of a vessel from the middle of the base up to the
// mouth, as (radius, height) pairs. Returns how many points.
outer_profile :: proc(k: Kind, out: ^[MAX_PROFILE][2]f32) -> int {
	d := kind_dims(k)
	r, h := d.radius, d.height
	switch k {
	case .Beaker:
		out[0], out[1], out[2] = {0, 0}, {r, 0}, {r, h}
		return 3
	case .Flask:
		nr := r * FLASK_NECK
		out[0], out[1], out[2], out[3] = {0, 0}, {r, 0}, {nr, h * FLASK_SHOULDER}, {nr, h}
		return 4
	case .Bottle:
		nr := r * BOTTLE_NECK
		out[0], out[1], out[2] = {0, 0}, {r, 0}, {r, h * BOTTLE_BODY}
		out[3], out[4] = {nr, h * BOTTLE_SHOULDER}, {nr, h * BOTTLE_NECK_TOP}
		return 5
	}
	return 0
}

// The glass of a vessel: a hollow shell, open at the top. The profile runs up
// the outside, across the rim, and back down the inside to the middle of the
// floor. The client draws it see-through.
vessel_shape :: proc(s: ^Shape, k: Kind) {
	s^ = {}
	s.gloss = 0.6
	outer, inner: [MAX_PROFILE][2]f32
	no := outer_profile(k, &outer)
	ni := interior_profile(k, &inner)
	profile: [MAX_PROFILE * 2][2]f32
	colors: [MAX_PROFILE * 2][4]u8
	n := 0
	for i in 0 ..< no {
		profile[n] = outer[i]
		n += 1
	}
	for i := ni - 1; i >= 0; i -= 1 {
		profile[n] = inner[i]
		n += 1
	}
	tint := glass_tint(k)
	rim := [4]u8{235, 244, 250, 255}
	inside := [4]u8{tint.r - 52, tint.g - 52, tint.b - 40, 255}
	for i in 0 ..< n - 1 {
		switch {
		case i < no - 1:
			colors[i] = tint
		case i == no - 1:
			colors[i] = rim
		case:
			colors[i] = inside
		}
	}
	lathe_build(s, profile[:n], colors[:n - 1], SHAPE_SEGMENTS)
}

// The liquid in a vessel, drawn as a solid that fills the whole inside up to
// the brim. The shader cuts it off at the surface, in world space.
liquid_shape :: proc(s: ^Shape, k: Kind) {
	s^ = {}
	inner: [MAX_PROFILE][2]f32
	ni := interior_profile(k, &inner)
	profile: [MAX_PROFILE][2]f32
	colors: [MAX_PROFILE][4]u8
	for i in 0 ..< ni {
		profile[i] = inner[i]
		if profile[i].x > 0 {
			profile[i].x -= LIQUID_INSET
		}
	}
	profile[ni] = {0, inner[ni - 1].y} // close the top on the axis
	for i in 0 ..< ni {
		colors[i] = {255, 255, 255, 255}
	}
	lathe_build(s, profile[:ni + 1], colors[:ni], SHAPE_SEGMENTS)
}

// The cap of a bottle, a solid piece drawn opaque. Only bottles have one.
cap_shape :: proc(s: ^Shape, k: Kind) -> bool {
	s^ = {}
	if k != .Bottle {
		return false
	}
	d := kind_dims(k)
	cr := d.radius * BOTTLE_NECK + CAP_OVERHANG
	mouth := d.height * BOTTLE_NECK_TOP
	profile := [?][2]f32{{0, mouth}, {cr, mouth}, {cr, d.height}, {0, d.height}}
	dark := [4]u8{48, 56, 68, 255}
	colors := [?][4]u8{dark, dark, dark}
	lathe_build(s, profile[:], colors[:], SHAPE_SEGMENTS)
	return true
}
