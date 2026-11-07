// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene_arena.odin"
// ============================================================================

package main

import "arena"
import "carry"
import "chem"
import "core:fmt"
import "core:math"
import "effects"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

ARENA_FOV :: f32(70)
ARENA_SKY :: rl.Color{153, 194, 235, 255} // the colour the arena shader fades to, as 8-bit values
ARENA_SEED :: u64(1)
ARENA_SPLASH_SCALE :: f32(4) // bursts are drawn this many times the lab's size, or they are specks across the sand

// The coliseum, walked in first person, with balloons to throw. It is a thin client: the
// simulation (here the Rust world, in time a server) places the player and flies the
// balloons, and this scene sends what the player asks for and draws what comes back. The
// player's own look is the one thing it keeps, so that the view turns the moment a
// finger moves. The balloons are the loadout from the lab: hook 0, 1, and 2 are slot 0, 1,
// and 2, and with none made there is a plain water balloon to try it with.
Arena :: struct {
	coliseum:    ^arena.Coliseum,
	mesh:        Lab_Mesh,
	host:        ^Local_Host,
	table:       arena.Host,
	look:        arena.Look,
	controls:    Controls,
	slots:       [carry.LOADOUT_SLOTS]arena.Slot,
	thrower:     arena.Thrower,
	view:        Arena_View,
	pool:        Character_Pool, // the other players, drawn as the temporary character
	fx:          effects.Effects,
	fx_view:     Effects_View,
	blast_flash: f32,
	hurt_flash:  f32, // red over the screen for a moment when the local player is hit
	hit_marker:  f32, // a red cross round the crosshair for a moment when somebody else is hit
	fire_push:   [2]f32, // where the finger is on the fire stick, from -1 to 1
	last_hp:     [arena.MAX_PLAYERS]u8, // each player's hit points a frame ago
	hp_known:    [arena.MAX_PLAYERS]bool,
	toast:       [96]u8,
	toast_timer: f32,
	bursts:      int, // balloons that have burst since the arena opened
}

arena_toast :: proc(a: ^Arena, format: string, args: ..any) {
	line := fmt.bprintf(a.toast[:len(a.toast) - 1], format, ..args)
	a.toast[len(line)] = 0
	a.toast_timer = 3.5
}

arena_load :: proc(game: ^Game) -> rawptr {
	a := new(Arena)
	a.coliseum = new(arena.Coliseum)
	arena.coliseum_build(a.coliseum)
	shader, ok := load_arena_shader()
	arena_mesh_init(&a.mesh, a.coliseum, shader, ok)

	a.host = local_host_new(ARENA_SEED, arena.LOCAL_PLAYER, 1) // with a bot to look at
	if a.host != nil {
		a.table = local_host_table(a.host)
		// The player starts facing the middle of the arena, wherever the match put them.
		if p, found := arena.view_player(arena.host_view(&a.table), arena.LOCAL_PLAYER); found {
			a.look.yaw = p.yaw
		}
	}
	a.slots = arena.slots_from_loadout(&game.loadout)
	arena.thrower_init(&a.thrower, &a.slots)

	balloon_shader, balloon_ok := load_balloon_shader()
	arena_view_init(&a.view, balloon_shader, balloon_ok)
	effects.init(&a.fx)
	effects_view_init(&a.fx_view)
	character_pool_init(&a.pool)
	if game.art == nil {
		game.art = new(carry.Art_Store)
	}
	pointers: Pointers
	platform_pointers(&pointers)
	controls_init(&a.controls, &pointers)
	// The same clip planes as the lab: close enough to see a balloon in the hand, and far
	// enough for the outer wall from the other side of the arena.
	rlgl.SetClipPlanes(0.08, 70)
	switch {
	case a.host == nil:
		arena_toast(a, "the match could not start")
	case a.slots[0].practice:
		arena_toast(a, "practice balloon: hang your own on a hook in the lab")
	}
	return a
}

