// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "character_view.odin"
// ============================================================================

package main

import "arena"
import "character"
import "core:math"
import rl "vendor:raylib"

CHARACTER_GLOSS :: f32(0.05)

// The other players of the match, drawn as the temporary character: one set of meshes for each
// player, built the first time they are seen in the colours of their id, and one animation each
// that follows how fast they move, whether they are in the air, and whether they have just thrown.
// The local player is not drawn, because the camera is in their head.
Character_Pool :: struct {
	built:    [arena.MAX_PLAYERS]bool,
	meshes:   [arena.MAX_PLAYERS][character.Part]rl.Mesh,
	anim:     [arena.MAX_PLAYERS]character.Anim,
	last_pos: [arena.MAX_PLAYERS]Vec3,
	seen:     [arena.MAX_PLAYERS]bool,
	prev:     arena.Match_View, // the match of the frame before, to see who has thrown
}

character_pool_init :: proc(pool: ^Character_Pool) {
	for &a in pool.anim {
		a = character.anim_new()
	}
}

// Makes one mesh of triangles with no indices from a part's soup: positions and normals, the
// vertex colour, and the glow and sheen in the texture coordinates, as the coliseum's mesh does.
character_mesh :: proc(s: ^character.Soup) -> rl.Mesh {
	n := s.count
	mesh: rl.Mesh
	mesh.vertexCount = i32(n)
	mesh.triangleCount = i32(n / 3)
	mesh.vertices = cast([^]f32)rl_alloc(n * 3 * size_of(f32))
	mesh.normals = cast([^]f32)rl_alloc(n * 3 * size_of(f32))
	mesh.texcoords = cast([^]f32)rl_alloc(n * 2 * size_of(f32))
	mesh.colors = cast([^]u8)rl_alloc(n * 4)
	for i in 0 ..< n {
		p, nm, c := s.pos[i], s.normal[i], s.color[i]
		mesh.vertices[i * 3 + 0], mesh.vertices[i * 3 + 1], mesh.vertices[i * 3 + 2] = p.x, p.y, p.z
		mesh.normals[i * 3 + 0], mesh.normals[i * 3 + 1], mesh.normals[i * 3 + 2] = nm.x, nm.y, nm.z
		mesh.texcoords[i * 2 + 0], mesh.texcoords[i * 2 + 1] = s.emissive[i], CHARACTER_GLOSS
		mesh.colors[i * 4 + 0], mesh.colors[i * 4 + 1], mesh.colors[i * 4 + 2], mesh.colors[i * 4 + 3] = c.r, c.g, c.b, c.a
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

character_build :: proc(pool: ^Character_Pool, id: int) {
	model := new(character.Model)
	defer free(model)
	character.model_build(model, character.palette_for(u8(id)))
	for part in character.Part {
		pool.meshes[id][part] = character_mesh(&model.parts[part])
	}
	pool.built[id] = true
}

character_pool_unload :: proc(pool: ^Character_Pool) {
	for id in 0 ..< arena.MAX_PLAYERS {
		if pool.built[id] {
			for part in character.Part {
				rl.UnloadMesh(pool.meshes[id][part])
			}
		}
	}
	pool^ = {}
}

// Moves the animations on by `dt` for the players in `view`: how fast each moved since the frame
// before, whether they are in the air, and whether a balloon of theirs has just appeared.
character_pool_update :: proc(pool: ^Character_Pool, view: ^arena.Match_View, local: u8, dt: f32) {
	for i in 0 ..< view.player_count {
		p := view.players[i]
		id := int(p.id) % arena.MAX_PLAYERS
		if p.id == local {
			continue
		}
		speed: f32
		if pool.seen[id] && dt > 0 {
			dx, dz := p.pos.x - pool.last_pos[id].x, p.pos.z - pool.last_pos[id].z
			speed = math.sqrt(dx * dx + dz * dz) / dt
		}
		pool.seen[id] = true
		pool.last_pos[id] = p.pos
		if arena.thrown_by(&pool.prev, view, p.id) {
			character.anim_throw(&pool.anim[id])
		}
		character.anim_step(&pool.anim[id], speed, !arena.on_floor(p), dt)
	}
	pool.prev = view^
}

// raylib's matrix, filled from the character package's.
rl_matrix :: proc(m: character.Mat) -> (out: rl.Matrix) {
	for r in 0 ..< 4 {
		for c in 0 ..< 4 {
			out[r, c] = m[r][c]
		}
	}
	return
}

// Draws every player but the local one, with the material (and so the shader) of the coliseum.
character_pool_draw :: proc(pool: ^Character_Pool, view: ^arena.Match_View, local: u8, material: rl.Material) {
	for i in 0 ..< view.player_count {
		p := view.players[i]
		if p.id == local {
			continue
		}
		id := int(p.id) % arena.MAX_PLAYERS
		if !pool.built[id] {
			character_build(pool, id)
		}
		root := character.root_matrix(p.pos, p.yaw)
		pose := character.anim_pose(&pool.anim[id])
		for part in character.Part {
			rl.DrawMesh(pool.meshes[id][part], material, rl_matrix(character.part_matrix(root, pose, part)))
		}
	}
}
