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

// A hollow glass vessel, empty for now. The profile runs up the outside, over
// the rim, and down the inside to the inner floor.
vessel_shape :: proc(s: ^Shape, k: Kind) {
	s^ = {}
	s.gloss = 0.6
	d := kind_dims(k)
	r, h, t := d.radius, d.height, VESSEL_WALL
	glass := [4]u8{150, 200, 225, 255}
	rim := [4]u8{226, 238, 246, 255}
	inner := [4]u8{104, 154, 184, 255}
	switch k {
	case .Beaker:
		profile := [?][2]f32{{0, 0}, {r, 0}, {r, h}, {r - t, h}, {r - t, t}, {0, t}}
		colors := [?][4]u8{glass, glass, rim, inner, inner}
		lathe_build(s, profile[:], colors[:], SHAPE_SEGMENTS)
	case .Flask:
		// A cone that narrows to a neck, like an Erlenmeyer flask.
		nr := r * 0.28
		shoulder := h * 0.62
		green := [4]u8{150, 214, 184, 255}
		profile := [?][2]f32{{0, 0}, {r, 0}, {nr, shoulder}, {nr, h}, {nr - t, h}, {nr - t, shoulder}, {r - t, t}, {0, t}}
		colors := [?][4]u8{green, green, green, rim, inner, inner, inner}
		lathe_build(s, profile[:], colors[:], SHAPE_SEGMENTS)
	case .Bottle:
		// A closed stock bottle: body, shoulder, neck and a dark cap.
		nr := r * 0.42
		cr := nr + 0.004
		amber := [4]u8{176, 112, 52, 255}
		cap := [4]u8{48, 56, 68, 255}
		profile := [?][2]f32{{0, 0}, {r, 0}, {r, h * 0.58}, {nr, h * 0.78}, {nr, h * 0.86}, {cr, h * 0.86}, {cr, h}, {0, h}}
		colors := [?][4]u8{amber, amber, amber, amber, cap, cap, cap}
		lathe_build(s, profile[:], colors[:], SHAPE_SEGMENTS)
	}
}
