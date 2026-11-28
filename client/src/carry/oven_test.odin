// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "oven_test.odin"
// ============================================================================

package carry

import "../chemistry"
import "../lab"
import "core:testing"

STAND :: Vec3{3.0, 1.6, -6.9} // where a player stands to use the oven

// Puts a drop of `compound` carrying `ml` into the air at `at`.
drop_at :: proc(s: PourScene, at: Vec3, compound: u16, ml: f32) {
	stream_spawn_ml(s.st, s.l, at, {}, compound, ml)
}

over_port :: proc(i: int, up: f32) -> Vec3 {
	m := lab.mixer_port(i)
	return {m.x, m.y + up, m.z}
}

// A port holding `ml` of a compound at a purity, 1 unless the compound is water out of the tap.
port :: proc(compound: chemistry.Id, ml: f32, purity := f32(-1)) -> Port {
	return {u16(compound), ml, purity < 0 ? stock_purity(u16(compound)) : purity}
}

loaded_oven :: proc(a, b, c, d: Port) -> Oven {
	o: Oven
	oven_init(&o)
	o.ports = {a, b, c, d}
	return o
}

@(test)
a_port_blends_the_purity_of_what_goes_in :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	oven_init(&o)
	events: [MAX_EVENTS]Oven_Event
	stream_spawn_ml(s.st, s.l, over_port(0, 0.1), {}, id(.Ethanol), 3.375, 0.2)
	stream_spawn_ml(s.st, s.l, over_port(0, 0.15), {}, id(.Ethanol), 3.375, 0.6)
	oven_capture(s.st, &o, &events)
	testing.expect_value(t, o.ports[0].ml, f32(6.75))
	testing.expect(t, abs(o.ports[0].purity - 0.4) < 1e-4, "the mean by volume")
}

@(test)
a_port_takes_one_liquid_and_turns_other_liquids_away :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	oven_init(&o)
	events: [MAX_EVENTS]Oven_Event
	drop_at(s, over_port(0, 0.1), id(.Water), 3.375)
	drop_at(s, over_port(0, 0.15), id(.Water), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 0)
	testing.expect_value(t, o.ports[0].compound, id(.Water))
	testing.expect(t, abs(o.ports[0].ml - 6.75) < 1e-4, "both went in")
	testing.expect_value(t, s.st.sim.count, 0)

	drop_at(s, over_port(0, 0.1), id(.Ethanol), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 1)
	testing.expect_value(t, events[0].kind, Oven_Event_Kind.Refused)
	testing.expect_value(t, events[0].port, 0)
	testing.expect_value(t, events[0].compound, id(.Water))
	testing.expect_value(t, o.ports[0].compound, id(.Water))
	testing.expect(t, abs(o.ports[0].ml - 6.75) < 1e-4, "the port is as it was")
	testing.expect_value(t, s.st.sim.count, 0) // and the drop is gone

	drop_at(s, over_port(0, 0.1), id(.Ethanol), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 0) // told once, not at every drop
	testing.expect_value(t, s.st.sim.count, 0)
	oven_update(&o, REFUSED_GAP + 0.1)
	drop_at(s, over_port(0, 0.1), id(.Ethanol), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 1) // and again after a while
}

@(test)
each_port_has_its_own_funnel :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	oven_init(&o)
	events: [MAX_EVENTS]Oven_Event
	liquids := [lab.MIXER_PORTS]u16{id(.Water), 0, id(.Ethanol), id(.Sulfuric_Acid)}
	for i in 0 ..< lab.MIXER_PORTS {
		if liquids[i] != 0 {
			// One at a time: the liquid simulation box is set by the first drop, and
			// is not wide enough to hold the whole oven.
			drop_at(s, over_port(i, 0.1), liquids[i], 3.375)
			oven_capture(s.st, &o, &events)
		}
	}
	testing.expect_value(t, o.ports[0].compound, id(.Water))
	testing.expect_value(t, o.ports[1].ml, 0)
	testing.expect_value(t, o.ports[2].compound, id(.Ethanol))
	testing.expect_value(t, o.ports[3].compound, id(.Sulfuric_Acid))
	testing.expect_value(t, oven_loaded(&o), 3)
}

