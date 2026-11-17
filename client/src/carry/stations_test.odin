// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stations_test.odin"
// ============================================================================

package carry

import "../chem"
import "../chemistry"
import "../lab"
import "core:testing"

EYE :: Vec3{6.0, 1.6, 6.9} // where a player stands to use the fill station

fresh_filler :: proc() -> Filler {
	f: Filler
	filler_init(&f)
	return f
}

id :: proc(i: chemistry.Id) -> u16 {
	return u16(i)
}

// Makes a mixture that bursts at the next drop of water: spirit and the two acids, equal parts, at 160 degrees,
// hotter than the four of them can be together. `each` is how many millilitres of each.
burst_mix :: proc(m: ^chemistry.Mixture, each: f32) {
	m^ = {}
	chemistry.mix_add(m, .Ethanol, each, 1, 160)
	chemistry.mix_add(m, .Acetic_Acid, each, 1, 160)
	chemistry.mix_add(m, .Sulfuric_Acid, each, 1, 160)
}

// Drops of one liquid, `count` of them, into the balloon. Returns the results that
// were worth telling.
drip :: proc(f: ^Filler, compound: u16, count: int) -> [dynamic]Fill_Result {
	found: [dynamic]Fill_Result
	for _ in 0 ..< count {
		r := filler_take_drop(f, compound, DROP_ML, EYE)
		if r.mix.kind != .Nothing || r.popped {
			append(&found, r)
		}
	}
	return found
}

@(test)
a_balloon_takes_drops_of_one_liquid :: proc(t: ^testing.T) {
	f := fresh_filler()
	found := drip(&f, id(.Water), 100)
	defer delete(found)
	testing.expect_value(t, len(found), 0)
	testing.expect_value(t, main_of(&f.mix), id(.Water))
	testing.expect(t, abs(ml_of(&f.mix) - 100 * DROP_ML) < 0.01, "all of it stays")
	testing.expect_value(t, f.generation, 1)
	testing.expect(t, abs(fill_ratio(&f) - ml_of(&f.mix) / BALLOON_REST_ML) < 1e-6, "the ratio is the share of the rest volume")
}

@(test)
a_pour_into_a_balloon_with_another_liquid_is_one_meeting :: proc(t: ^testing.T) {
	f := fresh_filler()
	fill_with(&f.mix, id(.Ethanol), 200)
	found := drip(&f, id(.Water), 60)
	defer delete(found)
	testing.expect_value(t, len(found), 1) // only the drop that makes it the mix the reaction wants starts it
	testing.expect_value(t, found[0].mix.kind, Mix_Kind.Mixed)
	testing.expect_value(t, f.mix.count, 2)
	testing.expect(t, abs(ml_of(&f.mix) - (200 + 60 * DROP_ML)) < 0.01, "later drops join it as it is")
	testing.expect(t, f.mix.heat_c < ROOM_C + 2.5, "and it warmed once, not with every drop")
	testing.expect(t, f.present, "a calm mix leaves the balloon")
}

@(test)
a_blast_bursts_the_balloon_and_it_is_replaced :: proc(t: ^testing.T) {
	f := fresh_filler()
	burst_mix(&f.mix, 100)
	r := filler_take_drop(&f, id(.Water), 100, EYE, 160)
	testing.expect_value(t, r.mix.kind, Mix_Kind.Blast)
	testing.expect_value(t, r.lost, id(.Diethyl_Ether))
	testing.expect(t, r.mix.damage > 0, "it hurts")
	testing.expect(t, !f.present, "the balloon is gone")
	testing.expect_value(t, ml_of(&f.mix), 0)
	testing.expect_value(t, main_of(&f.mix), 0)

	again := filler_take_drop(&f, id(.Water), DROP_ML, EYE)
	testing.expect_value(t, again.mix.kind, Mix_Kind.Nothing)
	testing.expect_value(t, ml_of(&f.mix), 0) // a drop with no balloon is lost

	filler_update(&f, FILLER_RESPAWN - 0.1)
	testing.expect(t, !f.present, "not yet")
	filler_update(&f, 0.2)
	testing.expect(t, f.present, "a fresh balloon")
	testing.expect_value(t, f.generation, 2)
	testing.expect_value(t, ml_of(&f.mix), 0)
}

