// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon_view.odin"
// ============================================================================

package main

import "core:math"
import "core:mem"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import bl "balloon"

// raylib reads this many maps per material.
MAX_MATERIAL_MAPS :: 12

// Index of each vertex buffer in a raylib mesh.
BUFFER_POSITION :: 0
BUFFER_NORMAL :: 2

// The knot is a small lathe mesh: KNOT_SEGMENTS vertices around, one ring for
// each point of the profile. Each point is (distance from the axis, height) in
// balloon radii, from the stem inside the neck up to the end of the tail.
KNOT_SEGMENTS :: 10
KNOT_PROFILE :: [?][2]f32{{0.11, -0.30}, {0.09, -0.18}, {0.15, -0.08}, {0.17, 0.00}, {0.13, 0.07}, {0.06, 0.11}, {0.08, 0.17}, {0.07, 0.24}, {0.0, 0.28}}
KNOT_TAIL_END :: f32(0.28) // height of the end of the tail in the knot's own shape
KNOT_OVERHANG :: f32(0.17) // how far the end of the tail reaches past the tip vertex, in radii
KNOT_RINGS :: len(KNOT_PROFILE)
KNOT_VERTS :: KNOT_RINGS * KNOT_SEGMENTS
KNOT_TRIS :: (KNOT_RINGS - 1) * KNOT_SEGMENTS * 2

// The balloon on the GPU: one dynamic mesh that is rewritten every frame, and
// the material that draws it.
Balloon_View :: struct {
	knot_mesh:   rl.Mesh,
	knot_local:  [KNOT_VERTS][3]f32, // the knot's shape around the origin, before it is placed
	knot_normal: [KNOT_VERTS][3]f32,
	mesh:      rl.Mesh,
	material:  rl.Material,
	lit:       bool, // false when the balloon shader failed to compile
	eye_loc:   rl.ShaderLocationIndex,
	light_loc: rl.ShaderLocationIndex,
	tint_loc:  rl.ShaderLocationIndex,
	back_loc:  rl.ShaderLocationIndex,
	strain_loc: rl.ShaderLocationIndex,
	strain:    f32, // 0 for a slack balloon, 1 at the point where it bursts, for the shader
	hide_knot: bool, // a balloon held open by its neck has no knot yet
	shares_shader: bool, // the shader belongs to another view, which unloads it
}

// Mesh and material memory comes from raylib's allocator, because UnloadMesh
// frees it with raylib's free.
rl_alloc :: proc(bytes: int) -> rawptr {
	p := rl.MemAlloc(u32(bytes))
	mem.zero(p, bytes)
	return p
}

// Builds the mesh for `b` and uploads it as dynamic. `shader` draws it when
// `lit` is true. Otherwise raylib's flat default shader does.
view_init :: proc(v: ^Balloon_View, b: ^bl.Balloon, shader: rl.Shader, lit: bool) {
	n := b.vert_count
	mesh: rl.Mesh
	mesh.vertexCount = i32(n)
	mesh.triangleCount = i32(b.face_count)
	mesh.vertices = cast([^]f32)rl_alloc(n * 3 * size_of(f32))
	mesh.normals = cast([^]f32)rl_alloc(n * 3 * size_of(f32))
	mesh.texcoords = cast([^]f32)rl_alloc(n * 2 * size_of(f32))
	mesh.indices = cast([^]u16)rl_alloc(b.face_count * 3 * size_of(u16))
	for i in 0 ..< n {
		// The shader reads how much of the knot a vertex is from the first texture coordinate.
		mesh.texcoords[i * 2] = b.knot[i]
		mesh.texcoords[i * 2 + 1] = 0
	}
	for f in 0 ..< b.face_count {
		for k in 0 ..< 3 {
			mesh.indices[f * 3 + k] = b.faces[f][k]
		}
	}
	v.mesh = mesh
	view_copy(v, b)
	rl.UploadMesh(&v.mesh, true)

	knot_init(v)

	v.material.shader = shader
	v.material.maps = cast([^]rl.MaterialMap)rl_alloc(MAX_MATERIAL_MAPS * size_of(rl.MaterialMap))
	v.material.maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
	v.lit = lit
	if lit {
		v.eye_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "eyePos"))
		v.light_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "lightDir"))
		v.tint_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "tint"))
		v.back_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "backFace"))
		v.strain_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "strain"))
	}
}