arena_unload :: proc(game: ^Game, state: rawptr) {
	a := cast(^Arena)state
	rlgl.SetClipPlanes(0.05, 4000)
	arena_view_unload(&a.view)
	character_pool_unload(&a.pool)
	effects_view_unload(&a.fx_view)
	lab_mesh_unload(&a.mesh)
	local_host_free(a.host)
	free(a.coliseum)
	free(a)
}

// What a balloon bursting looks like. The simulation says how violent it was: a plain
// balloon makes a splash, and a worse one a bigger splash, up to a blast.
arena_burst :: proc(a: ^Arena, b: arena.Burst) {
	color := chem.compound_color(b.compound)
	at := b.pos + {0, 0.03, 0}
	a.bursts += 1
	if b.volatility >= 0.6 {
		effects.blast(&a.fx, at, chem.blast_power(b.volatility), 1, color, color, 0)
		a.blast_flash = 0.4
		return
	}
	effects.pop_scaled(&a.fx, at, color, 1, 0, ARENA_SPLASH_SCALE * (1 + b.volatility))
}

// Chooses a slot, and says so when there is nothing in it.
arena_select :: proc(a: ^Arena, i: int) {
	if !arena.thrower_select(&a.thrower, &a.slots, i) {
		arena_toast(a, "slot %d has no balloon", i + 1)
	}
}