@(test)
a_full_port_loses_the_rest_and_only_drops_in_a_funnel_go_in :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	oven_init(&o)
	events: [MAX_EVENTS]Oven_Event
	o.ports[1] = port(.Water, PORT_CAPACITY - 2)
	drop_at(s, over_port(1, 0.1), id(.Water), 10)
	oven_capture(s.st, &o, &events)
	testing.expect_value(t, o.ports[1].ml, PORT_CAPACITY)

	m := lab.mixer_port(2)
	drop_at(s, {m.x + 0.2, m.y + 0.1, m.z}, id(.Water), 3.375) // beside the funnel
	drop_at(s, {m.x, lab.MIXER_TOP + lab.MIXER_CAPTURE_ABOVE + 0.1, m.z}, id(.Water), 3.375) // far above it
	oven_capture(s.st, &o, &events)
	testing.expect_value(t, o.ports[2].ml, 0)
	testing.expect_value(t, s.st.sim.count, 2)
}

@(test)
a_closed_oven_takes_nothing :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o := loaded_oven(port(.Water, 100), {}, {}, {})
	oven_start(&o, 1)
	events: [MAX_EVENTS]Oven_Event
	drop_at(s, over_port(1, 0.1), id(.Water), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 0)
	testing.expect_value(t, s.st.sim.count, 1)
	testing.expect_value(t, o.ports[1].ml, 0)
}

@(test)
a_run_needs_something_in_a_port_and_an_empty_tank :: proc(t: ^testing.T) {
	o: Oven
	oven_init(&o)
	testing.expect(t, !oven_can_run(&o), "nothing loaded")
	testing.expect(t, !oven_start(&o, 1), "so it will not start")
	o.ports[3] = port(.Water, 50)
	testing.expect(t, oven_can_run(&o), "something loaded")
	fill_with(&o.tank, id(.Ethyl_Acetate), 10)
	testing.expect(t, !oven_can_run(&o), "the tank still holds a product")
	o.tank = {}
	testing.expect(t, oven_start(&o, 1), "it starts")
	testing.expect_value(t, o.state, Oven_State.Running)
	testing.expect(t, !oven_can_run(&o), "and cannot start twice")
}

@(test)
a_run_takes_its_time_and_makes_the_product :: proc(t: ^testing.T) {
	o := loaded_oven(port(.Water, 450), port(.Sulfuric_Acid, 50), {}, {})
	oven_start(&o, 1)
	testing.expect_value(t, oven_progress(&o), 0)
	testing.expect_value(t, oven_update(&o, OVEN_RUN_TIME - 0.1).kind, Oven_Event_Kind.Nothing)
	testing.expect(t, oven_progress(&o) > 0.95 && oven_progress(&o) < 1, "nearly there")
	e := oven_update(&o, 0.2)
	testing.expect_value(t, e.kind, Oven_Event_Kind.Finished)
	testing.expect_value(t, e.compound, id(.Dilute_Sulfuric_Acid))
	testing.expect_value(t, e.ml, 500)
	testing.expect_value(t, main_of(&o.tank), id(.Dilute_Sulfuric_Acid))
	testing.expect_value(t, ml_of(&o.tank), 500)
	testing.expect_value(t, oven_loaded(&o), 0)
	testing.expect_value(t, o.state, Oven_State.Idle)
	testing.expect_value(t, oven_progress(&o), 0)
}

