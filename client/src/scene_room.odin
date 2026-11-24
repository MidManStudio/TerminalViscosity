// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene_room.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "carry"
import "chem"
import "dragdrop"
import "chemistry"
import "core:fmt"
import "core:math"
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
	spill_shader: rl.Shader, // what puddles and beads of liquid are drawn with
	spill_ok:    bool,
	station:     carry.Station, // the bottle wall
	valve:       int, // the tap the held vessel is under, or -1
	pour_target: int, // the vessel the crosshair is on while one is held, close enough to pour into, or -1
	step_us:     f32, // how long one step of the liquid took lately, in microseconds
	menu_open:   bool, // the book of reactions is showing, and the lab is paused
	stock:       carry.Stock, // the bag, and what is mounted on the bottle wall
	stock_ui:    Stock_Ui,
	stock_open:  bool, // the bag and the wall are showing, and the lab is paused
	menu_page:   int, // the page of the book it is open at, 0 for the contents
	blast_flash: f32, // how white the screen is from a blast, fading
	fx:          effects.Effects, // the look of blasts, spatters, and burst balloons
	fx_view:     Effects_View,
	filler:      carry.Filler, // the balloon fill station
	oven:        carry.Oven, // the reaction oven
	spout:       bool, // the held vessel is near the spout of the oven, with product to fill it
	spout_rest:  int, // a vessel standing on the tray under the spout, which the pour button fills, or -1
	loadout_view: Loadout_View,
	painting:    bool, // the drawing screen is open
	save_wanted: bool, // the loadout has changed and is to be written
	paint:       ^carry.Paint, // the paint and brush chosen, and the strokes that can be taken back
	paint_turn:  f32, // how far round the balloon in the paint station is turned, as a share of a turn
	paint_input: Paint_Input,
	steam_timer: f32, // seconds since hot vessels last gave off steam
	vent_timer:  f32, // seconds since the oven last puffed steam
	filler_view: Filler_View,
	toast:       [96]u8, // what the last mix did, as text
	toast_timer: f32,
	burn_vent:   f32, // time since the last puff from the chimney
	burn_timer:  f32, // seconds the incinerator has left to burn, with smoke from its chimney
	first_aid:   carry.First_Aid, // the cabinet on the north wall
	soap:        carry.Soap, // the soap by the sink
	pickup:      carry.Pickup, // the station that the crosshair is on, which can be picked up
	blueprint:   carry.Blueprint, // the station that is being carried, as a copy of itself, if one is
	scale:       carry.Scale, // the scale on the north counter
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
	if room.blueprint.active {
		// A station that is carried is put back, and not lost, and the lab is built again with it where it is now.
		if carry.blueprint_cancel(&room.blueprint, &room.props, &room.stock.bag) != .No_Room {
			room_stock_changed(room)
		}
	}
	lab.player_init(&room.player, &room.layout)
	carry.stream_clear(&room.stream)
	speed := carry.flow_speed(&room.props) // a knock-out does not change the speed that was set
	placed := room.props.placed // nor where the stations stand
	carry.props_init(&room.props)
	room.props.placed = placed
	room.props.speed = speed
	carry.props_place_defaults(&room.props, &room.layout)
	carry.health_init(&room.health)
	carry.filler_init(&room.filler)
	carry.oven_init(&room.oven)
	effects.reset(&room.fx)
	room.blast_flash = 0
	room.pour_target = -1
	room.valve = -1
	room.spout = false
	room.spout_rest = -1
	room.first_aid = {}
	room.soap = {}
	room.pickup = {}
	room.scale = {}
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
		if r.product != 0 {
			room_toast(room, "%v + %v made %v", a, b, product)
		} else {
			room_toast(room, "%v + %v mixed", a, b)
		}
	case .Spatter:
		room.blast_flash = 0.4
		effects.spatter(&room.fx, r.at, effects.mix_color(color_a, color_b, 0.5), floor)
		room_toast(room, "SPATTER! %v + %v %v", a, b, event_word(r))
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

