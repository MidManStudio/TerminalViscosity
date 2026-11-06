// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "character.odin"
// ============================================================================

// Package character is a temporary player character, built in code from boxes, spheres and
// cylinders in a low-poly style, after the owner's lab-coat design: a round body in a coat with
// lapels, pockets and a badge, a round head with goggles, a mask and a quiff, thin arms with
// round hands, and short legs. It gives the six parts that move, each as a soup of flat-shaded
// triangles in its own space with its pivot at the origin, and the matrices that place them.
// It has no raylib dependency, so it is tested without a window.
package character

import "core:math"

Vec3 :: [3]f32

// A 4 by 4 matrix, row-major, with the move in the last column, the way raylib's matrices are.
// A point is multiplied on the right.
Mat :: [4][4]f32

mat_identity :: proc() -> Mat {
	return {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}
}

// `a` after `b`: the point is moved by `b` first.
mat_mul :: proc(a, b: Mat) -> (m: Mat) {
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			for k in 0 ..< 4 {
				m[r][c] += a[r][k] * b[k][c]
			}
		}
	}
	return
}

mat_translate :: proc(v: Vec3) -> Mat {
	return {{1, 0, 0, v.x}, {0, 1, 0, v.y}, {0, 0, 1, v.z}, {0, 0, 0, 1}}
}

// Turns about the x axis: positive swings something hanging down toward -z, which is forward
// for a character that faces -z.
mat_rotate_x :: proc(a: f32) -> Mat {
	s, c := math.sin(a), math.cos(a)
	return {{1, 0, 0, 0}, {0, c, -s, 0}, {0, s, c, 0}, {0, 0, 0, 1}}
}

// Turns about the vertical axis, in the way a box of the coliseum is turned: x goes to
// (cos, -sin) on the floor and z to (sin, cos).
mat_rotate_y :: proc(a: f32) -> Mat {
	s, c := math.sin(a), math.cos(a)
	return {{c, 0, s, 0}, {0, 1, 0, 0}, {-s, 0, c, 0}, {0, 0, 0, 1}}
}