@(test)
overfilling_bursts_the_balloon_at_the_limit :: proc(t: ^testing.T) {
	f := fresh_filler()
	pops := 0
	most := f32(0)
	drops := 0
	for drops < 600 && f.present {
		r := filler_take_drop(&f, id(.Water), DROP_ML, EYE)
		drops += 1
		if r.popped {
			pops += 1
			testing.expect_value(t, r.lost, id(.Water))
		} else {
			most = max(most, ml_of(&f.mix))
		}
	}
	testing.expect_value(t, pops, 1)
	testing.expect(t, !f.present, "the balloon is lost")
	testing.expect_value(t, ml_of(&f.mix), 0)
	testing.expect(t, most < BALLOON_POP_ML, "it held up to the limit")
	testing.expect(t, most > BALLOON_POP_ML - 2 * DROP_ML, "and burst on the first drop over it")
	testing.expect(t, drops <= int(BALLOON_POP_ML / DROP_ML) + 1, "no more than a drop past")
}

@(test)
strain_runs_from_a_full_balloon_to_the_limit :: proc(t: ^testing.T) {
	f := fresh_filler()
	fill_with(&f.mix, id(.Water), BALLOON_REST_ML * 0.5)
	testing.expect_value(t, strain(&f), 0)
	fill_with(&f.mix, id(.Water), BALLOON_REST_ML)
	testing.expect_value(t, strain(&f), 0)
	fill_with(&f.mix, id(.Water), BALLOON_REST_ML * (1 + (BALLOON_POP_AT - 1) * 0.5))
	testing.expect(t, abs(strain(&f) - 0.5) < 1e-4, "halfway")
	fill_with(&f.mix, id(.Water), BALLOON_POP_ML)
	testing.expect(t, abs(strain(&f) - 1) < 1e-4, "at the limit")
	f.present = false
	testing.expect_value(t, strain(&f), 0)
	testing.expect_value(t, fill_ratio(&f), 0)
}

@(test)
a_spatter_in_the_balloon_loses_a_fifth :: proc(t: ^testing.T) {
	f := fresh_filler()
	fill_with(&f.mix, id(.Sulfuric_Acid), 100)
	r := filler_take_drop(&f, id(.Water), 900, EYE) // water into acid
	testing.expect_value(t, r.mix.kind, Mix_Kind.Spatter)
	testing.expect(t, f.present, "it survives a spatter")
	testing.expect(t, abs(ml_of(&f.mix) - 1000 * (1 - chem.SPATTER_LOSS)) < 0.01, "a fifth is thrown out")
}

@(test)
the_station_says_where_a_reaction_was :: proc(t: ^testing.T) {
	f := fresh_filler()
	fill_with(&f.mix, id(.Sulfuric_Acid), 100)
	r := filler_take_drop(&f, id(.Water), 900, EYE)
	testing.expect_value(t, r.mix.at, lab.filler_center())
	testing.expect_value(t, shield_factor(r.mix.at), 1)
}

// ---- aiming and pouring ----

@(test)
the_crosshair_finds_the_station :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	p.x, p.z = EYE.x, EYE.z
	look_at(p, lab.FILLER_MOUTH)
	testing.expect(t, filler_aim(&f, props, view_of(p)), "looking at the funnel")
	testing.expect(t, f.aimed_t < POUR_REACH, "close enough to pour")

	look_at(p, {0, 1.6, 0})
	testing.expect(t, !filler_aim(&f, props, view_of(p)), "looking away")

	p.z = 3.0
	look_at(p, lab.FILLER_MOUTH)
	testing.expect(t, !filler_aim(&f, props, view_of(p)), "too far")

	p.z = EYE.z
	look_at(p, lab.FILLER_MOUTH)
	f.present = false
	testing.expect(t, !filler_aim(&f, props, view_of(p)), "no balloon, nothing to aim at")
}