// What went wrong in a reaction, in words, from the first step of it that had an event: a splash, fumes,
// a fire or a burst.
event_word :: proc(r: carry.Mix_Result) -> string {
	for i in 0 ..< r.steps.count {
		step := r.steps.steps[i]
		#partial switch step.event {
		case .Splash:
			return step.wrong_order ? "spat: water went into the acid" : "splashed"
		case .Fumes:
			return "gave off fumes"
		case .Fire:
			return "caught fire"
		case .Burst:
			return "burst"
		}
	}
	return "went wrong"
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

// Does a balloon action and says what was done. A stretched balloon is let down to
// full when it is tied, and the player is told how much was let out.
room_balloon_action :: proc(room: ^Room, lo: ^carry.Loadout, action: carry.Balloon_Action) {
	slot := lo.spot_slot
	burned := lo.hand // what the incinerator is about to take, if that is the action
	let_out, ok := carry.balloon_do(lo, &room.filler, action)
	if !ok {
		return
	}
	room.save_wanted = true
	switch action {
	case .None:
	case .Tie_Take:
		if let_out > 0.5 {
			room_toast(room, "tied off, and let %d ml out of the stretched balloon", int(let_out + 0.5))
		} else {
			room_toast(room, "tied off and took the balloon")
		}
	case .Clamp:
		room_toast(room, "clamped in the paint station")
	case .Take_Paint:
		room_toast(room, "took the balloon from the paint station")
	case .Store:
		room_toast(room, "hung on hook %d", slot + 1)
	case .Take_Slot:
		room_toast(room, "took the balloon from hook %d", slot + 1)
	case .Burn:
		room_burn(room, burned)
	case .Paint:
	}
}

// A balloon dropped in the incinerator: a flash of fire in the hopper, in the colours of what was
// in it, and smoke from the chimney for a few seconds.
room_burn :: proc(room: ^Room, item: carry.Item) {
	item_mix := item.mix
	color := chemistry.mix_color(&item_mix)
	effects.blast(&room.fx, lab.INCINERATOR_MOUTH, 0.2, 0, color, color, lab.COUNTER_HEIGHT)
	room.burn_timer = 2.5
	room.burn_vent = 0
	room_toast(room, "burned the balloon")
}

// Smoke from the chimney while the incinerator burns, and a low rumble if the player is near.
room_burn_effects :: proc(room: ^Room, dt: f32) {
	if room.burn_timer <= 0 {
		return
	}
	room.burn_timer = max(room.burn_timer - dt, 0)
	room.burn_vent += dt
	vent := lab.incinerator_vent()
	for room.burn_vent >= 0.1 {
		room.burn_vent -= 0.1
		effects.vent(&room.fx, vent, {0.3, 0.28, 0.27})
	}
	eye := carry.view_of(&room.player).eye
	d := eye - lab.INCINERATOR_MOUTH
	if d.x * d.x + d.y * d.y + d.z * d.z < 16 {
		effects.rumble(&room.fx, 0.003)
	}
}

// Heats and cools the liquids, and shows what a vessel did that reacted because its temperature moved,
// in the same way as a drop that starts a reaction. A vessel that blasts has broken.
room_heat_events :: proc(room: ^Room, dt: f32) {
	events: [carry.MAX_EVENTS]carry.Mix_Result
	eye := carry.view_of(&room.player).eye
	count := carry.props_heat_update(&room.props, dt, eye, &events)
	for i in 0 ..< count {
		room_react(room, events[i])
	}
}

// Hot liquid gives off steam: a wisp from the top of each vessel that is hot, a few
// times a second.
room_steam :: proc(room: ^Room, dt: f32) {
	room.steam_timer += dt
	if room.steam_timer < 0.25 {
		return
	}
	room.steam_timer = 0
	for i in 0 ..< room.props.count {
		pr := room.props.items[i]
		if carry.ml_of(&pr.mix) > 0 && carry.heat_unit(pr.mix.heat_c) > 0.6 {
			top := Vec3{pr.pos.x, pr.pos.y + carry.kind_dims(pr.kind).height, pr.pos.z}
			effects.steam(&room.fx, top, chemistry.mix_color(&pr.mix))
		}
	}
}

