// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene_room.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "carry"
import "chem"
import "core:fmt"
import "lab"

LOOK_SPEED :: f32(0.0045) // radians of turn for each pixel dragged
ROOM_FOV :: f32(70)
FOG_COLOR :: rl.Color{204, 214, 224, 255}

// The chemistry lab, walked around in first person: a large open room with
// long counters along the walls and one in the middle, and vessels on the
// middle one that can be picked up and carried.
Room :: struct {
	layout:   lab.Layout,
	player:   lab.Player,
	mesh:     Lab_Mesh,
	controls: Controls,
	props:    carry.Props,
	hands:    carry.Hands,
	meshes:   Prop_Meshes,
	health:   carry.Health,
	mix_target: int, // the vessel the held one is over, or -1
	blast_flash: f32, // how white the screen is from a blast, fading
	toast:    [96]u8, // what the last mix did, as text
	toast_timer: f32,
}

// Shows a line of text for a few seconds. It is formatted into the room's own
// buffer, so nothing is allocated.
room_toast :: proc(room: ^Room, format: string, args: ..any) {
	line := fmt.bprintf(room.toast[:len(room.toast) - 1], format, ..args)
	room.toast[len(line)] = 0
	room.toast_timer = 3.5
}

// Puts the player, the vessels, and the health back as they were at the start.
room_reset :: proc(room: ^Room) {
	lab.player_init(&room.player, &room.layout)
	carry.props_init(&room.props)
	carry.props_place_defaults(&room.props, &room.layout)
	carry.health_init(&room.health)
	room.mix_target = -1
}

// One press of the mix button: pours the held vessel into the one under it,
// shows what came of it, and takes the damage.
room_mix :: proc(room: ^Room) {
	eye := carry.view_of(&room.player).eye
	held := room.props.held
	r := carry.mix(&room.props, eye)
	a, b, product := chem.compound_name(r.a), chem.compound_name(r.b), chem.compound_name(r.product)
	switch r.kind {
	case .Nothing:
		if held == -1 {
			room_toast(room, "pick up a vessel to pour")
		} else {
			room_toast(room, "hold it over another vessel to pour")
		}
	case .Poured:
		room_toast(room, "poured %v ml of %v", int(r.ml + 0.5), b)
	case .Mixed:
		room_toast(room, "%v + %v made %v", a, b, product)
	case .Spatter:
		room.blast_flash = 0.4
		room_toast(room, "SPATTER! %v + %v made %v", a, b, product)
	case .Blast:
		room.blast_flash = 1
		room_toast(room, "BLAST! %v + %v", a, b)
	}
	carry.health_hurt(&room.health, r.damage)
}

room_load :: proc(game: ^Game) -> rawptr {
	room := new(Room)
	lab.build(&room.layout)
	lab.player_init(&room.player, &room.layout)
	shader, ok := load_lab_shader()
	lab_mesh_init(&room.mesh, &room.layout, shader, ok)
	carry.props_init(&room.props)
	carry.props_place_defaults(&room.props, &room.layout)
	prop_meshes_init(&room.meshes)
	carry.health_init(&room.health)
	room.mix_target = -1
	pointers: Pointers
	platform_pointers(&pointers)
	controls_init(&room.controls, &pointers)
	// Up close the near plane has to be small, and the room is small enough
	// that the far plane can stay close, which keeps a 16-bit depth buffer accurate.
	rlgl.SetClipPlanes(0.08, 70)
	return room
}

room_unload :: proc(game: ^Game, state: rawptr) {
	room := cast(^Room)state
	rlgl.SetClipPlanes(0.05, 4000)
	prop_meshes_unload(&room.meshes)
	lab_mesh_unload(&room.mesh)
	free(room)
}