@(test)
a_nearer_vessel_wins_the_aim :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	p.x, p.z = EYE.x, EYE.z
	look_at(p, lab.FILLER_MOUTH)
	props.aimed, props.aimed_t = 0, 0.3
	testing.expect(t, !filler_aim(&f, props, view_of(p)), "a vessel is nearer")
	props.aimed_t = 5
	testing.expect(t, filler_aim(&f, props, view_of(p)), "the station is nearer")
	props.aimed = -1
	testing.expect(t, filler_aim(&f, props, view_of(p)), "no vessel at all")
}

@(test)
the_pour_button_is_ready_for_the_station_only_when_it_should_be :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	f.aimed, f.aimed_t = true, 0.6
	testing.expect(t, !filler_pour_ready(&f, props), "nothing held")

	props_add(props, l, .Beaker, 0, 0.9, id(.Water), 200)
	props_add(props, l, .Beaker, 0, 0.35)
	props.held = 0
	testing.expect(t, filler_pour_ready(&f, props), "a vessel held, the station aimed at")

	f.aimed_t = POUR_REACH + 0.2
	testing.expect(t, !filler_pour_ready(&f, props), "too far")

	f.aimed_t = 0.6
	props.aimed, props.aimed_t = 1, 0.5
	testing.expect_value(t, pour_target(props), 1)
	testing.expect(t, !filler_pour_ready(&f, props), "a vessel is the target")

	f.aimed = false
	props.aimed = -1
	testing.expect(t, !filler_pour_ready(&f, props), "the crosshair is not on the station")
}

@(test)
a_pour_into_the_funnel_fills_the_balloon :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	f := fresh_filler()
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 6.0, 7.0, id(.Water), 300)
	s.props.held = 0
	s.props.pouring = true
	s.p.x, s.p.z = EYE.x, EYE.z
	look_at(s.p, lab.FILLER_MOUTH)

	dt := f32(1.0 / 60)
	events: [MAX_EVENTS]Fill_Result
	for _ in 0 ..< 420 {
		update(s.props, s.l, s.p, dt)
		filler_aim(&f, s.props, view_of(s.p))
		filler_update(&f, dt)
		if filler_pour_ready(&f, s.props) {
			pour_flow_to(s.props, s.st, s.l, dt, filler_mouth(), true)
		} else {
			pour_flow(s.props, s.st, s.l, dt)
		}
		stream_step(s.st, 21)
		filler_capture(s.st, &f, view_of(s.p).eye, &events)
	}
	left := ml_of(&s.props.items[0].mix) + s.props.items[0].flow_acc
	in_air := f32(s.st.sim.count) * DROP_ML
	testing.expect(t, ml_of(&f.mix) > 200, "most of the pour reached the balloon")
	testing.expect(t, left < 30, "the beaker ran dry")
	testing.expect(t, ml_of(&f.mix) + left + in_air < 300 + 1, "and nothing was made from nothing")
	testing.expect_value(t, main_of(&f.mix), id(.Water))
}

@(test)
drops_pass_through_the_funnel_when_there_is_no_balloon :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	f := fresh_filler()
	f.present = false
	m := lab.FILLER_MOUTH
	stream_spawn(s.st, s.l, {m.x, m.y - 0.05, m.z}, {}, id(.Water))
	events: [MAX_EVENTS]Fill_Result
	testing.expect_value(t, filler_capture(s.st, &f, EYE, &events), 0)
	testing.expect_value(t, s.st.sim.count, 1)
}

