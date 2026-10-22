// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "lab_mesh.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "lab"

// The whole room as one static mesh, with a color for each vertex, so it is
// drawn with a single call.
Lab_Mesh :: struct {
	mesh:     rl.Mesh,
	material: rl.Material,
	lit:      bool, // false when the lab shader failed to compile
	eye_loc:  rl.ShaderLocationIndex,
}

// For each face of a box: its outward normal and two tangents that turn
// toward each other the right way round, so the corners come out
// counter-clockwise seen from outside.
BOX_FACES :: [6][3]lab.Vec3 {
	{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
	{{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
	{{0, 1, 0}, {0, 0, 1}, {1, 0, 0}},
	{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
	{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
	{{0, 0, -1}, {0, 1, 0}, {1, 0, 0}},
}

lab_mesh_init :: proc(m: ^Lab_Mesh, l: ^lab.Layout, shader: rl.Shader, lit: bool) {
	verts := l.box_count * 24
	mesh: rl.Mesh
	mesh.vertexCount = i32(verts)
	mesh.triangleCount = i32(l.box_count * 12)
	mesh.vertices = cast([^]f32)rl_alloc(verts * 3 * size_of(f32))
	mesh.normals = cast([^]f32)rl_alloc(verts * 3 * size_of(f32))
	mesh.texcoords = cast([^]f32)rl_alloc(verts * 2 * size_of(f32))
	mesh.colors = cast([^]u8)rl_alloc(verts * 4)
	mesh.indices = cast([^]u16)rl_alloc(l.box_count * 36 * size_of(u16))

	faces := BOX_FACES
	for bi in 0 ..< l.box_count {
		box := l.boxes[bi]
		half := box.size * 0.5
		for fi in 0 ..< 6 {
			n, t, b := faces[fi][0], faces[fi][1], faces[fi][2]
			// How far each direction reaches: the box's half size along that axis.
			reach_n := abs(n.x) * half.x + abs(n.y) * half.y + abs(n.z) * half.z
			reach_t := abs(t.x) * half.x + abs(t.y) * half.y + abs(t.z) * half.z
			reach_b := abs(b.x) * half.x + abs(b.y) * half.y + abs(b.z) * half.z
			first := (bi * 6 + fi) * 4
			corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
			for ci in 0 ..< 4 {
				p := box.center + n * reach_n + t * (corners[ci].x * reach_t) + b * (corners[ci].y * reach_b)
				v := first + ci
				mesh.vertices[v * 3 + 0], mesh.vertices[v * 3 + 1], mesh.vertices[v * 3 + 2] = p.x, p.y, p.z
				mesh.normals[v * 3 + 0], mesh.normals[v * 3 + 1], mesh.normals[v * 3 + 2] = n.x, n.y, n.z
				mesh.texcoords[v * 2 + 0], mesh.texcoords[v * 2 + 1] = box.emissive, box.gloss
				mesh.colors[v * 4 + 0], mesh.colors[v * 4 + 1], mesh.colors[v * 4 + 2], mesh.colors[v * 4 + 3] = box.color.r, box.color.g, box.color.b, box.color.a
			}
			at := (bi * 6 + fi) * 6
			base := u16(first)
			mesh.indices[at + 0], mesh.indices[at + 1], mesh.indices[at + 2] = base, base + 1, base + 2
			mesh.indices[at + 3], mesh.indices[at + 4], mesh.indices[at + 5] = base, base + 2, base + 3
		}
	}
	m.mesh = mesh
	rl.UploadMesh(&m.mesh, false)

	m.material.shader = shader
	m.material.maps = cast([^]rl.MaterialMap)rl_alloc(MAX_MATERIAL_MAPS * size_of(rl.MaterialMap))
	m.material.maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
	m.lit = lit
	if lit {
		m.eye_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "eyePos"))
	}
}

lab_mesh_draw :: proc(m: ^Lab_Mesh, eye: Vec3) {
	eye_v := eye
	if m.lit {
		rl.SetShaderValue(m.material.shader, m.eye_loc, &eye_v, .VEC3)
	}
	rlgl.EnableBackfaceCulling()
	rl.DrawMesh(m.mesh, m.material, rl.Matrix(1))
	rlgl.DrawRenderBatchActive()
}

lab_mesh_unload :: proc(m: ^Lab_Mesh) {
	rl.UnloadMesh(m.mesh)
	if m.lit {
		rl.UnloadShader(m.material.shader)
	}
	rl.MemFree(rawptr(m.material.maps))
	m^ = {}
}
