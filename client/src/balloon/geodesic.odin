// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "geodesic.odin"
// ============================================================================

package balloon

import "core:math"

// Builds the closed triangle mesh of a balloon. The mesh is a geodesic sphere:
// an icosahedron whose faces are cut into f * f triangles each and pushed out
// onto the unit sphere. Vertex TIP (0) sits at +Y, so the polar angle of a
// vertex is its angle from the tip.

// Counts for a geodesic sphere of frequency f.
geodesic_vertex_count :: proc(f: int) -> int {
	return 10 * f * f + 2
}

geodesic_edge_count :: proc(f: int) -> int {
	return 30 * f * f
}

geodesic_face_count :: proc(f: int) -> int {
	return 20 * f * f
}

// Writes the unit directions, faces, and edges of a frequency-f geodesic
// sphere into b. Faces wind counter-clockwise seen from outside.
geodesic_build :: proc(b: ^Balloon, f: int) {
	ico: [12]Vec3
	ico[0] = {0, 1, 0}
	ico[11] = {0, -1, 0}
	ring_y := 1 / math.sqrt(f32(5))
	ring_r := 2 / math.sqrt(f32(5))
	for k in 0 ..< 5 {
		a_up := f32(k) * 2 * math.PI / 5
		a_lo := a_up + math.PI / 5
		ico[1 + k] = {ring_r * math.cos(a_up), ring_y, ring_r * math.sin(a_up)}
		ico[6 + k] = {ring_r * math.cos(a_lo), -ring_y, ring_r * math.sin(a_lo)}
	}

	base_faces: [20][3]int
	n := 0
	for k in 0 ..< 5 {
		k1 := (k + 1) % 5
		base_faces[n] = {0, 1 + k, 1 + k1}
		base_faces[n + 1] = {1 + k, 6 + k, 1 + k1}
		base_faces[n + 2] = {1 + k1, 6 + k, 6 + k1}
		base_faces[n + 3] = {11, 6 + k1, 6 + k}
		n += 4
	}
	// Fix the winding so every face points away from the center.
	for &face in base_faces {
		a, c, d := ico[face[0]], ico[face[1]], ico[face[2]]
		if dot3(cross3(c - a, d - a), a + c + d) < 0 {
			face[1], face[2] = face[2], face[1]
		}
	}

	for i in 0 ..< 12 {
		b.unit_dir[i] = ico[i]
	}

	// Each icosahedron edge gets f - 1 shared points, numbered from the lower
	// vertex index to the higher one.
	edge_base: [12][12]int
	for lo in 0 ..< 12 {
		for hi in 0 ..< 12 {
			edge_base[lo][hi] = -1
		}
	}
	count := 12
	for face in base_faces {
		for e in 0 ..< 3 {
			u, v := face[e], face[(e + 1) % 3]
			lo, hi := min(u, v), max(u, v)
			if edge_base[lo][hi] >= 0 {
				continue
			}
			edge_base[lo][hi] = count
			for t in 1 ..< f {
				w := f32(t) / f32(f)
				b.unit_dir[count] = normalize3(ico[lo] * (1 - w) + ico[hi] * w)
				count += 1
			}
		}
	}

	interior := (f - 1) * (f - 2) / 2
	tris := 0
	for face in base_faces {
		pa, pb, pc := face[0], face[1], face[2]
		face_base := count
		count += interior
		for i in 1 ..= f - 2 {
			for j in 1 ..= f - 1 - i {
				p := ico[pa] * f32(f - i - j) + ico[pb] * f32(i) + ico[pc] * f32(j)
				b.unit_dir[geodesic_lattice_id(i, j, f, face, face_base, &edge_base)] = normalize3(p)
			}
		}
		for i in 0 ..< f {
			for j in 0 ..< f - i {
				v00 := geodesic_lattice_id(i, j, f, face, face_base, &edge_base)
				v10 := geodesic_lattice_id(i + 1, j, f, face, face_base, &edge_base)
				v01 := geodesic_lattice_id(i, j + 1, f, face, face_base, &edge_base)
				b.faces[tris] = {u16(v00), u16(v10), u16(v01)}
				tris += 1
				if j + 1 < f - i {
					v11 := geodesic_lattice_id(i + 1, j + 1, f, face, face_base, &edge_base)
					b.faces[tris] = {u16(v10), u16(v11), u16(v01)}
					tris += 1
				}
			}
		}
	}
	b.vert_count = count
	b.face_count = tris
	geodesic_build_edges(b)
	geodesic_order_edges(b)
}

