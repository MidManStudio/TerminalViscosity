// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "prop_mesh.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "carry"

GLOVE_COLOR :: [4]u8{70, 150, 215, 255}
SLEEVE_COLOR :: [4]u8{236, 240, 244, 255}

// The meshes of everything in the lab room that is not the room itself: for
// each kind of vessel its glass and the liquid solid inside it, the cap of a
// bottle, and a unit cube in the two colors the hands use. The glass and the
// liquid are drawn with their own shader; the rest use the room's material.
Prop_Meshes :: struct {
	glass:     [carry.KIND_COUNT]rl.Mesh,
	liquids:   [carry.KIND_COUNT]rl.Mesh,
	cap:       rl.Mesh,
	glove:     rl.Mesh,
	sleeve:    rl.Mesh,
	vessel_ok: bool, // false if the vessel shader failed to compile
	vessel:    rl.Material,
	eye_loc:   rl.ShaderLocationIndex,
	mode_loc:  rl.ShaderLocationIndex,
	level_loc: rl.ShaderLocationIndex,
	color_loc: rl.ShaderLocationIndex,
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
		m.glass[k] = mesh_from_shape(s)
		carry.liquid_shape(s, k)
		m.liquids[k] = mesh_from_shape(s)
	}
	carry.cap_shape(s, .Bottle)
	m.cap = mesh_from_shape(s)
	carry.box_build(s, GLOVE_COLOR)
	m.glove = mesh_from_shape(s)
	carry.box_build(s, SLEEVE_COLOR)
	m.sleeve = mesh_from_shape(s)

	shader, ok := load_vessel_shader()
	m.vessel_ok = ok
	if ok {
		m.vessel.shader = shader
		m.vessel.maps = cast([^]rl.MaterialMap)rl_alloc(MAX_MATERIAL_MAPS * size_of(rl.MaterialMap))
		m.vessel.maps[rl.MaterialMapIndex.ALBEDO].color = rl.WHITE
		m.eye_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "eyePos"))
		m.mode_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "liquidMode"))
		m.level_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "levelY"))
		m.color_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "liquidColor"))
	}
}

prop_meshes_unload :: proc(m: ^Prop_Meshes) {
	for k in carry.Kind {
		rl.UnloadMesh(m.glass[k])
		rl.UnloadMesh(m.liquids[k])
	}
	rl.UnloadMesh(m.cap)
	rl.UnloadMesh(m.glove)
	rl.UnloadMesh(m.sleeve)
	if m.vessel_ok {
		rl.UnloadShader(m.vessel.shader)
		rl.MemFree(rawptr(m.vessel.maps))
	}
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

// The caps of the bottles, which are solid and drawn with the room.
props_draw_caps :: proc(m: ^Prop_Meshes, material: rl.Material, props: ^carry.Props) {
	for i in 0 ..< props.count {
		pr := &props.items[i]
		if pr.kind == .Bottle {
			draw_placed(m.cap, material, carry.prop_placed(pr))
		}
	}
}

// The liquid in each vessel, cut off at a flat surface in world space. It is
// drawn solid, before the glass, with back faces on, so the cut shows as the
// surface. Without the vessel shader there is no liquid.
props_draw_liquids :: proc(m: ^Prop_Meshes, props: ^carry.Props, eye: Vec3) {
	if !m.vessel_ok {
		return
	}
	eye_v := eye
	mode := f32(1)
	rl.SetShaderValue(m.vessel.shader, m.eye_loc, &eye_v, .VEC3)
	rl.SetShaderValue(m.vessel.shader, m.mode_loc, &mode, .FLOAT)
	rlgl.DisableBackfaceCulling()
	for i in 0 ..< props.count {
		pr := &props.items[i]
		if pr.ml <= 0 {
			continue
		}
		level := carry.liquid_level(pr)
		color := carry.compound_color(pr.compound)
		rl.SetShaderValue(m.vessel.shader, m.level_loc, &level, .FLOAT)
		rl.SetShaderValue(m.vessel.shader, m.color_loc, &color, .VEC3)
		draw_placed(m.liquids[pr.kind], m.vessel, carry.prop_placed(pr))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
}

// The glass of each vessel, from the farthest to the nearest, blended over what
// is behind it and without writing depth, so glass behind glass still shows.
// If the vessel shader failed, the glass is drawn solid with the room's shader.
props_draw_glass :: proc(m: ^Prop_Meshes, material: rl.Material, props: ^carry.Props, eye: Vec3) {
	order: [carry.MAX_PROPS]int
	count := carry.far_to_near(props, eye, &order)
	if !m.vessel_ok {
		for n in 0 ..< count {
			pr := &props.items[order[n]]
			draw_placed(m.glass[pr.kind], material, carry.prop_placed(pr))
		}
		return
	}
	eye_v := eye
	mode := f32(0)
	rl.SetShaderValue(m.vessel.shader, m.eye_loc, &eye_v, .VEC3)
	rl.SetShaderValue(m.vessel.shader, m.mode_loc, &mode, .FLOAT)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	for n in 0 ..< count {
		pr := &props.items[order[n]]
		draw_placed(m.glass[pr.kind], m.vessel, carry.prop_placed(pr))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
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
