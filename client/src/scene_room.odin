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
import "core:time"
import "effects"
import "lab"

LOOK_SPEED :: f32(0.0045) // radians of turn for each pixel dragged
ROOM_FOV :: f32(70)
FOG_COLOR :: rl.Color{204, 214, 224, 255}
STREAM_BUDGET_US :: f32(5000) // the most the liquid may take of a frame, in microseconds

// The chemistry lab, walked around in first person: a large open room with
// long counters along the walls, a bottle wall on the east side, and one
// counter in the middle with vessels on it that can be picked up, carried, and
// poured into each other.
Room :: struct {
	layout:      lab.Layout,
	player:      lab.Player,
	mesh:        Lab_Mesh,
	controls:    Controls,
	props:       carry.Props,
	hands:       carry.Hands,
	meshes:      Prop_Meshes,
	health:      carry.Health,
	stream:      carry.Stream, // liquid in the air
	station:     carry.Station, // the bottle wall
	valve:       int, // the tap the held vessel is under, or -1
	pour_target: int, // the vessel the crosshair is on while one is held, close enough to pour into, or -1
	step_us:     f32, // how long one step of the liquid took lately, in microseconds
	menu_open:   bool, // the reaction matrix is showing, and the lab is paused
	blast_flash: f32, // how white the screen is from a blast, fading
	fx:          effects.Effects, // the look of blasts, spatters, and burst balloons
	fx_view:     Effects_View,
	filler:      carry.Filler, // the balloon fill station
	filler_view: Filler_View,
	toast:       [96]u8, // what the last mix did, as text
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
	carry.stream_clear(&room.stream)
	carry.props_init(&room.props)
	carry.props_place_defaults(&room.props, &room.layout)
	carry.health_init(&room.health)
	carry.filler_init(&room.filler)
	effects.reset(&room.fx)
	room.blast_flash = 0
	room.pour_target = -1
	room.valve = -1
}

// A reaction that a pour started: shows what came of it, and takes the damage, less
// what the fume hood stops. The look of it comes from the effects: a spatter throws
// drops of the liquid, and a blast is fire, sparks, smoke, a ring, a flash of light
// on the room, a knock to the view, and a wobble of the picture, smaller in the hood.
room_react :: proc(room: ^Room, r: carry.Mix_Result) {
	a, b, product := chem.compound_name(r.a), chem.compound_name(r.b), chem.compound_name(r.product)
	open := carry.openness(r)
	floor := carry.support_height(&room.layout, r.at.x, r.at.z, 0.1)
	color_a, color_b := chem.compound_color(r.a), chem.compound_color(r.b)
	switch r.kind {
	case .Nothing:
	case .Mixed:
		room_toast(room, "%v + %v made %v", a, b, product)
	case .Spatter:
		room.blast_flash = 0.4
		effects.spatter(&room.fx, r.at, effects.mix_color(color_a, color_b, 0.5), floor)
		room_toast(room, "SPATTER! %v + %v made %v", a, b, product)
	case .Blast:
		room.blast_flash = 0.4 + 0.6 * open
		effects.blast(&room.fx, r.at, chem.blast_power(r.volatility), open, color_a, color_b, floor)
		if open == 0 {
			room_toast(room, "BLAST in the hood! %v + %v", a, b)
		} else {
			room_toast(room, "BLAST! %v + %v", a, b)
		}
	}
	carry.health_hurt(&room.health, carry.felt_damage(r))
}

// What a drop into the balloon did: a reaction, shown as for a vessel, and a burst
// from overfilling, which sends the liquid flying but hurts nobody.
room_fill_event :: proc(room: ^Room, e: carry.Fill_Result) {
	if e.mix.kind != .Nothing {
		room_react(room, e.mix)
	}
	if e.popped {
		at := lab.filler_center()
		floor := carry.support_height(&room.layout, at.x, at.z, 0.1)
		effects.pop(&room.fx, at, chem.compound_color(e.lost), 1, floor)
		room_toast(room, "POP! the balloon was overfilled")
	}
}