@(test)
a_violent_mix_is_safe_in_the_oven_and_gives_its_product :: proc(t: ^testing.T) {
	// Water into the acid, which is a splash in a vessel.
	o := loaded_oven(port(.Sulfuric_Acid, 50), port(.Water, 450), {}, {})
	oven_start(&o, 1)
	e := oven_update(&o, OVEN_RUN_TIME + 0.1)
	testing.expect_value(t, e.kind, Oven_Event_Kind.Finished)
	testing.expect_value(t, e.volatility, f32(0.45))
	testing.expect_value(t, o.tank.count, 2)
	testing.expect_value(t, ml_of(&o.tank), 500) // none of it lost
}

@(test)
the_ports_are_mixed_in_order :: proc(t: ^testing.T) {
	good := loaded_oven(port(.Water, 450), port(.Sulfuric_Acid, 50), {}, {})
	made, calm := oven_fold(&good)
	testing.expect_value(t, calm, 0)
	testing.expect_value(t, made.count, 1)
	testing.expect_value(t, made.items[0].compound, chemistry.Id.Dilute_Sulfuric_Acid)
	wrong := loaded_oven(port(.Sulfuric_Acid, 50), port(.Water, 450), {}, {})
	spat, volatility := oven_fold(&wrong)
	testing.expect_value(t, volatility, f32(0.45))
	testing.expect_value(t, spat.count, 2) // the same ports in another order do not make the acid
}

@(test)
the_same_liquid_in_two_ports_adds_up_and_one_port_moves_over :: proc(t: ^testing.T) {
	o := loaded_oven(port(.Water, 100), {}, port(.Water, 120), {})
	made, volatility := oven_fold(&o)
	testing.expect_value(t, main_of(&made), id(.Water))
	testing.expect_value(t, ml_of(&made), 220)
	testing.expect_value(t, volatility, 0)

	single := loaded_oven({}, {}, port(.Acetic_Acid, 75), {})
	one, _ := oven_fold(&single)
	testing.expect_value(t, main_of(&one), id(.Acetic_Acid))
	testing.expect_value(t, ml_of(&one), 75)
}

@(test)
speed_shortens_a_run :: proc(t: ^testing.T) {
	o := loaded_oven(port(.Water, 100), {}, {}, {})
	oven_start(&o, 4)
	testing.expect_value(t, oven_update(&o, OVEN_RUN_TIME / 4 - 0.1).kind, Oven_Event_Kind.Nothing)
	testing.expect_value(t, oven_update(&o, 0.2).kind, Oven_Event_Kind.Finished)
}

// ---- aiming ----

@(test)
the_crosshair_finds_the_oven_and_the_port_it_points_at :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	o: Oven
	oven_init(&o)
	p.x, p.z = STAND.x, STAND.z
	for i in 0 ..< lab.MIXER_PORTS {
		look_at(p, lab.mixer_port(i))
		testing.expect(t, oven_aim(&o, props, view_of(p)), "looking at a port")
		testing.expect_value(t, o.aimed_port, i)
		testing.expect(t, o.aimed_t < POUR_REACH, "close enough to pour")
	}
	look_at(p, {0, 1.6, 0})
	testing.expect(t, !oven_aim(&o, props, view_of(p)), "looking away")
	testing.expect_value(t, o.aimed_port, -1)
	p.z = -3.0
	look_at(p, lab.mixer_port(1))
	testing.expect(t, !oven_aim(&o, props, view_of(p)), "too far")
	p.z = STAND.z
	look_at(p, lab.mixer_port(1))
	props.aimed, props.aimed_t = 0, 0.2
	testing.expect(t, !oven_aim(&o, props, view_of(p)), "a nearer vessel wins")
}