// Builds the knot's shape and its mesh. The mesh is rewritten every frame to
// follow the tip, like the balloon's own.
knot_init :: proc(v: ^Balloon_View) {
	profile := KNOT_PROFILE
	for i in 0 ..< KNOT_RINGS {
		// Outward direction in the (distance, height) plane, averaged from the
		// segments on either side of the point.
		lo, hi := max(i - 1, 0), min(i + 1, KNOT_RINGS - 1)
		dr := profile[hi][0] - profile[lo][0]
		dy := profile[hi][1] - profile[lo][1]
		len := math.sqrt(dr * dr + dy * dy)
		nr, ny := dy / len, -dr / len
		for k in 0 ..< KNOT_SEGMENTS {
			a := f32(k) / f32(KNOT_SEGMENTS) * math.TAU
			c, s := math.cos(a), math.sin(a)
			v.knot_local[i * KNOT_SEGMENTS + k] = {profile[i][0] * c, profile[i][1], profile[i][0] * s}
			v.knot_normal[i * KNOT_SEGMENTS + k] = {nr * c, ny, nr * s}
		}
	}
	mesh: rl.Mesh
	mesh.vertexCount = KNOT_VERTS
	mesh.triangleCount = KNOT_TRIS
	mesh.vertices = cast([^]f32)rl_alloc(KNOT_VERTS * 3 * size_of(f32))
	mesh.normals = cast([^]f32)rl_alloc(KNOT_VERTS * 3 * size_of(f32))
	mesh.texcoords = cast([^]f32)rl_alloc(KNOT_VERTS * 2 * size_of(f32))
	mesh.indices = cast([^]u16)rl_alloc(KNOT_TRIS * 3 * size_of(u16))
	for i in 0 ..< KNOT_VERTS {
		mesh.texcoords[i * 2] = 1 // all knot, so the shader draws it as opaque rubber
	}
	tri := 0
	for i in 0 ..< KNOT_RINGS - 1 {
		for k in 0 ..< KNOT_SEGMENTS {
			a := u16(i * KNOT_SEGMENTS + k)
			b := u16(i * KNOT_SEGMENTS + (k + 1) % KNOT_SEGMENTS)
			d := a + KNOT_SEGMENTS
			c := b + KNOT_SEGMENTS
			mesh.indices[tri * 3 + 0], mesh.indices[tri * 3 + 1], mesh.indices[tri * 3 + 2] = a, d, c
			mesh.indices[tri * 3 + 3], mesh.indices[tri * 3 + 4], mesh.indices[tri * 3 + 5] = a, c, b
			tri += 2
		}
	}
	v.knot_mesh = mesh
	knot_place(v, {0, 0, 0}, {0, 1, 0}, {1, 0, 0}, 1)
	rl.UploadMesh(&v.knot_mesh, true)
}

// Puts the knot on the tip vertex, pointing along `axis`, scaled by `size`.
// The bulb sits on the vertex and the tail reaches past it, so the knot stands
// out from the narrow neck instead of sinking into it.
knot_place :: proc(v: ^Balloon_View, apex, axis, side: Vec3, size: f32) {
	third := bl.cross3(axis, side)
	origin := apex + axis * ((KNOT_OVERHANG - KNOT_TAIL_END) * size)
	for i in 0 ..< KNOT_VERTS {
		p := v.knot_local[i]
		n := v.knot_normal[i]
		pos := origin + (side * p.x + axis * p.y + third * p.z) * size
		nrm := side * n.x + axis * n.y + third * n.z
		v.knot_mesh.vertices[i * 3 + 0], v.knot_mesh.vertices[i * 3 + 1], v.knot_mesh.vertices[i * 3 + 2] = pos.x, pos.y, pos.z
		v.knot_mesh.normals[i * 3 + 0], v.knot_mesh.normals[i * 3 + 1], v.knot_mesh.normals[i * 3 + 2] = nrm.x, nrm.y, nrm.z
	}
}