// Vertex index of lattice point (i, j) inside the face whose corners are
// face[0], face[1], face[2]. i counts steps from corner 0 toward corner 1, and
// j counts steps toward corner 2.
geodesic_lattice_id :: proc(i, j, f: int, face: [3]int, face_base: int, edge_base: ^[12][12]int) -> int {
	if i == 0 && j == 0 {
		return face[0]
	}
	if i == f {
		return face[1]
	}
	if j == f {
		return face[2]
	}
	if j == 0 {
		return geodesic_edge_point(face[0], face[1], i, f, edge_base)
	}
	if i == 0 {
		return geodesic_edge_point(face[0], face[2], j, f, edge_base)
	}
	if i + j == f {
		return geodesic_edge_point(face[1], face[2], j, f, edge_base)
	}
	// Interior points are numbered row by row.
	before := (i - 1) * (f - 1) - (i - 1) * i / 2
	return face_base + before + (j - 1)
}

// Point t steps from corner `from` toward corner `to` along an icosahedron edge.
geodesic_edge_point :: proc(from, to, t, f: int, edge_base: ^[12][12]int) -> int {
	lo, hi := min(from, to), max(from, to)
	steps := t if from == lo else f - t
	return edge_base[lo][hi] + steps - 1
}

// Collects each undirected edge once. Every vertex of this mesh has at most
// six neighbors, so a short list per vertex is enough to find duplicates.
geodesic_build_edges :: proc(b: ^Balloon) {
	higher: [MAX_VERTS][MAX_VALENCE]u16
	counts: [MAX_VERTS]int
	b.edge_count = 0
	for fi in 0 ..< b.face_count {
		tri := b.faces[fi]
		for e in 0 ..< 3 {
			u, v := tri[e], tri[(e + 1) % 3]
			lo, hi := min(u, v), max(u, v)
			found := false
			for k in 0 ..< counts[lo] {
				if higher[lo][k] == hi {
					found = true
					break
				}
			}
			if !found {
				higher[lo][counts[lo]] = hi
				counts[lo] += 1
				b.edges[b.edge_count] = {lo, hi}
				b.edge_count += 1
			}
		}
	}
}

// Sorts the edges by color, where no two edges that share a vertex have the
// same color. A solver that visits the edges in list order then does not sweep
// around the sphere. A sweep in one spatial order leaks a little spin into the
// balloon every substep, which shows as a steady twist while it hangs.
geodesic_order_edges :: proc(b: ^Balloon) {
	used: [MAX_VERTS]u32
	color: [MAX_EDGES]u8
	colors := 0
	for e in 0 ..< b.edge_count {
		a, c := b.edges[e][0], b.edges[e][1]
		taken := used[a] | used[c]
		k: u32
		for taken & (1 << k) != 0 {
			k += 1
		}
		color[e] = u8(k)
		used[a] |= 1 << k
		used[c] |= 1 << k
		colors = max(colors, int(k) + 1)
	}
	sorted: [MAX_EDGES][2]u16
	out := 0
	for k in 0 ..< colors {
		for e in 0 ..< b.edge_count {
			if int(color[e]) == k {
				sorted[out] = b.edges[e]
				out += 1
			}
		}
	}
	for e in 0 ..< b.edge_count {
		b.edges[e] = sorted[e]
	}
}

// Moves a unit direction onto the balloon's rest shape: a sphere of
// cfg.radius with a short neck that narrows toward the tip. The azimuth of a
// vertex is kept, only its distance from the axis and its height change.
shape_point :: proc(d: Vec3, cfg: ^Config, ring_angle: f32) -> Vec3 {
	dy := clamp(d.y, -1, 1)
	theta := math.acos(dy)
	horiz := math.sqrt(max(0, 1 - dy * dy))
	hx, hz: f32
	if horiz > 1e-6 {
		hx = d.x / horiz
		hz = d.z / horiz
	}
	t := clamp(theta / cfg.neck_angle, 0, 1)
	s := t * t * (3 - 2 * t)
	// Squaring keeps the neck slim for most of its length before it flares into the body.
	scale := cfg.neck_pinch + (1 - cfg.neck_pinch) * s * s
	// The knot is a small swelling one ring below the very tip.
	k := (theta - ring_angle) / (0.7 * ring_angle)
	bump := 1 + cfg.knot_bulge * math.exp(-k * k)
	rho := cfg.radius * horiz * scale * bump
	y := cfg.radius * (dy + cfg.neck_length * (1 - s))
	return {hx * rho, y, hz * rho}
}

// Angle between the tip and the first ring of vertices around it.
geodesic_ring_angle :: proc(f: int) -> f32 {
	// The icosahedron's edge spans about 63.43 degrees.
	return 1.1071487 / f32(f)
}