@(test)
the_buttons_are_ready_for_the_oven_only_when_they_should_be :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	o := loaded_oven(port(.Water, 100), {}, {}, {})
	o.aimed, o.aimed_t = true, 0.8
	testing.expect(t, oven_run_ready(&o, props), "nothing held, the oven aimed at, something loaded")
	testing.expect(t, !oven_pour_ready(&o, props), "nothing to pour")

	props_add(props, l, .Beaker, 0, 0.9, id(.Water), 200)
	props.held = 0
	testing.expect(t, !oven_run_ready(&o, props), "hands are full")
	testing.expect(t, oven_pour_ready(&o, props), "a vessel to pour")
	o.aimed_t = POUR_REACH + 0.2
	testing.expect(t, !oven_pour_ready(&o, props), "too far")
	o.aimed_t = 0.8
	props.held = -1

	fill_with(&o.tank, id(.Ethyl_Acetate), 10)
	testing.expect(t, !oven_run_ready(&o, props), "a product waits in the tank")
	o.tank = {}
	o.aimed = false
	testing.expect(t, !oven_run_ready(&o, props), "not aimed at")
	o.aimed = true
	oven_start(&o, 1)
	testing.expect(t, !oven_run_ready(&o, props), "already running")
	props.held = 0
	testing.expect(t, !oven_pour_ready(&o, props), "the ports are shut")
}

// ---- the spout ----

@(test)
a_vessel_is_found_at_the_spout_only_when_there_is_product :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Beaker, 0, 0)
	props.held = 0
	n := lab.MIXER_SPOUT
	under := n.y - 0.2 - kind_dims(.Beaker).height
	place :: proc(props: ^Props, x, y, z: f32) {
		props.items[0].pos = {x, y, z}
	}
	o: Oven
	oven_init(&o)
	place(props, n.x, under, n.z)
	testing.expect(t, !oven_spout_under(&o, props), "no product")
	fill_with(&o.tank, id(.Ethyl_Acetate), 100)
	testing.expect(t, oven_spout_under(&o, props), "under the spout")
	place(props, n.x + 0.3, under, n.z)
	testing.expect(t, oven_spout_under(&o, props), "a little to the side")
	place(props, n.x + 0.7, under, n.z)
	testing.expect(t, !oven_spout_under(&o, props), "too far to the side")
	place(props, n.x, n.y - 1.4, n.z)
	testing.expect(t, !oven_spout_under(&o, props), "far below")
	place(props, n.x, under, n.z)
	props.items[0].tilt = 0.8
	testing.expect(t, !oven_spout_under(&o, props), "tipped over")
	props.items[0].tilt = 0
	fill_with(&props.items[0].mix, id(.Water), capacity_ml(.Beaker))
	testing.expect(t, !oven_spout_under(&o, props), "already full")
	fill_with(&props.items[0].mix, 0, 0)
	props.held = -1
	testing.expect(t, !oven_spout_under(&o, props), "nothing held")
}

// Runs the spout into the held vessel for `frames` frames at `speed`, and returns
// the milliliters the vessel holds and what is still in the air.
run_spout :: proc(s: PourScene, o: ^Oven, frames: int, speed: f32) -> (in_vessel, in_air: f32) {
	events: [MAX_EVENTS]Mix_Result
	for _ in 0 ..< frames {
		oven_flow(o, s.st, s.l, 1.0 / 60, tap_mouth(s.props), speed)
		stream_step(s.st, 21)
		stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	}
	for i in 0 ..< s.st.sim.count {
		in_air += s.st.ml[i]
	}
	return ml_of(&s.props.items[0].mix), in_air
}

held_beaker_at_the_spout :: proc(s: PourScene, aside: f32) {
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 0, 0, 0, 0)
	s.props.held = 0
	n := lab.MIXER_SPOUT
	s.props.items[0].pos = {n.x + aside, n.y - 0.2 - kind_dims(.Beaker).height, n.z}
}

@(test)
the_spout_fills_a_vessel_with_the_product :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	held_beaker_at_the_spout(s, 0.3) // off to one side, as a hand will be
	o: Oven
	oven_init(&o)
	fill_with(&o.tank, id(.Ethanol), 300)
	got, air := run_spout(s, &o, 420, 1)
	testing.expect_value(t, main_of(&s.props.items[0].mix), id(.Ethanol))
	testing.expectf(t, got > 280, "the vessel holds %v ml", got)
	testing.expect(t, got + air + ml_of(&o.tank) <= 300.01, "nothing was made from nothing")
	testing.expect_value(t, ml_of(&o.tank), 0)
	testing.expect_value(t, main_of(&o.tank), 0) // an empty tank holds no liquid
}