// What the oven did: a refusal of a liquid, told in a line, or the end of a run. A
// run that was violent has the look of a blast at the top of the oven, with the
// light, the sparks, the smoke, and the ring, and it hurts nobody, because it
// happened inside the machine. That is the point of the oven.
room_oven_event :: proc(room: ^Room, e: carry.Oven_Event) {
	switch e.kind {
	case .Nothing:
	case .Refused:
		room_toast(room, "port %d holds %v, a port takes one liquid", e.port + 1, chem.compound_name(e.compound))
	case .Finished:
		at := lab.mixer_vent()
		floor := carry.support_height(&room.layout, at.x, at.z, 0.1)
		color := chem.compound_color(e.compound)
		name := chem.compound_name(e.compound)
		switch {
		case e.volatility >= 0.6:
			effects.blast(&room.fx, at, chem.blast_power(e.volatility), 0, color, color, floor)
			room_toast(room, "%v ready, %d ml. It blasted, and the oven held it. Spout on the right", name, int(e.ml + 0.5))
		case e.volatility >= 0.3:
			effects.spatter(&room.fx, at, color, floor)
			room_toast(room, "%v ready, %d ml. It spattered, and the oven held it. Spout on the right", name, int(e.ml + 0.5))
		case:
			room_toast(room, "%v ready, %d ml. Fill a vessel at the spout on the right", name, int(e.ml + 0.5))
		}
	}
}

// While a run goes the oven puffs steam from its top a few times a second, tinted by
// the first liquid in it, and the view rumbles a little when the player is near.
room_oven_effects :: proc(room: ^Room, dt: f32) {
	if room.oven.state != .Running {
		room.vent_timer = 0
		return
	}
	room.vent_timer += dt
	vent := lab.mixer_vent()
	color := Vec3{0.8, 0.8, 0.85}
	for p in room.oven.ports {
		if p.ml > 0 {
			color = chem.compound_color(p.compound)
			break
		}
	}
	for room.vent_timer >= 0.15 {
		room.vent_timer -= 0.15
		effects.vent(&room.fx, vent, color)
	}
	eye := carry.view_of(&room.player).eye
	d := eye - vent
	if d.x * d.x + d.y * d.y + d.z * d.z < 36 {
		effects.rumble(&room.fx, 0.004)
	}
}