// Copies the current positions and normals into the CPU side of the mesh.
view_copy :: proc(v: ^Balloon_View, b: ^bl.Balloon) {
	n := b.vert_count
	mem.copy(rawptr(v.mesh.vertices), &b.pos[0], n * size_of([3]f32))
	mem.copy(rawptr(v.mesh.normals), &b.normal[0], n * size_of([3]f32))
}

// Sends the balloon's current shape to the GPU.
view_update :: proc(v: ^Balloon_View, b: ^bl.Balloon) {
	view_copy(v, b)
	bytes := i32(b.vert_count * size_of([3]f32))
	rl.UpdateMeshBuffer(v.mesh, BUFFER_POSITION, rawptr(v.mesh.vertices), bytes, 0)
	rl.UpdateMeshBuffer(v.mesh, BUFFER_NORMAL, rawptr(v.mesh.normals), bytes, 0)

	apex, axis, side := bl.tip_frame(b)
	knot_place(v, apex, axis, side, b.cfg.radius)
	knot_bytes := i32(KNOT_VERTS * size_of([3]f32))
	rl.UpdateMeshBuffer(v.knot_mesh, BUFFER_POSITION, rawptr(v.knot_mesh.vertices), knot_bytes, 0)
	rl.UpdateMeshBuffer(v.knot_mesh, BUFFER_NORMAL, rawptr(v.knot_mesh.normals), knot_bytes, 0)
}

// Draws the balloon in two passes, inside first and outside second, so the far
// wall shows faintly through the near one without any sorting.
view_draw :: proc(v: ^Balloon_View, eye: Vec3, light: Vec3, tint: Vec3) {
	view_draw_at(v, eye, light, tint, rl.Matrix(1))
}

// The same, with the balloon moved and scaled by `model`. The shader works in the
// balloon's own space, so `eye` must be given in that space too: the eye minus the
// move, over the scale. A balloon that is held open has no knot, and a stretched
// one is drawn thin and pale by the amount of `strain`.
view_draw_at :: proc(v: ^Balloon_View, eye: Vec3, light: Vec3, tint: Vec3, model: rl.Matrix) {
	// Anything queued before this, such as the floor, must land first.
	rlgl.DrawRenderBatchActive()
	placement := model
	eye_v, light_v, tint_v := eye, light, tint
	if v.lit {
		strain := v.strain
		rl.SetShaderValue(v.material.shader, v.strain_loc, &strain, .FLOAT)
		rl.SetShaderValue(v.material.shader, v.eye_loc, &eye_v, .VEC3)
		rl.SetShaderValue(v.material.shader, v.light_loc, &light_v, .VEC3)
		rl.SetShaderValue(v.material.shader, v.tint_loc, &tint_v, .VEC3)
	} else {
		v.material.maps[rl.MaterialMapIndex.ALBEDO].color = {u8(tint.x * 255), u8(tint.y * 255), u8(tint.z * 255), 255}
	}
	rlgl.EnableBackfaceCulling()
	// The knot is opaque, so it goes first and hides what is behind it.
	rlgl.SetCullFace(.BACK)
	if v.lit {
		back := f32(0)
		rl.SetShaderValue(v.material.shader, v.back_loc, &back, .FLOAT)
	}
	if !v.hide_knot {
		rl.DrawMesh(v.knot_mesh, v.material, placement)
	}
	if v.lit {
		back := f32(1)
		rl.SetShaderValue(v.material.shader, v.back_loc, &back, .FLOAT)
		rlgl.SetCullFace(.FRONT)
		rl.DrawMesh(v.mesh, v.material, placement)
		back = 0
		rl.SetShaderValue(v.material.shader, v.back_loc, &back, .FLOAT)
	}
	rlgl.SetCullFace(.BACK)
	rl.DrawMesh(v.mesh, v.material, placement)
	rlgl.DrawRenderBatchActive()
}

view_unload :: proc(v: ^Balloon_View) {
	rl.UnloadMesh(v.mesh)
	rl.UnloadMesh(v.knot_mesh)
	if v.lit && !v.shares_shader {
		rl.UnloadShader(v.material.shader)
	}
	rl.MemFree(rawptr(v.material.maps))
	v^ = {}
}