@(test)
a_faster_spout_empties_the_tank_sooner_with_bigger_drops :: proc(t: ^testing.T) {
	slow, fast := pour_scene(), pour_scene()
	defer free_pour_scene(slow)
	defer free_pour_scene(fast)
	held_beaker_at_the_spout(slow, 0)
	held_beaker_at_the_spout(fast, 0)
	a, b: Oven
	oven_init(&a)
	oven_init(&b)
	fill_with(&a.tank, id(.Water), 800)
	fill_with(&b.tank, id(.Water), 800)
	run_spout(slow, &a, 120, 1)
	run_spout(fast, &b, 2, 8) // the first frame only gathers a drop's worth
	biggest := f32(0)
	for i in 0 ..< fast.st.sim.count {
		biggest = max(biggest, fast.st.ml[i])
	}
	testing.expect_value(t, biggest, DROP_ML * 8) // each drop carries eight times as much
	run_spout(fast, &b, 118, 8)
	let_out := 800 - ml_of(&a.tank)
	testing.expect(t, let_out > 190 && let_out < 250, "two seconds at normal speed")
	testing.expect_value(t, ml_of(&b.tank), 0) // eight times as fast is done
	testing.expect(t, fast.st.sim.count <= MAX_STREAM, "and no more drops in flight than before")
}

@(test)
a_vessel_standing_on_the_tray_is_found_and_filled_without_being_held :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	o: Oven
	oven_init(&o)
	n := lab.MIXER_SPOUT
	props_add(props, l, .Beaker, n.x, n.z, 0, 0)
	testing.expect_value(t, oven_rest_under(&o, props), -1) // no product
	fill_with(&o.tank, id(.Ethyl_Acetate), 100)
	testing.expect_value(t, oven_rest_under(&o, props), 0)
	props.items[0].pos.x = n.x + lab.MIXER_TRAY_RADIUS + 0.05
	testing.expect_value(t, oven_rest_under(&o, props), -1) // off the tray
	props.items[0].pos.x = n.x
	props.items[0].pos.y = lab.COUNTER_HEIGHT + 0.4
	testing.expect_value(t, oven_rest_under(&o, props), -1) // in the air
	props.items[0].pos.y = lab.COUNTER_HEIGHT
	props.items[0].tilt = 0.8
	testing.expect_value(t, oven_rest_under(&o, props), -1) // tipped over
	props.items[0].tilt = 0
	fill_with(&props.items[0].mix, id(.Water), capacity_ml(.Beaker))
	testing.expect_value(t, oven_rest_under(&o, props), -1) // full
	fill_with(&props.items[0].mix, 0, 0)
	props.held = 0
	testing.expect_value(t, oven_rest_under(&o, props), -1) // held ones are the other case
	props.held = -1
	props_add(props, l, .Flask, n.x + 0.05, n.z, 0, 0)
	testing.expect(t, oven_rest_under(&o, props) != -1, "one of the two")
}

@(test)
the_spout_fills_a_vessel_standing_on_the_tray :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	props_init(s.props)
	n := lab.MIXER_SPOUT
	props_add(s.props, s.l, .Beaker, n.x, n.z, 0, 0)
	o: Oven
	oven_init(&o)
	fill_with(&o.tank, id(.Acetic_Acid), 300)
	events: [MAX_EVENTS]Mix_Result
	for _ in 0 ..< 420 {
		if i := oven_rest_under(&o, s.props); i != -1 {
			oven_flow(&o, s.st, s.l, 1.0 / 60, oven_rest_mouth(s.props, i), 1)
		}
		stream_step(s.st, 21)
		stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	}
	testing.expect_value(t, main_of(&s.props.items[0].mix), id(.Acetic_Acid))
	testing.expectf(t, ml_of(&s.props.items[0].mix) > 280, "the vessel on the tray holds %v ml", ml_of(&s.props.items[0].mix))
	testing.expect_value(t, ml_of(&o.tank), 0)
}