@(test)
only_drops_in_the_funnel_column_are_taken :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	f := fresh_filler()
	m := lab.FILLER_MOUTH
	stream_spawn(s.st, s.l, {m.x, m.y - 0.05, m.z}, {}, id(.Water)) // in
	stream_spawn(s.st, s.l, {m.x + 0.2, m.y - 0.05, m.z}, {}, id(.Water)) // beside it
	stream_spawn(s.st, s.l, {m.x, lab.FILLER_CAPTURE_HIGH + 0.1, m.z}, {}, id(.Water)) // far above
	events: [MAX_EVENTS]Fill_Result
	filler_capture(s.st, &f, EYE, &events)
	testing.expect_value(t, s.st.sim.count, 2)
	testing.expect(t, abs(ml_of(&f.mix) - DROP_ML) < 0.01, "one drop went in")
}

// ---- the sink and the fume hood ----

@(test)
the_drain_takes_what_falls_in_the_basin :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	b := lab.SINK_BASIN
	cx, cz := (b.min_x + b.max_x) * 0.5, (b.min_z + b.max_z) * 0.5
	low := lab.COUNTER_HEIGHT + 0.05
	stream_spawn(s.st, s.l, {cx, low, cz}, {}, id(.Water)) // in the basin, low
	stream_spawn(s.st, s.l, {cx, low, cz + 0.2}, {}, id(.Water)) // in the basin, low
	stream_spawn(s.st, s.l, {cx, lab.SINK_DRAIN_TOP + 0.15, cz}, {}, id(.Water)) // over the basin, still in the air
	stream_spawn(s.st, s.l, {b.max_x + 0.3, low, cz}, {}, id(.Water)) // on the counter beside it
	testing.expect_value(t, s.st.sim.count, 4)
	testing.expect_value(t, stream_drain(s.st), 2)
	testing.expect_value(t, s.st.sim.count, 2)
}

@(test)
the_hood_shields_what_is_inside_it :: proc(t: ^testing.T) {
	h := lab.HOOD
	inside := Vec3{(h.min_x + h.max_x) * 0.5, lab.COUNTER_HEIGHT + 0.1, (h.min_z + h.max_z) * 0.5}
	testing.expect(t, in_hood(inside), "in the hood")
	testing.expect_value(t, shield_factor(inside), HOOD_SHIELD)
	testing.expect(t, !in_hood({inside.x, lab.HOOD_TOP + 0.2, inside.z}), "above it")
	testing.expect(t, !in_hood({h.max_x + 0.3, inside.y, inside.z}), "beside it")
	testing.expect_value(t, shield_factor({0, 1.2, 0}), 1)

	r := Mix_Result {
		damage = 80,
		at     = inside,
	}
	testing.expect(t, abs(felt_damage(r) - 80 * HOOD_SHIELD) < 1e-4, "a fifth gets out")
	testing.expect_value(t, openness(r), 0)
	r.at = {0, 1.2, 0}
	testing.expect_value(t, felt_damage(r), 80)
	testing.expect_value(t, openness(r), 1)
}

@(test)
a_blast_in_the_hood_hurts_less_than_the_same_blast_outside :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	h := lab.HOOD
	hx, hz := (h.min_x + h.max_x) * 0.5, (h.min_z + h.max_z) * 0.5
	props_add(props, l, .Flask, hx, hz)
	props_add(props, l, .Flask, 0, 0.4)
	burst_mix(&props.items[0].mix, 100)
	burst_mix(&props.items[1].mix, 100)
	// The player is the same distance, 0.8 m, from the middle of each flask.
	mid := kind_dims(.Flask).height * 0.5
	in_hood_eye := Vec3{hx, lab.COUNTER_HEIGHT + mid, hz + 0.8}
	out_eye := Vec3{0.8, lab.COUNTER_HEIGHT + mid, 0.4}
	a := apply_droplet(props, 0, id(.Water), 100, in_hood_eye, 160)
	b := apply_droplet(props, 0, id(.Water), 100, out_eye, 160) // the other flask is now number 0
	testing.expect_value(t, a.kind, Mix_Kind.Blast)
	testing.expect_value(t, b.kind, Mix_Kind.Blast)
	testing.expect(t, abs(a.damage - b.damage) < 0.5, "the same force at the same distance")
	testing.expect(t, felt_damage(a) < felt_damage(b) * 0.25, "but the hood takes most of it")
	testing.expect(t, in_hood(a.at) && !in_hood(b.at), "and each says where it was")
}