// Runs the liquid for this frame. It takes as many substeps as a real-time frame
// needs, or fewer if they would take too long, and then the liquid runs a little
// slower than real time instead of the frame being late.
room_stream_step :: proc(room: ^Room, dt: f32) {
	// Puddles go on lying, and dissolve, when nothing is in the air, and in real time.
	carry.spill_step(&room.stream.spill, dt)
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

// Builds the lab from nothing: the room, the bottle wall with the dispensers that are mounted on it, the
// apparatus and the shelves. It is called when the lab is loaded, and again when a dispenser has been moved.
room_build_layout :: proc(room: ^Room) {
	lab.build(&room.layout)
	colors, present := carry.wall_look(&room.stock.wall)
	lab.add_dispensers_with(&room.layout, colors, present)
	lab.add_apparatus_with(&room.layout, room.props.placed)
	shelf_colors := carry.shelf_colors()
	lab.add_shelves(&room.layout, shelf_colors[:])
}

// Saves the stock and where the stations stand, unless a station is being carried: it is in neither the bag nor on a
// counter then, and the file keeps it where it was picked up from, so that nothing that ends the game while it is carried
// can lose it.
room_save_stock :: proc(room: ^Room) {
	if !room.blueprint.active {
		stock_save(&room.stock, &room.props.placed)
	}
}

// What follows when the contents of the bag or the wall changed, or a station was picked up, put down or put back: the
// taps follow what is mounted, the lab and its mesh are made again so that the bottles and the stations are where they
// are, and the stock is saved.
room_stock_changed :: proc(room: ^Room) {
	carry.station_sync(&room.station, &room.stock.wall)
	room.scale.tare = 0 // a scale that has been moved starts at nothing
	room_build_layout(room)
	lab_mesh_rebuild(&room.mesh, &room.layout)
	room_save_stock(room)
}

// Puts the carried station down where the crosshair has it, if it can stand there, and otherwise says why it cannot.
room_blueprint_place :: proc(room: ^Room) {
	bp := &room.blueprint
	if !bp.ok {
		room_toast(room, "%v", carry.blueprint_words(bp.problem))
		return
	}
	name := carry.station_name(bp.kind)
	if carry.blueprint_place(bp, &room.props) {
		room_stock_changed(room)
		room_toast(room, "%v put down", name)
	}
}

// Puts the carried station back where it was picked up from, or into the bag if that place is not free.
room_blueprint_cancel :: proc(room: ^Room) {
	name := carry.station_name(room.blueprint.kind)
	switch carry.blueprint_cancel(&room.blueprint, &room.props, &room.stock.bag) {
	case .Put_Back:
		room_stock_changed(room)
		room_toast(room, "%v is back where it was", name)
	case .In_Bag:
		room_stock_changed(room)
		room_toast(room, "%v is in the bag", name)
	case .No_Room:
		room_toast(room, "no room in the bag: put the %v down on a counter", name)
	case .Nothing:
	}
}

room_load :: proc(game: ^Game) -> rawptr {
	room := new(Room)
	carry.stock_init(&room.stock)
	stock_ui_init(&room.stock_ui)
	carry.props_init(&room.props) // before the stock is read, which says where the stations stand
	stock_load(&room.stock, &room.props.placed)
	room_build_layout(room)
	lab.player_init(&room.player, &room.layout)
	shader, ok := load_lab_shader()
	lab_mesh_init(&room.mesh, &room.layout, shader, ok)
	carry.props_place_defaults(&room.props, &room.layout)
	carry.stream_init(&room.stream)
	carry.station_init(&room.station)
	carry.station_sync(&room.station, &room.stock.wall)
	prop_meshes_init(&room.meshes)
	carry.health_init(&room.health)
	carry.filler_init(&room.filler)
	carry.oven_init(&room.oven)
	effects.init(&room.fx)
	effects_view_init(&room.fx_view)
	room.spill_shader, room.spill_ok = load_spill_shader()
	balloon_shader, balloon_ok := load_balloon_shader()
	filler_view_init(&room.filler_view, balloon_shader, balloon_ok)
	loadout_view_init(&room.loadout_view, balloon_shader, balloon_ok)
	room.paint = new(carry.Paint)
	carry.paint_init(room.paint)
	if game.art == nil {
		game.art = new(carry.Art_Store)
	}
	room.pour_target = -1
	room.valve = -1
	room.spout_rest = -1
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
	loadout_save(game)
	if room.blueprint.active {
		carry.blueprint_cancel(&room.blueprint, &room.props, &room.stock.bag) // put back before the file is written
	}
	room_save_stock(room)
	free(room.paint)
	loadout_view_unload(&room.loadout_view)
	filler_view_unload(&room.filler_view)
	effects_view_unload(&room.fx_view)
	prop_meshes_unload(&room.meshes)
	carry.stream_destroy(&room.stream)
	if room.spill_ok {
		rl.UnloadShader(room.spill_shader)
	}
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

	// A change to the balloons is written the frame after it, so a frame that makes
	// several changes writes the file once.
	if room.save_wanted {
		room.save_wanted = false
		loadout_save(game)
	}

	// While drawing the lab waits, and the fingers draw, choose, and turn the balloon.
	if room.painting {
		l := carry.paint_layout(w, h)
		done, no_room := paint_touch_update(&room.paint_input, &pointers, &l, room.paint, &game.loadout, game.art, &room.paint_turn, h)
		if no_room {
			room_toast(room, "no room for another drawing")
		}
		loadout_view_update(&room.loadout_view, &game.loadout, game.art, carry.view_of(&room.player), dt)
		if done {
			room.painting = false
			room.save_wanted = true
			carry.paint_stroke_end(room.paint)
			controls_init(&room.controls, &pointers) // the finger that pressed done must not start walking
		}
		return
	}

	// With the book open the lab waits, and only the book's own buttons work.
	if room.menu_open {
		pointer := platform_mouse_position()
		pressed := rl.IsMouseButtonPressed(.LEFT)
		closed := pressed && inside(pointer, book_close_button(w, h))
		if pressed {
			room.menu_page = book_press(room.menu_page, pointer, w, h)
		}
		when ODIN_PLATFORM_SUBTARGET != .Android {
			closed = closed || rl.IsKeyPressed(.R)
			if rl.IsKeyPressed(.LEFT) {
				room.menu_page = book_prev_page(room.menu_page)
			}
			if rl.IsKeyPressed(.RIGHT) {
				room.menu_page = book_next_page(room.menu_page)
			}
		}
		if closed {
			room.menu_open = false
			controls_init(&room.controls, &pointers) // the finger that closed it must not start walking
		}
		return
	}

	// With the bag and the wall open the lab waits as well. A press on a stack that can be moved starts a drag, and
	// letting go moves it where it can go.
	if room.stock_open {
		pointer := platform_mouse_position()
		pressed := rl.IsMouseButtonPressed(.LEFT)
		closed := pressed && inside(pointer, book_close_button(w, h))
		when ODIN_PLATFORM_SUBTARGET != .Android {
			closed = closed || rl.IsKeyPressed(.B)
		}
		if closed {
			dragdrop.cancel(&room.stock_ui.drag)
			room.stock_open = false
			controls_init(&room.controls, &pointers) // the finger that closed it must not start walking
		} else {
			room.stock_ui.hands_free = room.props.held == -1
			if stock_update(&room.stock_ui, &room.stock, pointer, pressed, rl.IsMouseButtonReleased(.LEFT), w, h) {
				room_stock_changed(room)
			}
			if slot := room.stock_ui.carry_slot; slot != -1 && carry.blueprint_take_from_bag(&room.blueprint, &room.props, &room.stock.bag, slot) {
				// Carry the station: the screen closes, and the copy follows the crosshair. Nothing is saved while it is carried.
				room.stock_open = false
				controls_init(&room.controls, &pointers)
				room_toast(room, "%v: aim at a counter and press place", carry.station_name(room.blueprint.kind))
			}
		}
		return
	}

	buttons := [10][4]f32{switch_button(w, h), grab_button(w, h), jump_button(w, h), bench_button(w, h), pour_button(w, h), book_button(w, h), speed_button(w, h), arena_button(w, h), bag_button(w, h), pickup_button(w, h)}
	controls_update(&room.controls, &pointers, w, h, buttons[:])
	if button_pressed(&room.controls, 0) {
		game_switch(game, .Balloon_Lab)
		return
	}
	if button_pressed(&room.controls, 3) {
		game_switch(game, .Sim_Bench)
		return
	}
	if button_pressed(&room.controls, 7) {
		game_switch(game, .Arena)
		return
	}
	grab_pressed := button_pressed(&room.controls, 1)
	jump_pressed := button_pressed(&room.controls, 2)
	pour_down := button_held(&room.controls, 4)
	rotate_pressed := button_pressed(&room.controls, 9) // pick up, or turn the station that is carried
	cancel_pressed := button_pressed(&room.controls, 4) // put the station that is carried back
	carrying := room.blueprint.active
	speed_pressed := button_pressed(&room.controls, 6)
	if button_pressed(&room.controls, 5) {
		room.menu_open = true
		return
	}
	bag_pressed := button_pressed(&room.controls, 8)
	when ODIN_PLATFORM_SUBTARGET != .Android {
		bag_pressed = bag_pressed || rl.IsKeyPressed(.B)
	}
	if bag_pressed && carrying {
		room_toast(room, "put the station down or put it back first")
	} else if bag_pressed {
		room.stock_open = true
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
		if rl.IsKeyPressed(.Q) {
			rotate_pressed = true
		}
		if rl.IsKeyPressed(.X) {
			cancel_pressed = true
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
		if rl.IsKeyPressed(.V) {
			speed_pressed = true
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

	if speed_pressed {
		room_toast(room, "liquid speed x%d", int(carry.speed_cycle(&room.props)))
	}

	// Near a tap, or the spout of the oven, the pour button fills the held vessel, and
	// otherwise it tips the held vessel over to pour. Which one is known before the
	// button is pressed, so the button can show it.
	if carrying {
		pour_down = false // the pour button cancels while a station is carried, and pours nothing
	}
	room.valve = carry.dispenser_under(&room.station, &room.props)
	room.spout = room.valve == -1 && carry.oven_spout_under(&room.oven, &room.props)
	room.spout_rest = room.props.held == -1 ? carry.oven_rest_under(&room.oven, &room.props) : -1
	room.props.pouring = pour_down && room.valve == -1 && !room.spout && room.props.held != -1

	// Carrying: the button, or E on a desktop, grabs what the crosshair points
	// at, or lets go of what is held.
	carry.update(&room.props, &room.layout, &room.player, dt)
	carry.oven_aim(&room.oven, &room.props, carry.view_of(&room.player))
	carry.filler_aim(&room.filler, &room.props, carry.view_of(&room.player))
	carry.loadout_aim(&game.loadout, &room.filler, &room.props, carry.view_of(&room.player))
	carry.first_aid_aim(&room.first_aid, &room.props, carry.view_of(&room.player))
	carry.soap_aim(&room.soap, &room.props, carry.view_of(&room.player))
	if carrying {
		// The copy of the station follows the crosshair, and is put down, turned or put back by the buttons.
		room.pickup = {}
		if rotate_pressed {
			carry.blueprint_rotate(&room.blueprint)
		}
		carry.blueprint_aim(&room.blueprint, &room.props, carry.view_of(&room.player))
		if grab_pressed {
			room_blueprint_place(room)
		} else if cancel_pressed {
			room_blueprint_cancel(room)
		}
		grab_pressed = false
	} else {
		carry.pickup_aim(&room.pickup, &room.props, carry.view_of(&room.player))
		if rotate_pressed && room.pickup.aimed {
			switch {
			case room.props.held != -1:
				room_toast(room, "hands are full")
			case room.pickup.busy:
				room_toast(room, "take the vessel off the %v first", carry.station_name(room.props.placed.items[room.pickup.index].kind))
			case:
				name := carry.station_name(room.props.placed.items[room.pickup.index].kind)
				if carry.blueprint_pick_up(&room.blueprint, &room.props, room.pickup.index) {
					room.pickup = {}
					room_stock_changed(room)
					room_toast(room, "%v: aim at a counter and press place", name)
				}
			}
		}
	}
	carry.scale_aim(&room.scale, &room.props, carry.view_of(&room.player))
	if grab_pressed {
		action := carry.balloon_action(&game.loadout, &room.filler, &room.props)
		switch {
		case carry.oven_run_ready(&room.oven, &room.props):
			carry.oven_start(&room.oven, carry.flow_speed(&room.props))
			room_toast(room, "the oven is running")
		case action == .Paint:
			room.painting = true
			carry.paint_init(room.paint)
			paint_input_init(&room.paint_input, &pointers)
		case action != .None:
			room_balloon_action(room, &game.loadout, action)
		case carry.loadout_hands_full(&game.loadout):
			room_toast(room, "hands full: hang the balloon on a hook, clamp it at the paint station, or burn it")
		case carry.first_aid_use_ready(&room.first_aid, &room.props, &room.health):
			carry.first_aid_use(&room.first_aid, &room.health)
			room_toast(room, "patched up, back to full health")
		case carry.scale_zero_ready(&room.scale, &room.props):
			carry.scale_zero(&room.scale, &room.props)
			room_toast(room, "scale zeroed")
		case carry.soap_use_ready(&room.soap, &room.props):
			carry.soap_use(&room.soap)
		case room.props.held != -1:
			carry.release(&room.props)
		case:
			carry.grab(&room.props)
		}
	}
	carry.hands_update(&room.hands, carry.state_of(&room.props), dt)
	room.pour_target = carry.pour_target(&room.props)

	// Liquid: let out of a tap or over the lip of the held vessel, simulated, and
	// taken by the vessels it lands in.
	eye := carry.view_of(&room.player).eye
	speed := carry.flow_speed(&room.props)
	if pour_down && room.valve != -1 {
		if !carry.station_flow_to(&room.station, &room.stream, &room.layout, room.valve, dt, carry.tap_mouth(&room.props), true, speed) {
			room_toast(room, "that tap is locked")
		}
	} else if pour_down && room.spout {
		carry.oven_flow(&room.oven, &room.stream, &room.layout, dt, carry.tap_mouth(&room.props), speed)
	} else if pour_down && room.spout_rest != -1 {
		carry.oven_flow(&room.oven, &room.stream, &room.layout, dt, carry.oven_rest_mouth(&room.props, room.spout_rest), speed)
	} else if carry.filler_pour_ready(&room.filler, &room.props) {
		carry.pour_flow_to(&room.props, &room.stream, &room.layout, dt, carry.filler_mouth(), true)
	} else if carry.oven_pour_ready(&room.oven, &room.props) {
		carry.pour_flow_to(&room.props, &room.stream, &room.layout, dt, carry.oven_mouth(&room.oven), true)
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
	oven_events: [carry.MAX_EVENTS]carry.Oven_Event
	for i in 0 ..< carry.oven_capture(&room.stream, &room.oven, &oven_events) {
		room_oven_event(room, oven_events[i])
	}
	carry.stream_drain(&room.stream)
	room_oven_event(room, carry.oven_update(&room.oven, dt))
	room_oven_effects(room, dt)
	room_burn_effects(room, dt)
	carry.filler_update(&room.filler, dt)
	filler_view_update(&room.filler_view, &room.filler, dt)
	loadout_view_update(&room.loadout_view, &game.loadout, game.art, carry.view_of(&room.player), dt)
	room_heat_events(room, dt)
	carry.loadout_heat_update(&game.loadout, dt)
	room_steam(room, dt)
	effects.step(&room.fx, dt)
	game.heat_strength = room.fx.heat

	carry.health_update(&room.health, dt)
	carry.first_aid_update(&room.first_aid, dt)
	if carry.soap_update(&room.soap, dt) {
		room_toast(room, "hands washed")
	}
	carry.scale_update(&room.scale, &room.props)
	room.blast_flash *= 1 - min(dt * 4, 1)
	room.toast_timer = max(room.toast_timer - dt, 0)
	if carry.health_dead(&room.health) {
		room_reset(room)
		room_toast(room, "knocked out, the lab was reset")
	}
}

room_camera :: proc(room: ^Room) -> rl.Camera3D {
	if room.painting {
		return paint_camera(f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
	}
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
	if !room.painting {
		hands_draw(&room.meshes, room.mesh.material, placed[:count])
	}
	props_draw_caps(&room.meshes, room.mesh.material, &room.props)
	stream_draw(&room.stream, carry.view_of(&room.player), room.spill_shader, room.spill_ok)
	props_draw_liquids(&room.meshes, &room.props, camera.position)
	filler_view_draw(&room.filler_view, &room.filler, camera.position)
	room.loadout_view.paint.view.art_turn = room.paint_turn
	loadout_view_draw(&room.loadout_view, &game.loadout, camera.position, !room.painting)
	props_draw_glass(&room.meshes, room.mesh.material, &room.props, camera.position)
	stations_draw(&room.filler, &game.loadout)
	tablet_draw(&room.loadout_view, &game.loadout)
	oven_draw(&room.oven)
	blueprint_draw(&room.blueprint)
	forward := linalg_normalize(camera.target - camera.position)
	cam_right := linalg_normalize(linalg_cross(forward, {0, 1, 0}))
	cam_up := linalg_cross(cam_right, forward)
	effects_draw(&room.fx_view, &room.fx, cam_right, cam_up)
	rl.EndMode3D()
}

room_draw_ui :: proc(game: ^Game, state: rawptr) {
	room := cast(^Room)state
	w, h := f32(game.screen_w), f32(game.screen_h)
	if room.painting {
		draw_paint_ui(w, h, &room.loadout_view, &game.loadout, room.paint)
		return
	}
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
	lines := carry.focus(&room.props) != -1 ? 1 : 0
	if room.blueprint.active {
		draw_blueprint_readout(w, h, &room.blueprint, lines)
	} else if room.filler.aimed && room.pour_target == -1 {
		draw_filler_readout(w, h, &room.filler, lines)
	} else if room.oven.aimed && room.pour_target == -1 {
		draw_oven_readout(w, h, &room.oven, lines)
	} else if room.first_aid.aimed && room.pour_target == -1 {
		draw_first_aid_readout(w, h, &room.first_aid, &room.health, lines)
	} else if room.soap.aimed && room.pour_target == -1 {
		draw_soap_readout(w, h, &room.soap, lines)
	} else if room.pickup.aimed && room.pour_target == -1 && !room.scale.aimed {
		draw_pickup_readout(w, h, room.props.placed.items[room.pickup.index].kind, room.pickup.busy, lines)
	} else if room.pour_target == -1 && (room.scale.aimed || carry.scale_on(&room.props, room.props.aimed)) {
		grams, loaded := carry.scale_reading(&room.scale, &room.props)
		draw_scale_readout(w, h, grams, loaded, room.scale.tare > 0, lines)
	} else if room.pour_target == -1 {
		draw_spot_readout(w, h, &game.loadout, lines)
	}
	draw_carrying(w, h, game.loadout.hand)
	draw_health(w, h, room.health.hp)
	draw_toast(w, h, cstring(raw_data(room.toast[:])), room.toast_timer)
	action := carry.balloon_action(&game.loadout, &room.filler, &room.props)
	switch {
	case room.blueprint.active:
		draw_station_button(w, h, "place", room.blueprint.ok)
	case carry.oven_run_ready(&room.oven, &room.props):
		draw_run_button(w, h)
	case action != .None:
		draw_action_button(w, h, balloon_action_label(action))
	case carry.loadout_hands_full(&game.loadout):
		draw_full_button(w, h)
	case room.first_aid.aimed && room.props.held == -1:
		label, ready := first_aid_label(&room.first_aid, &room.health)
		draw_station_button(w, h, label, ready)
	case room.scale.aimed && room.props.held == -1:
		draw_station_button(w, h, "zero", carry.scale_zero_ready(&room.scale, &room.props))
	case room.soap.aimed && room.props.held == -1:
		label, ready := soap_label(&room.soap)
		draw_station_button(w, h, label, ready)
	case:
		draw_grab_button(w, h, state)
	}
	draw_jump_button(w, h, room.player.jump > 0)
	label: cstring = "pour"
	ready := false
	port_label: [16]u8
	switch {
	case room.blueprint.active:
		label, ready = "cancel", true
	case room.valve != -1 || room.spout || room.spout_rest != -1:
		label, ready = "fill", true
	case room.pour_target != -1:
		label, ready = "mix", true
	case carry.filler_pour_ready(&room.filler, &room.props):
		label, ready = "balloon", true
	case carry.oven_pour_ready(&room.oven, &room.props):
		text := fmt.bprintf(port_label[:15], "port %d", room.oven.aimed_port + 1)
		port_label[len(text)] = 0
		label, ready = cstring(raw_data(port_label[:])), true
	}
	draw_pour_button(w, h, label, ready, button_held(&room.controls, 4))
	draw_bench_button(w, h)
	draw_book_button(w, h)
	draw_speed_button(w, h, carry.flow_speed(&room.props))
	draw_arena_button(w, h)
	draw_bag_button(w, h, !room.blueprint.active)
	if room.blueprint.active {
		draw_book_nav(pickup_button(w, h), "rotate", true)
	} else {
		draw_book_nav(pickup_button(w, h), "pick up", carry.pickup_ready(&room.pickup, &room.props))
	}
	controls_draw(&room.controls, w, h)
	if room.menu_open {
		draw_book(w, h, room.menu_page)
	}
	if room.stock_open {
		draw_stock(w, h, &room.stock, &room.stock_ui, platform_mouse_position())
	}
}

linalg_normalize :: proc(v: Vec3) -> Vec3 {
	n := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	return n > 1e-6 ? v / n : v
}

linalg_cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}