// ---- the oven where it stands ----

// The oven turned so that its front looks east, on the west counter, as it stands when it has been moved there.
moved_oven :: proc() -> Oven {
	o: Oven
	oven_init(&o)
	o.at = lab.Placement{.Oven, -11.63, -1.5, 3}
	return o
}

// Puts one drop of ethanol into the air at `at` in a stream of its own, so that the place of the first drop does not
// decide where the others may be, and gives how much of it the ports took.
oven_takes_a_drop_at :: proc(t: ^testing.T, o: ^Oven, at: Vec3) -> f32 {
	s := pour_scene()
	defer free_pour_scene(s)
	testing.expect(t, stream_spawn_ml(s.st, s.l, at, {}, id(.Ethanol), 3.375), "the drop is in the air")
	events: [MAX_EVENTS]Oven_Event
	total :: proc(o: ^Oven) -> f32 {
		sum := f32(0)
		for port in o.ports {
			sum += port.ml
		}
		return sum
	}
	before := total(o)
	oven_capture(s.st, o, &events)
	return total(o) - before
}

@(test)
an_oven_that_has_been_moved_takes_drops_at_its_new_ports_and_not_the_old :: proc(t: ^testing.T) {
	o := moved_oven()
	for i in 0 ..< lab.MIXER_PORTS {
		m := lab.mixer_port_at(o.at, i)
		testing.expect_value(t, oven_takes_a_drop_at(t, &o, {m.x, m.y + 0.1, m.z}), f32(3.375))
		testing.expect_value(t, o.ports[i].ml, f32(3.375))
	}
	// Over where the ports were made, there is nothing now.
	testing.expect_value(t, oven_takes_a_drop_at(t, &o, over_port(2, 0.1)), f32(0))
	// An oven that has been picked up takes nothing, wherever the drop is.
	o.standing = false
	m := lab.mixer_port_at(o.at, 1)
	testing.expect_value(t, oven_takes_a_drop_at(t, &o, {m.x, m.y + 0.1, m.z}), f32(0))
	// And one that starts takes them where it starts.
	g: Oven
	oven_init(&g)
	testing.expect_value(t, g.at, lab.OVEN_START)
	testing.expect(t, g.standing, "a new one stands")
	testing.expect_value(t, oven_takes_a_drop_at(t, &g, over_port(0, 0.1)), f32(3.375))
}

@(test)
an_oven_that_has_been_moved_is_aimed_at_where_it_stands_and_says_which_port :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	o := moved_oven()
	for port in 0 ..< lab.MIXER_PORTS {
		m := lab.mixer_port_at(o.at, port)
		view := view_toward({-10.4, 1.6, m.z}, {m.x, 1.3, m.z})
		testing.expectf(t, oven_aim(&o, props, view), "looking at port %d from the east", port)
		testing.expect_value(t, o.aimed_port, port)
		mouth := oven_mouth(&o)
		testing.expectf(t, abs(mouth.x - m.x) < 0.001 && abs(mouth.z - m.z) < 0.001 && mouth.y > m.y, "the pour is aimed over port %d", port)
	}
	// Not where it was made.
	testing.expect(t, !oven_aim(&o, props, view_toward({3.0, 1.6, -6.6}, {3.0, 1.3, -7.63})), "nothing at the old place")
	// Not when it does not stand.
	o.standing = false
	m := lab.mixer_port_at(o.at, 1)
	testing.expect(t, !oven_aim(&o, props, view_toward({-10.4, 1.6, m.z}, {m.x, 1.3, m.z})), "nothing where it stood once it is gone")
}