// ---- the gauge ----

lit_lights :: proc(ratio: f32) -> int {
	n := 0
	for i in 0 ..< lab.GAUGE_LIGHTS {
		if gauge_color(ratio, i) != .Off {
			n += 1
		}
	}
	return n
}

@(test)
the_gauge_lights_one_after_another :: proc(t: ^testing.T) {
	testing.expect_value(t, lit_lights(0), 0)
	testing.expect_value(t, lit_lights(0.01), 1)
	testing.expect_value(t, lit_lights(BALLOON_POP_AT), lab.GAUGE_LIGHTS)
	last := 0
	for ratio := f32(0); ratio <= BALLOON_POP_AT; ratio += 0.01 {
		n := lit_lights(ratio)
		testing.expect(t, n >= last, "a fuller balloon never shows fewer lights")
		for i in 0 ..< n {
			testing.expect(t, gauge_color(ratio, i) != .Off, "the lit ones are the lowest")
		}
		last = n
	}
}

@(test)
the_gauge_goes_from_green_to_red :: proc(t: ^testing.T) {
	testing.expect_value(t, gauge_color(BALLOON_POP_AT, 0), Gauge_Color.Green)
	testing.expect_value(t, gauge_color(BALLOON_POP_AT, lab.GAUGE_LIGHTS - 1), Gauge_Color.Red)
	seen_amber := false
	for i in 0 ..< lab.GAUGE_LIGHTS {
		if gauge_color(BALLOON_POP_AT, i) == .Amber {
			seen_amber = true
		}
	}
	testing.expect(t, seen_amber, "something between")
	// Everything green is under a fill of 1: the balloon is at its natural size
	// when the last green light is lit.
	greens := 0
	for i in 0 ..< lab.GAUGE_LIGHTS {
		if gauge_color(BALLOON_POP_AT, i) == .Green {
			greens += 1
		}
	}
	step := BALLOON_POP_AT / f32(lab.GAUGE_LIGHTS)
	testing.expect(t, f32(greens) * step <= 1 + step, "the green part ends near a fill of 1")
	testing.expect(t, f32(greens) * step >= 1 - step, "and starts from empty")
}

// ---- the speed of liquid, and taps that aim ----

@(test)
speed_goes_round_the_choices :: proc(t: ^testing.T) {
	props := new(Props)
	defer free(props)
	testing.expect_value(t, flow_speed(props), 1) // an unset speed is normal
	props_init(props)
	testing.expect_value(t, flow_speed(props), 1)
	testing.expect_value(t, speed_cycle(props), 2)
	testing.expect_value(t, speed_cycle(props), 4)
	testing.expect_value(t, speed_cycle(props), 8)
	testing.expect_value(t, speed_cycle(props), 1)
	testing.expect_value(t, flow_speed(props), 1)
}