// Runs the liquid for this frame. It takes as many substeps as a real-time frame
// needs, or fewer if they would take too long, and then the liquid runs a little
// slower than real time instead of the frame being late.
room_stream_step :: proc(room: ^Room, dt: f32) {
	if room.stream.sim.count == 0 {
		return
	}
	needed := clamp(int(dt / carry.STREAM_DT + 0.999), 1, 40)
	steps := clamp(int(STREAM_BUDGET_US / max(room.step_us, 1)), 1, needed)
	start := time.tick_now()
	carry.stream_step(&room.stream, steps)
	elapsed := f32(time.duration_microseconds(time.tick_diff(start, time.tick_now())))
	room.step_us += (elapsed / f32(steps) - room.step_us) * 0.2
}

room_load :: proc(game: ^Game) -> rawptr {
	room := new(Room)
	lab.build(&room.layout)
	lab.add_dispensers(&room.layout, carry.station_colors())
	lab.add_apparatus(&room.layout)
	lab.player_init(&room.player, &room.layout)
	shader, ok := load_lab_shader()
	lab_mesh_init(&room.mesh, &room.layout, shader, ok)
	carry.props_init(&room.props)
	carry.props_place_defaults(&room.props, &room.layout)
	carry.stream_init(&room.stream)
	carry.station_init(&room.station)
	prop_meshes_init(&room.meshes)
	carry.health_init(&room.health)
	carry.filler_init(&room.filler)
	effects.init(&room.fx)
	effects_view_init(&room.fx_view)
	balloon_shader, balloon_ok := load_balloon_shader()
	filler_view_init(&room.filler_view, balloon_shader, balloon_ok)
	room.pour_target = -1
	room.valve = -1
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
	game.heat_strength = 0
	filler_view_unload(&room.filler_view)
	effects_view_unload(&room.fx_view)
	prop_meshes_unload(&room.meshes)
	carry.stream_destroy(&room.stream)
	lab_mesh_unload(&room.mesh)
	free(room)
}

inside :: proc(pointer: [2]f32, box: [4]f32) -> bool {
	return pointer.x >= box.x && pointer.x <= box.x + box.z && pointer.y >= box.y && pointer.y <= box.y + box.w
}

