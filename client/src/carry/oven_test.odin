// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "oven_test.odin"
// ============================================================================

package carry

import "../chem"
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

loaded_oven :: proc(a, b, c, d: Port) -> Oven {
	o: Oven
	oven_init(&o)
	o.ports = {a, b, c, d}
	return o
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

	drop_at(s, over_port(0, 0.1), id(.Fizz_Acid), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 1)
	testing.expect_value(t, events[0].kind, Oven_Event_Kind.Refused)
	testing.expect_value(t, events[0].port, 0)
	testing.expect_value(t, events[0].compound, id(.Water))
	testing.expect_value(t, o.ports[0].compound, id(.Water))
	testing.expect(t, abs(o.ports[0].ml - 6.75) < 1e-4, "the port is as it was")
	testing.expect_value(t, s.st.sim.count, 0) // and the drop is gone

	drop_at(s, over_port(0, 0.1), id(.Fizz_Acid), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 0) // told once, not at every drop
	testing.expect_value(t, s.st.sim.count, 0)
	oven_update(&o, REFUSED_GAP + 0.1)
	drop_at(s, over_port(0, 0.1), id(.Fizz_Acid), 3.375)
	testing.expect_value(t, oven_capture(s.st, &o, &events), 1) // and again after a while
}

@(test)
each_port_has_its_own_funnel :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	oven_init(&o)
	events: [MAX_EVENTS]Oven_Event
	liquids := [lab.MIXER_PORTS]u16{id(.Water), 0, id(.Fizz_Acid), id(.Spark_Blue)}
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
	testing.expect_value(t, o.ports[2].compound, id(.Fizz_Acid))
	testing.expect_value(t, o.ports[3].compound, id(.Spark_Blue))
	testing.expect_value(t, oven_loaded(&o), 3)
}

@(test)
a_full_port_loses_the_rest_and_only_drops_in_a_funnel_go_in :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	o: Oven
	oven_init(&o)
	events: [MAX_EVENTS]Oven_Event
	o.ports[1] = {id(.Water), PORT_CAPACITY - 2}
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
	o := loaded_oven({id(.Water), 100}, {}, {}, {})
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
	o.ports[3] = {id(.Water), 50}
	testing.expect(t, oven_can_run(&o), "something loaded")
	o.tank = {id(.Slurry), 10}
	testing.expect(t, !oven_can_run(&o), "the tank still holds a product")
	o.tank = {}
	testing.expect(t, oven_start(&o, 1), "it starts")
	testing.expect_value(t, o.state, Oven_State.Running)
	testing.expect(t, !oven_can_run(&o), "and cannot start twice")
}

@(test)
a_run_takes_its_time_and_makes_the_product :: proc(t: ^testing.T) {
	o := loaded_oven({id(.Soda_Base), 200}, {id(.Fizz_Acid), 100}, {}, {})
	oven_start(&o, 1)
	testing.expect_value(t, oven_progress(&o), 0)
	testing.expect_value(t, oven_update(&o, OVEN_RUN_TIME - 0.1).kind, Oven_Event_Kind.Nothing)
	testing.expect(t, oven_progress(&o) > 0.95 && oven_progress(&o) < 1, "nearly there")
	e := oven_update(&o, 0.2)
	product := chem.react(id(.Soda_Base), id(.Fizz_Acid)).product
	testing.expect_value(t, e.kind, Oven_Event_Kind.Finished)
	testing.expect_value(t, e.compound, product)
	testing.expect_value(t, e.ml, 300)
	testing.expect_value(t, o.tank.compound, product)
	testing.expect_value(t, o.tank.ml, 300)
	testing.expect_value(t, oven_loaded(&o), 0)
	testing.expect_value(t, o.state, Oven_State.Idle)
	testing.expect_value(t, oven_progress(&o), 0)
}