// Pours a beaker of `ml` of water into the funnel of the fill station at `speed`.
// Returns the frames until the beaker is empty, and what the balloon holds.
pour_into_funnel :: proc(speed: f32, ml: f32) -> (frames: int, delivered: f32) {
	s := pour_scene()
	defer free_pour_scene(s)
	f := fresh_filler()
	props_init(s.props)
	s.props.speed = speed
	props_add(s.props, s.l, .Beaker, 6.0, 7.0, id(.Water), ml)
	s.props.held = 0
	s.props.pouring = true
	s.p.x, s.p.z = EYE.x, EYE.z
	look_at(s.p, lab.FILLER_MOUTH)
	dt := f32(1.0 / 60)
	events: [MAX_EVENTS]Fill_Result
	empty_at := -1
	for frame in 0 ..< 900 {
		update(s.props, s.l, s.p, dt)
		filler_aim(&f, s.props, view_of(s.p))
		if filler_pour_ready(&f, s.props) {
			pour_flow_to(s.props, s.st, s.l, dt, filler_mouth(), true)
		} else {
			pour_flow(s.props, s.st, s.l, dt)
		}
		stream_step(s.st, 21)
		filler_capture(s.st, &f, view_of(s.p).eye, &events)
		if empty_at < 0 && ml_of(&s.props.items[0].mix) + s.props.items[0].flow_acc < 1 {
			empty_at = frame
		}
		if s.st.sim.count == 0 && empty_at >= 0 {
			break
		}
	}
	return empty_at, ml_of(&f.mix)
}

@(test)
a_faster_pour_empties_a_vessel_sooner_and_loses_nothing :: proc(t: ^testing.T) {
	slow_frames, slow_got := pour_into_funnel(1, 600)
	fast_frames, fast_got := pour_into_funnel(8, 600)
	testing.expect(t, slow_frames > 0 && fast_frames > 0, "both emptied the beaker")
	testing.expectf(t, fast_frames * 3 < slow_frames, "normal took %v frames and eight times took %v", slow_frames, fast_frames)
	testing.expectf(t, slow_got > 540, "normal delivered %v of 600", slow_got)
	testing.expectf(t, fast_got > 540, "fast delivered %v of 600", fast_got)
	testing.expect(t, fast_got <= 600.01 && slow_got <= 600.01, "and made nothing from nothing")
}

// Fills a held beaker held `aside` metres beside tap 4 for `frames` frames at
// `speed`. Returns what it holds and what is still in the air.
fill_at_tap :: proc(aside: f32, frames: int, speed: f32) -> (got, air: f32) {
	s := pour_scene()
	defer free_pour_scene(s)
	st: Station
	station_init(&st)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 0, 0, 0, 0)
	s.props.held = 0
	n := lab.dispenser_nozzle(2)
	s.props.items[0].pos = {n.x - 0.1, n.y - 0.25 - kind_dims(.Beaker).height, n.z + aside}
	events: [MAX_EVENTS]Mix_Result
	for _ in 0 ..< frames {
		station_flow_to(&st, s.st, s.l, 2, 1.0 / 60, tap_mouth(s.props), true, speed)
		stream_step(s.st, 21)
		stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	}
	for i in 0 ..< s.st.sim.count {
		air += s.st.ml[i]
	}
	return ml_of(&s.props.items[0].mix), air
}

// The purity of the first drop that comes out of tap `i`.
first_drop_purity :: proc(i: int) -> f32 {
	s := pour_scene()
	defer free_pour_scene(s)
	st: Station
	station_init(&st)
	for _ in 0 ..< 20 {
		station_flow(&st, s.st, s.l, i, 1.0 / 60)
	}
	return s.st.sim.count > 0 ? s.st.purity[0] : -1
}

@(test)
water_from_the_sink_is_tap_water_and_the_chemicals_of_the_wall_are_pure :: proc(t: ^testing.T) {
	testing.expect_value(t, first_drop_purity(lab.SINK_TAP), SINK_PURITY) // water
	testing.expect_value(t, first_drop_purity(0), STOCK_PURITY) // acetic acid
	testing.expect_value(t, first_drop_purity(1), STOCK_PURITY) // ethanol
	testing.expect_value(t, first_drop_purity(2), STOCK_PURITY) // sulfuric acid
}