room_update :: proc(game: ^Game, state: rawptr, dt: f32) {
	room := cast(^Room)state
	w, h := f32(game.screen_w), f32(game.screen_h)

	pointers: Pointers
	platform_pointers(&pointers)

	// With the reaction matrix open the lab waits, and only its close button works.
	if room.menu_open {
		closed := rl.IsMouseButtonPressed(.LEFT) && inside(platform_mouse_position(), matrix_close_button(w, h))
		when ODIN_PLATFORM_SUBTARGET != .Android {
			closed = closed || rl.IsKeyPressed(.R)
		}
		if closed {
			room.menu_open = false
			controls_init(&room.controls, &pointers) // the finger that closed it must not start walking
		}
		return
	}

	buttons := [6][4]f32{switch_button(w, h), grab_button(w, h), jump_button(w, h), bench_button(w, h), pour_button(w, h), matrix_button(w, h)}
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
	pour_down := room.controls.held == 4
	if room.controls.pressed == 5 {
		room.menu_open = true
		return
	}

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
		if rl.IsKeyDown(.M) {
			pour_down = true
		}
		if rl.IsKeyPressed(.R) {
			room.menu_open = true
			return
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

	// Under a tap the pour button fills the held vessel, and otherwise it tips the
	// held vessel over to pour.
	room.valve = pour_down ? carry.dispenser_under(&room.station, &room.props) : -1
	room.props.pouring = pour_down && room.valve == -1 && room.props.held != -1

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
	room.pour_target = carry.pour_target(&room.props)
	carry.filler_aim(&room.filler, &room.props, carry.view_of(&room.player))

	// Liquid: let out of a tap or over the lip of the held vessel, simulated, and
	// taken by the vessels it lands in.
	eye := carry.view_of(&room.player).eye
	if room.valve != -1 {
		if !carry.station_flow(&room.station, &room.stream, &room.layout, room.valve, dt) {
			room_toast(room, "that tap is locked")
		}
	} else if carry.filler_pour_ready(&room.filler, &room.props) {
		carry.pour_flow_to(&room.props, &room.stream, &room.layout, dt, carry.filler_mouth(), true)
	} else {
		carry.pour_flow(&room.props, &room.stream, &room.layout, dt)
	}
	room_stream_step(room, dt)
	events: [carry.MAX_EVENTS]carry.Mix_Result
	for i in 0 ..< carry.stream_capture(&room.stream, &room.props, eye, &events) {
		room_react(room, events[i])
	}
	fill_events: [carry.MAX_EVENTS]carry.Fill_Result
	for i in 0 ..< carry.filler_capture(&room.stream, &room.filler, eye, &fill_events) {
		room_fill_event(room, fill_events[i])
	}
	carry.stream_drain(&room.stream)
	carry.filler_update(&room.filler, dt)
	filler_view_update(&room.filler_view, &room.filler, dt)
	effects.step(&room.fx, dt)
	game.heat_strength = room.fx.heat

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
	// A blast knocks the view a little to the side and up, and it settles again.
	v := carry.view_of(p)
	knock := effects.look_shake(&room.fx)
	forward := lab.player_forward(p) + v.right * knock.x + v.up * knock.y
	return rl.Camera3D{position = eye, target = eye + forward, up = {0, 1, 0}, fovy = ROOM_FOV, projection = .PERSPECTIVE}
}

room_draw :: proc(game: ^Game, state: rawptr) {
	room := cast(^Room)state
	rl.ClearBackground(FOG_COLOR)
	camera := room_camera(room)
	if room.mesh.lit {
		blast_light_set(room.mesh.material.shader, room.mesh.blast, &room.fx)
	}
	if room.meshes.vessel_ok {
		blast_light_set(room.meshes.vessel.shader, room.meshes.blast, &room.fx)
	}
	rl.BeginMode3D(camera)
	lab_mesh_draw(&room.mesh, camera.position)
	view := carry.view_of(&room.player)
	grip, radius := carry.grip_of(&room.props, view)
	placed: [carry.MAX_HAND_PARTS]carry.Placed
	count := carry.hands_place(&room.hands, view, grip, radius, &placed)
	// Solid things first, then the liquid, then the glass blended over all of it.
	hands_draw(&room.meshes, room.mesh.material, placed[:count])
	props_draw_caps(&room.meshes, room.mesh.material, &room.props)
	stream_draw(&room.stream)
	props_draw_liquids(&room.meshes, &room.props, camera.position)
	filler_view_draw(&room.filler_view, &room.filler, camera.position)
	props_draw_glass(&room.meshes, room.mesh.material, &room.props, camera.position)
	stations_draw(&room.filler)
	effects_draw(&room.fx_view, &room.fx, view.right, view.up)
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
		rl.DrawText("WASD or arrows walk, drag the mouse to look, E grabs, hold M to pour, R reactions, space jumps", 20, 20, size, {40, 52, 66, 255})
	}
	rl.DrawFPS(20, 20 + size + 8)
	state := carry.state_of(&room.props)
	draw_crosshair(w, h, state)
	draw_flash(w, h, {255, 240, 200, 200}, room.blast_flash)
	draw_flash(w, h, {200, 20, 20, 120}, room.health.flash)
	if focus := carry.focus(&room.props); focus != -1 {
		target: ^carry.Prop
		if room.pour_target != -1 {
			target = &room.props.items[room.pour_target]
		}
		draw_contents(w, h, &room.props.items[focus], target)
	}
	if room.filler.aimed && room.pour_target == -1 {
		draw_filler_readout(w, h, &room.filler, carry.focus(&room.props) != -1 ? 1 : 0)
	}
	draw_health(w, h, room.health.hp)
	draw_toast(w, h, cstring(raw_data(room.toast[:])), room.toast_timer)
	draw_grab_button(w, h, state)
	draw_jump_button(w, h, room.player.jump > 0)
	label: cstring = "pour"
	ready := false
	switch {
	case room.valve != -1:
		label, ready = "fill", true
	case room.pour_target != -1:
		label, ready = "mix", true
	case carry.filler_pour_ready(&room.filler, &room.props):
		label, ready = "balloon", true
	}
	draw_pour_button(w, h, label, ready, room.controls.held == 4)
	draw_bench_button(w, h)
	draw_matrix_button(w, h)
	controls_draw(&room.controls, w, h)
	if room.menu_open {
		draw_matrix_menu(w, h)
	}
}