@(test)
a_violent_mix_is_safe_in_the_oven_and_gives_its_product :: proc(t: ^testing.T) {
	o := loaded_oven({id(.Ember_Oil), 300}, {id(.Spark_Blue), 100}, {}, {})
	outcome := chem.react(id(.Ember_Oil), id(.Spark_Blue))
	testing.expect_value(t, chem.hazard_of(outcome.volatility), chem.Hazard.Blast) // in a vessel this is a blast
	oven_start(&o, 1)
	e := oven_update(&o, OVEN_RUN_TIME + 0.1)
	testing.expect_value(t, e.kind, Oven_Event_Kind.Finished)
	testing.expect_value(t, e.volatility, outcome.volatility)
	testing.expect_value(t, o.tank.compound, outcome.product)
	testing.expect_value(t, o.tank.ml, 400) // none of it lost
}

@(test)
the_ports_are_mixed_in_order :: proc(t: ^testing.T) {
	o := loaded_oven({id(.Soda_Base), 100}, {id(.Fizz_Acid), 100}, {}, {id(.Dye_Red), 50})
	compound, ml, _ := oven_fold(&o)
	step1 := chem.react(id(.Soda_Base), id(.Fizz_Acid)).product
	step2 := chem.react(step1, id(.Dye_Red)).product
	testing.expect_value(t, compound, step2)
	testing.expect_value(t, ml, 250)
}

@(test)
the_same_liquid_in_two_ports_adds_up_and_one_port_moves_over :: proc(t: ^testing.T) {
	o := loaded_oven({id(.Water), 100}, {}, {id(.Water), 120}, {})
	compound, ml, volatility := oven_fold(&o)
	testing.expect_value(t, compound, id(.Water))
	testing.expect_value(t, ml, 220)
	testing.expect_value(t, volatility, 0)

	single := loaded_oven({}, {}, {id(.Frost_Gel), 75}, {})
	compound, ml, _ = oven_fold(&single)
	testing.expect_value(t, compound, id(.Frost_Gel))
	testing.expect_value(t, ml, 75)
}

@(test)
speed_shortens_a_run :: proc(t: ^testing.T) {
	o := loaded_oven({id(.Water), 100}, {}, {}, {})
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
	o := loaded_oven({id(.Water), 100}, {}, {}, {})
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

	o.tank = {id(.Slurry), 10}
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
	o.tank = {id(.Slurry), 100}
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
	props.items[0].compound, props.items[0].ml = id(.Water), capacity_ml(.Beaker)
	testing.expect(t, !oven_spout_under(&o, props), "already full")
	props.items[0].compound, props.items[0].ml = 0, 0
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
	return s.props.items[0].ml, in_air
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
	o.tank = {id(.Fizz_Acid), 300}
	got, air := run_spout(s, &o, 420, 1)
	testing.expect_value(t, s.props.items[0].compound, id(.Fizz_Acid))
	testing.expectf(t, got > 280, "the vessel holds %v ml", got)
	testing.expect(t, got + air + o.tank.ml <= 300.01, "nothing was made from nothing")
	testing.expect_value(t, o.tank.ml, 0)
	testing.expect_value(t, o.tank.compound, 0) // an empty tank holds no liquid
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
	a.tank = {id(.Water), 800}
	b.tank = {id(.Water), 800}
	run_spout(slow, &a, 120, 1)
	run_spout(fast, &b, 2, 8) // the first frame only gathers a drop's worth
	biggest := f32(0)
	for i in 0 ..< fast.st.sim.count {
		biggest = max(biggest, fast.st.ml[i])
	}
	testing.expect_value(t, biggest, DROP_ML * 8) // each drop carries eight times as much
	run_spout(fast, &b, 118, 8)
	let_out := 800 - a.tank.ml
	testing.expect(t, let_out > 190 && let_out < 250, "two seconds at normal speed")
	testing.expect_value(t, b.tank.ml, 0) // eight times as fast is done
	testing.expect(t, fast.st.sim.count <= MAX_STREAM, "and no more drops in flight than before")
}