room_update :: proc(game: ^Game, state: rawptr, dt: f32) {
	room := cast(^Room)state
	w, h := f32(game.screen_w), f32(game.screen_h)

	pointers: Pointers
	platform_pointers(&pointers)
	buttons := [5][4]f32{switch_button(w, h), grab_button(w, h), jump_button(w, h), bench_button(w, h), mix_button(w, h)}
	controls_update(&room.controls, &pointers, w, h, buttons[:])
	if room.controls.pressed == 0 {
		game_switch(game, .Balloon_Lab)
		return
	}
	if room.controls.pressed == 3 {
		game_switch(game, .Sim_Bench)
		return
	}
	grab_pressed := room.controls.pressed == 1
	jump_pressed := room.controls.pressed == 2
	mix_pressed := room.controls.pressed == 4

	// Looking: dragging up looks up, and dragging right turns right.
	delta := room.controls.look_delta
	lab.player_look(&room.player, delta.x * LOOK_SPEED, -delta.y * LOOK_SPEED)

	// Walking: the joystick, or the keyboard on a desktop. Pushing the stick up
	// is forward, because screen y points down.
	push := [2]f32{room.controls.stick.x, -room.controls.stick.y}
	when ODIN_PLATFORM_SUBTARGET != .Android {
		if rl.IsKeyPressed(.E) {
			grab_pressed = true
		}
		if rl.IsKeyPressed(.SPACE) {
			jump_pressed = true
		}
		if rl.IsKeyPressed(.M) {
			mix_pressed = true
		}
		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
			push.y += 1
		}
		if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) {
			push.y -= 1
		}
		if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
			push.x += 1
		}
		if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
			push.x -= 1
		}
	}
	forward := lab.player_flat_forward(&room.player)
	right := lab.player_flat_right(&room.player)
	wish := right * push.x + forward * push.y
	lab.player_move(&room.player, &room.layout, wish, dt)
	if jump_pressed {
		lab.player_jump(&room.player)
	}
	lab.player_update_air(&room.player, dt)

	// Carrying: the button, or E on a desktop, grabs what the crosshair points
	// at, or lets go of what is held.
	carry.update(&room.props, &room.layout, &room.player, dt)
	if grab_pressed {
		if room.props.held != -1 {
			carry.release(&room.props)
		} else {
			carry.grab(&room.props)
		}
	}
	carry.hands_update(&room.hands, carry.state_of(&room.props), dt)

	room.mix_target = carry.mix_target(&room.props)
	if mix_pressed {
		room_mix(room)
		room.mix_target = carry.mix_target(&room.props)
	}
	carry.health_update(&room.health, dt)
	room.blast_flash *= 1 - min(dt * 4, 1)
	room.toast_timer = max(room.toast_timer - dt, 0)
	if carry.health_dead(&room.health) {
		room_reset(room)
		room_toast(room, "knocked out, the lab was reset")
	}
}

room_camera :: proc(room: ^Room) -> rl.Camera3D {
	p := &room.player
	eye := Vec3{p.x, lab.player_eye_y(p), p.z}
	return rl.Camera3D{position = eye, target = eye + lab.player_forward(p), up = {0, 1, 0}, fovy = ROOM_FOV, projection = .PERSPECTIVE}
}

room_draw :: proc(game: ^Game, state: rawptr) {
	room := cast(^Room)state
	rl.ClearBackground(FOG_COLOR)
	camera := room_camera(room)
	rl.BeginMode3D(camera)
	lab_mesh_draw(&room.mesh, camera.position)
	view := carry.view_of(&room.player)
	grip, radius := carry.grip_of(&room.props, view)
	placed: [carry.MAX_HAND_PARTS]carry.Placed
	count := carry.hands_place(&room.hands, view, grip, radius, &placed)
	// Solid things first, then the liquid, then the glass blended over all of it.
	hands_draw(&room.meshes, room.mesh.material, placed[:count])
	props_draw_caps(&room.meshes, room.mesh.material, &room.props)
	props_draw_liquids(&room.meshes, &room.props, camera.position)
	props_draw_glass(&room.meshes, room.mesh.material, &room.props, camera.position)
	rl.EndMode3D()
}

room_draw_ui :: proc(game: ^Game, state: rawptr) {
	room := cast(^Room)state
	w, h := f32(game.screen_w), f32(game.screen_h)
	size := max(i32(18), game.screen_h / 36)
	draw_switch_button(w, h, "balloon")
	when ODIN_PLATFORM_SUBTARGET == .Android {
		rl.DrawText("left thumb walks, right thumb looks", 20, 20, size, {40, 52, 66, 255})
	} else {
		rl.DrawText("WASD or arrows walk, drag the mouse to look, E grabs, M mixes, space jumps", 20, 20, size, {40, 52, 66, 255})
	}
	rl.DrawFPS(20, 20 + size + 8)
	state := carry.state_of(&room.props)
	draw_crosshair(w, h, state)
	draw_flash(w, h, {255, 240, 200, 200}, room.blast_flash)
	draw_flash(w, h, {200, 20, 20, 120}, room.health.flash)
	if focus := carry.focus(&room.props); focus != -1 {
		target: ^carry.Prop
		if room.mix_target != -1 {
			target = &room.props.items[room.mix_target]
		}
		draw_contents(w, h, &room.props.items[focus], target)
	}
	draw_health(w, h, room.health.hp)
	draw_toast(w, h, cstring(raw_data(room.toast[:])), room.toast_timer)
	draw_grab_button(w, h, state)
	draw_jump_button(w, h, room.player.jump > 0)
	draw_mix_button(w, h, room.mix_target != -1)
	draw_bench_button(w, h)
	controls_draw(&room.controls, w, h)
}
