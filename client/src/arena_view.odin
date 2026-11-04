// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "arena_view.odin"
// ============================================================================

package main

import "arena"
import bl "balloon"
import "carry"
import "core:math"
import rl "vendor:raylib"

FLIGHT_SCALE :: f32(3) // thrown balloons are drawn this many times life size, or they are specks across a coliseum
FLIGHT_SPIN :: f32(0.7) // turns a second that the drawing on a balloon in flight goes round
PLAIN_ML :: f32(500) // how full the balloons of other players are drawn, which the snapshot does not say

// The coliseum as one static mesh with a colour for each vertex, built the way the lab's
// room is, but from boxes that may be turned. It is a `Lab_Mesh`, so it is drawn and
// freed with the lab's own procs. A mesh with 16-bit indices holds 2730 boxes.
arena_mesh_init :: proc(m: ^Lab_Mesh, c: ^arena.Coliseum, shader: rl.Shader, lit: bool) {
	verts := c.count * 24
	mesh: rl.Mesh
	mesh.vertexCount = i32(verts)
	mesh.triangleCount = i32(c.count * 12)
	mesh.vertices = cast([^]f32)rl_alloc(verts * 3 * size_of(f32))
	mesh.normals = cast([^]f32)rl_alloc(verts * 3 * size_of(f32))
	mesh.texcoords = cast([^]f32)rl_alloc(verts * 2 * size_of(f32))
	mesh.colors = cast([^]u8)rl_alloc(verts * 4)
	mesh.indices = cast([^]u16)rl_alloc(c.count * 36 * size_of(u16))

	faces := BOX_FACES
	for bi in 0 ..< c.count {
		piece := c.pieces[bi]
		half := piece.size * 0.5
		s, co := math.sin(piece.yaw), math.cos(piece.yaw)
		// Turning a vector about the vertical axis, the same turn `arena.piece_corner` uses.
		turn :: proc(v: Vec3, s, co: f32) -> Vec3 {
			return {v.x * co + v.z * s, v.y, -v.x * s + v.z * co}
		}
		for fi in 0 ..< 6 {
			n, t, b := faces[fi][0], faces[fi][1], faces[fi][2]
			reach_n := abs(n.x) * half.x + abs(n.y) * half.y + abs(n.z) * half.z
			reach_t := abs(t.x) * half.x + abs(t.y) * half.y + abs(t.z) * half.z
			reach_b := abs(b.x) * half.x + abs(b.y) * half.y + abs(b.z) * half.z
			first := (bi * 6 + fi) * 4
			corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
			world_n := turn(n, s, co)
			for ci in 0 ..< 4 {
				local := n * reach_n + t * (corners[ci].x * reach_t) + b * (corners[ci].y * reach_b)
				p := piece.center + turn(local, s, co)
				v := first + ci
				mesh.vertices[v * 3 + 0], mesh.vertices[v * 3 + 1], mesh.vertices[v * 3 + 2] = p.x, p.y, p.z
				mesh.normals[v * 3 + 0], mesh.normals[v * 3 + 1], mesh.normals[v * 3 + 2] = world_n.x, world_n.y, world_n.z
				mesh.texcoords[v * 2 + 0], mesh.texcoords[v * 2 + 1] = piece.emissive, piece.gloss
				mesh.colors[v * 4 + 0], mesh.colors[v * 4 + 1], mesh.colors[v * 4 + 2], mesh.colors[v * 4 + 3] = piece.color.r, piece.color.g, piece.color.b, piece.color.a
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
		m.blast = blast_locs(shader)
	}
}

// The balloons of the match: the one in the player's hand, one body for each slot of the
// loadout to draw its balloons in flight with, and a plain one for everybody else's. Only
// the one in the hand is simulated. The others are posed once, hanging, and drawn
// wherever the match says a balloon is, which is the arena's idea of a balloon in flight.
Arena_View :: struct {
	hand:        Balloon_Body,
	flight:      [carry.LOADOUT_SLOTS]Balloon_Body,
	plain:       Balloon_Body, // owns the shader
	centre:      [carry.LOADOUT_SLOTS + 1]f32, // how far below its tip the middle of each body is, in its own units
	filled:      [carry.LOADOUT_SLOTS]f32, // the fill each flight body was posed for, or -1
	hand_slot:   int, // the slot the hand body was made ready for, or -1
	hand_fill:   f32,
	hand_on:     bool,
	hand_origin: Vec3, // where the hand body hung last frame
	hand_turn:   f32, // how far the drawing is turned so that its middle faces the player
	scratch:     []u8, // room to turn a drawing into pixels in
	time:        f32,
}

// How far below its tip the middle of a hanging balloon is, in the units of its body.
body_centre :: proc(b: ^Balloon_Body) -> f32 {
	lo, hi := bl.bounds(b.balloon)
	return (lo.y + hi.y) * 0.5
}

arena_view_init :: proc(av: ^Arena_View, shader: rl.Shader, lit: bool) {
	body_init(&av.plain, shader, lit, false, 40)
	body_init(&av.hand, shader, lit, true, 400) // a hand moves faster than a clamp, so the neck follows faster
	for &b in av.flight {
		body_init(&b, shader, lit, true, 40)
	}
	body_reset(&av.plain, PLAIN_ML / carry.BALLOON_REST_ML)
	av.centre[carry.LOADOUT_SLOTS] = body_centre(&av.plain)
	for &f in av.filled {
		f = -1
	}
	av.hand_slot = -1
	av.scratch = art_scratch_alloc()
}

// The shader belongs to the plain body, so it goes last.
arena_view_unload :: proc(av: ^Arena_View) {
	body_unload(&av.hand)
	for &b in av.flight {
		body_unload(&b)
	}
	body_unload(&av.plain)
	art_scratch_free(av.scratch)
	av^ = {}
}

// Where the player's eyes are and which way they face, as the carry package wants it.
view_basis :: proc(eye: Vec3, look: arena.Look) -> carry.View {
	forward := arena.look_dir(look)
	right := linalg_normalize(linalg_cross(forward, {0, 1, 0}))
	return {eye = eye, right = right, up = linalg_cross(right, forward), back = -forward}
}

// Poses each balloon the loadout holds when it arrives or changes, and runs the one in the
// hand, which swings from the hand as the lab's does.
arena_view_update :: proc(av: ^Arena_View, slots: ^[carry.LOADOUT_SLOTS]arena.Slot, selected: int, store: ^carry.Art_Store, v: carry.View, dt: f32) {
	av.time += dt
	for i in 0 ..< carry.LOADOUT_SLOTS {
		s := slots[i]
		if !s.used {
			av.filled[i] = -1
			continue
		}
		ratio := f32(s.ml) / carry.BALLOON_REST_ML
		if av.filled[i] != ratio {
			body_reset(&av.flight[i], ratio)
			av.filled[i] = ratio
			av.centre[i] = body_centre(&av.flight[i])
		}
		body_art(&av.flight[i], store, s.art, av.scratch)
	}

	if !arena.slot_usable(slots, selected) {
		av.hand_on = false
		av.hand_slot = -1
		return
	}
	s := slots[selected]
	ratio := f32(s.ml) / carry.BALLOON_REST_ML
	if av.hand_slot != selected || av.hand_fill != ratio {
		av.hand_slot, av.hand_fill = selected, ratio
		av.hand_on = false
	}
	origin := hand_origin(v)
	moved := av.hand_on ? origin - av.hand_origin : Vec3{}
	if moved.x * moved.x + moved.y * moved.y + moved.z * moved.z > 0.36 { // 0.6 m in a frame is a jump
		moved = {}
		av.hand_on = false
	}
	if !av.hand_on {
		av.hand_on = true
		body_reset(&av.hand, ratio)
	}
	body_step(&av.hand, ratio, 0, dt, moved)
	body_art(&av.hand, store, s.art, av.scratch)
	av.hand_origin = origin
	// The balloon in the hand does not turn with the player, so its drawing is turned to face them.
	av.hand_turn = carry.facing_turn(v.back.x, v.back.z)
}

// Draws one balloon of a body at `middle`, `FLIGHT_SCALE` times life size.
flight_draw :: proc(b: ^Balloon_Body, centre_y: f32, middle, eye, tint: Vec3) {
	s := b.scale * FLIGHT_SCALE
	origin := middle - Vec3{0, centre_y * s, 0}
	local_eye := (eye - origin) / s
	m := rl.Matrix(1)
	m[0, 0], m[1, 1], m[2, 2] = s, s, s
	m[0, 3], m[1, 3], m[2, 3] = origin.x, origin.y, origin.z
	view_draw_at(&b.view, local_eye, bl.normalize3(LIGHT_DIR), tint, m)
}

// Draws the balloon in the hand, if there is one and it is wanted, and every balloon in
// flight. The player's own wear their drawings, as the slots they came from do.
arena_view_draw :: proc(av: ^Arena_View, v: ^arena.Match_View, slots: ^[carry.LOADOUT_SLOTS]arena.Slot, selected: int, local: u8, eye: Vec3, show_hand: bool) {
	if show_hand && av.hand_on && arena.slot_usable(slots, selected) {
		s := slots[selected]
		av.hand.view.art_turn = av.hand_turn
		body_draw(&av.hand, av.hand_origin, eye, balloon_tint(s.compound, f32(s.ml)))
	}
	for i in 0 ..< v.balloon_count {
		f := v.balloons[i]
		own := f.owner == local && int(f.slot) < carry.LOADOUT_SLOTS && slots[f.slot].used
		body := own ? &av.flight[f.slot] : &av.plain
		centre := own ? av.centre[f.slot] : av.centre[carry.LOADOUT_SLOTS]
		ml := own ? f32(slots[f.slot].ml) : PLAIN_ML
		body.view.art_turn = math.mod(av.time * FLIGHT_SPIN + f32(f.id) * 0.37, 1)
		flight_draw(body, centre, f.pos, eye, balloon_tint(f.compound, ml))
	}
}