mat_rotate_z :: proc(a: f32) -> Mat {
	s, c := math.sin(a), math.cos(a)
	return {{c, -s, 0, 0}, {s, c, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}
}

mat_point :: proc(m: Mat, p: Vec3) -> Vec3 {
	return {
		m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z + m[0][3],
		m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z + m[1][3],
		m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z + m[2][3],
	}
}

// A direction: turned, not moved.
mat_dir :: proc(m: Mat, d: Vec3) -> Vec3 {
	return {
		m[0][0] * d.x + m[0][1] * d.y + m[0][2] * d.z,
		m[1][0] * d.x + m[1][1] * d.y + m[1][2] * d.z,
		m[2][0] * d.x + m[2][1] * d.y + m[2][2] * d.z,
	}
}

MAX_SOUP :: 1200 // vertices in one part, three to a triangle

// Triangles with a flat normal each, wound counter-clockwise seen from outside, in the colour
// and glow of the vertex. A mesh with no indices is made of it.
Soup :: struct {
	pos:      [MAX_SOUP]Vec3,
	normal:   [MAX_SOUP]Vec3,
	color:    [MAX_SOUP][4]u8,
	emissive: [MAX_SOUP]f32,
	count:    int, // vertices
}

soup_tri :: proc(s: ^Soup, a, b, c: Vec3, color: [4]u8, emissive: f32 = 0) {
	if s.count + 3 > MAX_SOUP {
		return
	}
	u, v := b - a, c - a
	n := Vec3{u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x}
	length := math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
	if length < 1e-9 {
		return // a sliver that has no face
	}
	n /= length
	for p, i in ([3]Vec3{a, b, c}) {
		s.pos[s.count + i] = p
		s.normal[s.count + i] = n
		s.color[s.count + i] = color
		s.emissive[s.count + i] = emissive
	}
	s.count += 3
}

// A box of the given size, centred on the origin, then moved by `m`.
soup_box :: proc(s: ^Soup, m: Mat, size: Vec3, color: [4]u8, emissive: f32 = 0) {
	h := size * 0.5
	corner :: proc(m: Mat, h: Vec3, sx, sy, sz: f32) -> Vec3 {
		return mat_point(m, {sx * h.x, sy * h.y, sz * h.z})
	}
	// Each face as four corners, going round counter-clockwise from outside.
	faces := [6][4][3]f32{
		{{1, -1, -1}, {1, 1, -1}, {1, 1, 1}, {1, -1, 1}}, // +x
		{{-1, -1, 1}, {-1, 1, 1}, {-1, 1, -1}, {-1, -1, -1}}, // -x
		{{-1, 1, -1}, {-1, 1, 1}, {1, 1, 1}, {1, 1, -1}}, // +y
		{{-1, -1, 1}, {-1, -1, -1}, {1, -1, -1}, {1, -1, 1}}, // -y
		{{-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, {-1, 1, 1}}, // +z
		{{1, -1, -1}, {-1, -1, -1}, {-1, 1, -1}, {1, 1, -1}}, // -z
	}
	for f in faces {
		a := corner(m, h, f[0][0], f[0][1], f[0][2])
		b := corner(m, h, f[1][0], f[1][1], f[1][2])
		c := corner(m, h, f[2][0], f[2][1], f[2][2])
		d := corner(m, h, f[3][0], f[3][1], f[3][2])
		soup_tri(s, a, b, c, color, emissive)
		soup_tri(s, a, c, d, color, emissive)
	}
}

// An ellipsoid with the given radii, centred on `center`, as `segments` slices round and `rings`
// bands from pole to pole, each face flat.
soup_ellipsoid :: proc(s: ^Soup, center, radii: Vec3, segments, rings: int, color: [4]u8, emissive: f32 = 0) {
	point :: proc(center, radii: Vec3, ring, rings, seg, segments: int) -> Vec3 {
		lat := math.PI * (0.5 - f32(ring) / f32(rings)) // from the top pole down
		lon := 2 * math.PI * f32(seg) / f32(segments)
		return {center.x + radii.x * math.cos(lat) * math.cos(lon), center.y + radii.y * math.sin(lat), center.z + radii.z * math.cos(lat) * math.sin(lon)}
	}
	for ring in 0 ..< rings {
		for seg in 0 ..< segments {
			// A growing angle goes round clockwise seen from above, so seen from outside the next slice
			// is to the left. `a` and `b` are the upper corners of a face and `d` and `c` the lower ones,
			// and going a, c, d is counter-clockwise from outside. At a pole two corners are the same
			// point and the face is one triangle.
			a := point(center, radii, ring, rings, seg, segments)
			b := point(center, radii, ring, rings, seg + 1, segments)
			c := point(center, radii, ring + 1, rings, seg + 1, segments)
			d := point(center, radii, ring + 1, rings, seg, segments)
			if ring == 0 {
				soup_tri(s, a, c, d, color, emissive)
			} else if ring == rings - 1 {
				soup_tri(s, a, b, d, color, emissive)
			} else {
				soup_tri(s, a, c, d, color, emissive)
				soup_tri(s, a, b, c, color, emissive)
			}
		}
	}
}

// A cylinder of the given radius and height, standing on the y axis with its middle at the
// origin, closed at both ends, then moved by `m`.
soup_cylinder :: proc(s: ^Soup, m: Mat, radius, height: f32, sides: int, color: [4]u8, emissive: f32 = 0) {
	top, bottom := height * 0.5, -height * 0.5
	ring :: proc(m: Mat, radius, y: f32, i, sides: int) -> Vec3 {
		a := 2 * math.PI * f32(i) / f32(sides)
		return mat_point(m, {radius * math.cos(a), y, radius * math.sin(a)})
	}
	t, b := mat_point(m, {0, top, 0}), mat_point(m, {0, bottom, 0})
	for i in 0 ..< sides {
		a0, a1 := ring(m, radius, top, i, sides), ring(m, radius, top, i + 1, sides)
		b0, b1 := ring(m, radius, bottom, i, sides), ring(m, radius, bottom, i + 1, sides)
		soup_tri(s, a0, a1, b1, color, emissive) // the side, seen from outside
		soup_tri(s, a0, b1, b0, color, emissive)
		soup_tri(s, t, a1, a0, color, emissive) // the top
		soup_tri(s, b, b0, b1, color, emissive) // the bottom
	}
}