arena_update :: proc(game: ^Game, state: rawptr, dt: f32) {
	a := cast(^Arena)state
	w, h := f32(game.screen_w), f32(game.screen_h)

	pointers: Pointers
	platform_pointers(&pointers)
	buttons := [6][4]f32{switch_button(w, h), throw_button(w, h), slot_button(w, h, 0), slot_button(w, h, 1), slot_button(w, h, 2), arena_jump_button(w, h)}
	controls_update(&a.controls, &pointers, w, h, buttons[:])
	if a.controls.pressed == 0 {
		game_switch(game, .Lab_Room)
		return
	}
	if a.host == nil {
		return
	}
	if a.controls.pressed >= 2 && a.controls.pressed <= 4 {
		arena_select(a, a.controls.pressed - 2)
	}

	// Looking: dragging up looks up, and dragging right turns right.
	delta := a.controls.look_delta
	arena.look_turn(&a.look, delta.x * LOOK_SPEED, -delta.y * LOOK_SPEED)

	// The fire stick: a finger on it also steers the view, by how far it is pushed from the middle.
	// The stick is held for as long as the finger is down, wherever the finger wanders.
	a.fire_push = {}
	if a.controls.held == 1 {
		center, radius := fire_stick(w, h)
		for i in 0 ..< pointers.count {
			if pointers.items[i].id == a.controls.button_id {
				a.fire_push = arena.fire_push(center, radius, pointers.items[i].pos)
			}
		}
		yaw_rate, pitch_rate := arena.fire_turn(a.fire_push)
		arena.look_turn(&a.look, yaw_rate * dt, pitch_rate * dt)
	}

	// Walking: the joystick, or the keyboard on a desktop. Pushing the stick up is forward,
	// because screen y points down.
	push := [2]f32{a.controls.stick.x, -a.controls.stick.y}
	throw_down := a.controls.held == 1
	jump_down := a.controls.held == 5
	when ODIN_PLATFORM_SUBTARGET != .Android {
		if rl.IsKeyDown(.E) {
			throw_down = true
		}
		if rl.IsKeyDown(.SPACE) {
			jump_down = true
		}
		if rl.IsKeyPressed(.ONE) {
			arena_select(a, 0)
		}
		if rl.IsKeyPressed(.TWO) {
			arena_select(a, 1)
		}
		if rl.IsKeyPressed(.THREE) {
			arena_select(a, 2)
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
	if length := math.sqrt(push.x * push.x + push.y * push.y); length > 1 {
		push /= length
	}
	arena.host_input(&a.table, {forward = push.y, strafe = push.x, yaw = a.look.yaw, jump = jump_down})

	// Throwing: holding charges the throw, and letting go throws it where the player looks. A player
	// who is knocked out cannot, and a throw that was charging is let go of without throwing.
	down := arena_down(a)
	if down {
		arena.thrower_cancel(&a.thrower)
		throw_down = false
	}
	if fire, power := arena.thrower_update(&a.thrower, &a.slots, throw_down, dt); fire && !down {
		s := a.slots[a.thrower.selected]
		thrown := arena.host_throw(&a.table, {slot = u8(a.thrower.selected), compound = s.compound, ml = s.ml, dir = arena.look_dir(a.look), power = power})
		if !thrown {
			arena_toast(a, "the throw was refused")
		}
	}

	arena.host_step(&a.table, dt)
	view := arena.host_view(&a.table)
	for i in 0 ..< view.burst_count {
		arena_burst(a, view.bursts[i])
	}
	arena_watch_health(a, view)

	eye := Vec3{0, arena.EYE_HEIGHT, 0}
	if p, found := arena.view_player(view, arena.LOCAL_PLAYER); found {
		eye = arena.eye_of(p)
	}
	arena_view_update(&a.view, &a.slots, a.thrower.selected, game.art, view_basis(eye, a.look), dt)
	character_pool_update(&a.pool, view, arena.LOCAL_PLAYER, dt)

	effects.step(&a.fx, dt)
	a.blast_flash *= 1 - min(dt * 4, 1)
	a.hurt_flash *= 1 - min(dt * 3, 1)
	a.hit_marker = max(a.hit_marker - dt * 3, 0)
	a.toast_timer = max(a.toast_timer - dt, 0)
}

// Whether the local player is knocked out.
arena_down :: proc(a: ^Arena) -> bool {
	if a.host == nil {
		return false
	}
	p, found := arena.view_player(arena.host_view(&a.table), arena.LOCAL_PLAYER)
	return found && arena.knocked_out(p)
}

// Notices whose hit points went down or who was knocked out or came back, since the frame before:
// a red flash when the local player is hit, a cross at the crosshair when somebody else is, and
// a line of text for a knock-out. Who threw is not known to the view, and with one other player in
// the match it is the local player's balloon that hurt them.
arena_watch_health :: proc(a: ^Arena, view: ^arena.Match_View) {
	for i in 0 ..< view.player_count {
		p := view.players[i]
		id := int(p.id) % arena.MAX_PLAYERS
		if a.hp_known[id] {
			before := a.last_hp[id]
			if p.hp < before {
				lost := f32(before - p.hp) / f32(arena.MAX_HEALTH)
				if p.id == arena.LOCAL_PLAYER {
					a.hurt_flash = clamp(0.35 + lost * 2, 0, 0.9)
				} else {
					a.hit_marker = 1
				}
				if p.hp == 0 {
					if p.id == arena.LOCAL_PLAYER {
						arena_toast(a, "you were knocked out")
					} else {
						arena_toast(a, "player %d knocked out", p.id + 1)
					}
				}
			} else if before == 0 && p.hp > 0 && p.id == arena.LOCAL_PLAYER {
				arena_toast(a, "back on your feet")
			}
		}
		a.last_hp[id] = p.hp
		a.hp_known[id] = true
	}
}

arena_camera :: proc(a: ^Arena) -> rl.Camera3D {
	eye := Vec3{0, arena.EYE_HEIGHT, 0}
	if a.host != nil {
		if p, found := arena.view_player(arena.host_view(&a.table), arena.LOCAL_PLAYER); found {
			eye = arena.eye_of(p)
		}
	}
	// A blast knocks the view a little to the side and up, and it settles again.
	v := view_basis(eye, a.look)
	knock := effects.look_shake(&a.fx)
	forward := arena.look_dir(a.look) + v.right * knock.x + v.up * knock.y
	return rl.Camera3D{position = eye, target = eye + forward, up = {0, 1, 0}, fovy = ARENA_FOV, projection = .PERSPECTIVE}
}

arena_draw :: proc(game: ^Game, state: rawptr) {
	a := cast(^Arena)state
	rl.ClearBackground(ARENA_SKY)
	camera := arena_camera(a)
	if a.mesh.lit {
		blast_light_set(a.mesh.material.shader, a.mesh.blast, &a.fx)
	}
	rl.BeginMode3D(camera)
	lab_mesh_draw(&a.mesh, camera.position)
	if a.host != nil {
		view := arena.host_view(&a.table)
		arena_view_draw(&a.view, view, &a.slots, a.thrower.selected, arena.LOCAL_PLAYER, camera.position, a.thrower.cooldown <= 0)
		character_pool_draw(&a.pool, view, arena.LOCAL_PLAYER, a.mesh.material)
	}
	forward := linalg_normalize(camera.target - camera.position)
	cam_right := linalg_normalize(linalg_cross(forward, {0, 1, 0}))
	cam_up := linalg_cross(cam_right, forward)
	if a.host != nil {
		character_bars_draw(arena.host_view(&a.table), arena.LOCAL_PLAYER, forward, cam_right, cam_up)
	}
	effects_draw(&a.fx_view, &a.fx, cam_right, cam_up)
	rl.EndMode3D()
}

arena_draw_ui :: proc(game: ^Game, state: rawptr) {
	a := cast(^Arena)state
	w, h := f32(game.screen_w), f32(game.screen_h)
	size := max(i32(18), game.screen_h / 36)
	draw_switch_button(w, h, "lab")
	when ODIN_PLATFORM_SUBTARGET == .Android {
		rl.DrawText("left thumb walks, hold the round stick to charge, push it to aim, let go to throw", 20, 20, size, {40, 52, 66, 255})
	} else {
		rl.DrawText("WASD or arrows walk, drag the mouse to look, space jumps, hold E (or the round stick) and let go to throw, 1 2 3 choose", 20, 20, size, {40, 52, 66, 255})
	}
	rl.DrawFPS(20, 20 + size + 8)
	if a.host != nil {
		air_buf: [32]u8
		in_air := arena.host_view(&a.table).balloon_count
		rl.DrawText(text_in(air_buf[:], "in the air: %d, burst: %d", in_air, a.bursts), 20, 20 + size * 2 + 16, size, {40, 52, 66, 255})
	}
	draw_arena_crosshair(w, h)
	draw_flash(w, h, {255, 240, 200, 200}, a.blast_flash)
	draw_flash(w, h, {220, 40, 30, 200}, a.hurt_flash)
	draw_hit_marker(w, h, a.hit_marker)

	for i in 0 ..< carry.LOADOUT_SLOTS {
		draw_slot_button(w, h, i, a.slots[i], i == a.thrower.selected)
	}
	down := arena_down(a)
	draw_throw_button(w, h, &a.thrower, &a.slots, down, a.controls.held == 1, a.fire_push)
	grounded := true
	local_hp := arena.MAX_HEALTH
	if a.host != nil {
		if p, found := arena.view_player(arena.host_view(&a.table), arena.LOCAL_PLAYER); found {
			grounded = arena.on_floor(p)
			local_hp = p.hp
		}
	}
	draw_health_bar(w, h, local_hp)
	if down {
		draw_text_centered("knocked out", i32(w * 0.5), i32(h * 0.38), size * 3, {235, 70, 60, 255})
		draw_text_centered("back in a moment", i32(w * 0.5), i32(h * 0.38) + size * 3 + 8, size, {40, 52, 66, 255})
	}
	draw_arena_jump_button(w, h, !grounded || down)
	if arena.slot_usable(&a.slots, a.thrower.selected) {
		s := a.slots[a.thrower.selected]
		line_buf: [64]u8
		text := text_in(line_buf[:], "slot %d: %v, %d ml%v", a.thrower.selected + 1, chem.compound_name(s.compound), s.ml, s.practice ? " (practice)" : "")
		g := throw_button(w, h)
		draw_text_centered(text, i32(w * 0.5), i32(g.y) - i32(size) * 3, size, {20, 28, 40, 255})
	}
	draw_toast(w, h, cstring(raw_data(a.toast[:])), a.toast_timer)
	controls_draw(&a.controls, w, h)
}
