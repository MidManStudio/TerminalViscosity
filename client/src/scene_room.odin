// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene_room.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "carry"
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
	buttons := [4][4]f32{switch_button(w, h), grab_button(w, h), jump_button(w, h), bench_button(w, h)}
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
		rl.DrawText("WASD or arrows walk, drag the mouse to look, E grabs, space jumps", 20, 20, size, {40, 52, 66, 255})
	}
	rl.DrawFPS(20, 20 + size + 8)
	state := carry.state_of(&room.props)
	draw_crosshair(w, h, state)
	if focus := carry.focus(&room.props); focus != -1 {
		draw_contents(w, h, &room.props.items[focus])
	}
	draw_grab_button(w, h, state)
	draw_jump_button(w, h, room.player.jump > 0)
	draw_bench_button(w, h)
	controls_draw(&room.controls, w, h)
}