@(test)
the_spout_of_a_moved_oven_fills_a_vessel_under_it_or_standing_on_its_tray :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Beaker, 0, 0)
	props.held = 0
	o := moved_oven()
	fill_with(&o.tank, id(.Ethyl_Acetate), 100)
	n := lab.mixer_spout_at(o.at)
	testing.expect(t, abs(n.x - -11.63) < 0.001 && abs(n.z - (-1.5 + 1.02 * -1)) < 0.001 || abs(n.z - (-1.5 + 1.02)) < 0.001, "the spout is off the end of the oven")
	under := n.y - 0.2 - kind_dims(.Beaker).height
	props.items[0].pos = {n.x, under, n.z}
	testing.expect(t, oven_spout_under(&o, props), "under the new spout")
	props.items[0].pos = {lab.MIXER_SPOUT.x, under, lab.MIXER_SPOUT.z}
	testing.expect(t, !oven_spout_under(&o, props), "not under the old one")
	// Standing on the tray, not held.
	props.held = -1
	props.items[0].pos = {n.x, lab.COUNTER_HEIGHT + 0.01, n.z}
	testing.expect_value(t, oven_rest_under(&o, props), 0)
	props.items[0].pos = {lab.MIXER_SPOUT.x, lab.COUNTER_HEIGHT + 0.01, lab.MIXER_SPOUT.z}
	testing.expect_value(t, oven_rest_under(&o, props), -1)
	// The product leaves the spout of the oven where it stands.
	s := pour_scene()
	defer free_pour_scene(s)
	oven_flow(&o, s.st, s.l, 0.1, n + Vec3{0, -0.5, 0}, 1)
	testing.expect(t, s.st.sim.count > 0, "a drop left the spout")
	first := stream_position(s.st, 0)
	testing.expect(t, abs(first.x - n.x) < 0.1 && abs(first.z - n.z) < 0.1 && abs(first.y - n.y) < 0.1, "at the tip of the new spout")
	// An oven that has been picked up has no spout.
	o.standing = false
	props.items[0].pos = {n.x, lab.COUNTER_HEIGHT + 0.01, n.z}
	testing.expect_value(t, oven_rest_under(&o, props), -1)
	props.held = 0
	props.items[0].pos = {n.x, under, n.z}
	testing.expect(t, !oven_spout_under(&o, props), "and nothing under it")
}

@(test)
the_oven_is_found_among_the_stations_and_keeps_what_is_in_it_when_it_is_picked_up :: proc(t: ^testing.T) {
	placed := lab.default_placed()
	o: Oven
	oven_init(&o)
	o.ports[1] = port(.Ethanol, 40)
	fill_with(&o.tank, id(.Ethyl_Acetate), 100)
	oven_sync(&o, &placed)
	testing.expect(t, o.standing && o.at == lab.OVEN_START, "it stands where it starts")
	for i in 0 ..< placed.count {
		if placed.items[i].kind == .Oven {
			placed.items[i] = {.Oven, -11.63, -1.5, 3}
		}
	}
	oven_sync(&o, &placed)
	testing.expect_value(t, o.at, lab.Placement{.Oven, -11.63, -1.5, 3})
	for i in 0 ..< placed.count {
		if placed.items[i].kind == .Oven {
			lab.placed_remove(&placed, i)
			break
		}
	}
	oven_sync(&o, &placed)
	testing.expect(t, !o.standing, "picked up")
	testing.expect_value(t, o.ports[1].ml, f32(40))
	testing.expect_value(t, ml_of(&o.tank), f32(100))
	lab.placed_add(&placed, {.Oven, 3.0, -7.63, 0})
	oven_sync(&o, &placed)
	testing.expect(t, o.standing && o.ports[1].ml == 40 && ml_of(&o.tank) == 100, "put down again with what it held")
}
