// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "prop_mesh.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import "carry"

GLOVE_COLOR :: [4]u8{70, 150, 215, 255}
SLEEVE_COLOR :: [4]u8{236, 240, 244, 255}

// The meshes of everything in the lab room that is not the room itself: one
// for each kind of vessel, and a unit cube in the two colors the hands use.
// They are all drawn with the room's own material.
Prop_Meshes :: struct {
	vessels: [carry.KIND_COUNT]rl.Mesh,
	glove:   rl.Mesh,
	sleeve:  rl.Mesh,
}

// Copies a shape into a raylib mesh and uploads it. The texture coordinate
// carries glow (x) and gloss (y) to the lab shader, as in the room mesh.
mesh_from_shape :: proc(s: ^carry.Shape) -> rl.Mesh {
	n := s.vert_count
	mesh: rl.Mesh
	mesh.vertexCount = i32(n)
	mesh.triangleCount = i32(s.index_count / 3)
	mesh.vertices = cast([^]f32)rl_alloc(n * 3 * size_of(f32))
	mesh.normals = cast([^]f32)rl_alloc(n * 3 * size_of(f32))
	mesh.texcoords = cast([^]f32)rl_alloc(n * 2 * size_of(f32))
	mesh.colors = cast([^]u8)rl_alloc(n * 4)
	mesh.indices = cast([^]u16)rl_alloc(s.index_count * size_of(u16))
	for i in 0 ..< n {
		p, q, c := s.positions[i], s.normals[i], s.colors[i]
		mesh.vertices[i * 3 + 0], mesh.vertices[i * 3 + 1], mesh.vertices[i * 3 + 2] = p.x, p.y, p.z
		mesh.normals[i * 3 + 0], mesh.normals[i * 3 + 1], mesh.normals[i * 3 + 2] = q.x, q.y, q.z
		mesh.texcoords[i * 2 + 0], mesh.texcoords[i * 2 + 1] = 0, s.gloss
		mesh.colors[i * 4 + 0], mesh.colors[i * 4 + 1], mesh.colors[i * 4 + 2], mesh.colors[i * 4 + 3] = c.r, c.g, c.b, c.a
	}
	for i in 0 ..< s.index_count {
		mesh.indices[i] = s.indices[i]
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

prop_meshes_init :: proc(m: ^Prop_Meshes) {
	s := new(carry.Shape)
	defer free(s)
	for k in carry.Kind {
		carry.vessel_shape(s, k)
		m.vessels[k] = mesh_from_shape(s)
	}
	carry.box_build(s, GLOVE_COLOR)
	m.glove = mesh_from_shape(s)
	carry.box_build(s, SLEEVE_COLOR)
	m.sleeve = mesh_from_shape(s)
}

prop_meshes_unload :: proc(m: ^Prop_Meshes) {
	for k in carry.Kind {
		rl.UnloadMesh(m.vessels[k])
	}
	rl.UnloadMesh(m.glove)
	rl.UnloadMesh(m.sleeve)
	m^ = {}
}

// Draws a mesh at a placed frame. The matrix is built by hand, because raylib's
// matrix helpers return a struct, which is not safe to call from Odin on
// Android (see docs/ANDROID.md). Raylib's matrices are row-major here, with
// the move in the last column.
draw_placed :: proc(mesh: rl.Mesh, material: rl.Material, p: carry.Placed) {
	m := rl.Matrix(1)
	for c in 0 ..< 3 {
		for r in 0 ..< 3 {
			m[r, c] = p.axes[c][r]
		}
	}
	m[0, 3], m[1, 3], m[2, 3] = p.origin.x, p.origin.y, p.origin.z
	rl.DrawMesh(mesh, material, m)
}

props_draw :: proc(m: ^Prop_Meshes, material: rl.Material, props: ^carry.Props) {
	for i in 0 ..< props.count {
		pr := &props.items[i]
		draw_placed(m.vessels[pr.kind], material, carry.prop_placed(pr))
	}
}

// Draws the parts of both hands, as placed by carry.hands_place.
hands_draw :: proc(m: ^Prop_Meshes, material: rl.Material, placed: []carry.Placed) {
	for p in placed {
		mesh := m.glove
		if p.tone == .Sleeve {
			mesh = m.sleeve
		}
		draw_placed(mesh, material, p)
	}
}