@(test)
water_is_not_on_the_bottle_wall_and_the_sink_gives_only_water :: proc(t: ^testing.T) {
	st: Station
	station_init(&st)
	testing.expect_value(t, st.items[0].compound, u16(chemistry.Id.Acetic_Acid))
	testing.expect_value(t, st.items[1].compound, u16(chemistry.Id.Ethanol))
	testing.expect_value(t, st.items[2].compound, u16(chemistry.Id.Sulfuric_Acid))
	for i in 0 ..< lab.DISPENSER_COUNT {
		testing.expect(t, st.items[i].compound != u16(chemistry.Id.Water), "no tap of the wall has water")
		testing.expect_value(t, st.items[i].unlocked, i < 3)
	}
	testing.expect_value(t, st.items[lab.SINK_TAP].compound, u16(chemistry.Id.Water))
	testing.expect(t, st.items[lab.SINK_TAP].unlocked, "and the faucet runs")
}

@(test)
a_vessel_held_under_the_faucet_is_found_and_filled_with_sink_water :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	st: Station
	station_init(&st)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 0, 0, 0, 0)
	s.props.held = 0
	n := lab.SINK_NOZZLE
	s.props.items[0].pos = {n.x, n.y - 0.2 - kind_dims(.Beaker).height, n.z}
	testing.expect_value(t, dispenser_under(&st, s.props), lab.SINK_TAP)
	events: [MAX_EVENTS]Mix_Result
	for _ in 0 ..< 150 { // two and a half seconds
		station_flow_to(&st, s.st, s.l, lab.SINK_TAP, 1.0 / 60, tap_mouth(s.props), true, 1)
		stream_step(s.st, 21)
		stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	}
	v := s.props.items[0]
	testing.expect_value(t, main_of(&v.mix), u16(chemistry.Id.Water))
	testing.expect_value(t, v.mix.count, 1)
	testing.expect_value(t, v.mix.items[0].purity, SINK_PURITY)
	testing.expectf(t, ml_of(&v.mix) > 200 && ml_of(&v.mix) < 300, "the vessel holds %v ml", ml_of(&v.mix))
}

@(test)
a_vessel_at_the_bottle_wall_is_not_under_the_faucet_and_the_other_way_round :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	st: Station
	station_init(&st)
	props_init(props)
	props_add(props, l, .Beaker, 0, 0, 0, 0)
	props.held = 0
	w := lab.dispenser_nozzle(0)
	props.items[0].pos = {w.x, w.y - 0.2 - kind_dims(.Beaker).height, w.z}
	testing.expect_value(t, dispenser_under(&st, props), 0)
	n := lab.SINK_NOZZLE
	props.items[0].pos = {n.x, n.y - 0.2 - kind_dims(.Beaker).height, n.z}
	testing.expect_value(t, dispenser_under(&st, props), lab.SINK_TAP)
	props.items[0].pos = {n.x, n.y - 0.2 - kind_dims(.Beaker).height, n.z + 1.5} // along the counter, away from it
	testing.expect_value(t, dispenser_under(&st, props), -1)
	props.items[0].pos = {n.x, n.y + 0.5, n.z} // above the tip
	testing.expect_value(t, dispenser_under(&st, props), -1)
}

@(test)
a_tap_fills_a_vessel_that_is_not_under_it :: proc(t: ^testing.T) {
	got, air := fill_at_tap(0.35, 150, 1)
	testing.expectf(t, got > 200, "the vessel beside the nozzle holds %v ml", got)
	testing.expect(t, got + air <= 110 * 2.5 + 7, "and nothing was made from nothing")
}

@(test)
a_faster_tap_fills_sooner :: proc(t: ^testing.T) {
	slow, _ := fill_at_tap(0.35, 90, 1)
	fast, air := fill_at_tap(0.35, 90, 4)
	testing.expectf(t, slow > 100, "normal gave %v", slow)
	testing.expectf(t, fast > slow * 2.5, "four times faster gave %v against %v", fast, slow)
	testing.expect(t, fast + air <= 110 * 4 * 1.5 + 4 * DROP_ML, "and nothing was made from nothing")
}
