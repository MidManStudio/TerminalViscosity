// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "heat_test.odin"
// ============================================================================

package carry

import "../chemistry"
import "../lab"
import "core:testing"

hot_spot :: proc() -> (x, z: f32) {
	return (lab.HOT_PLATE.min_x + lab.HOT_PLATE.max_x) * 0.5, (lab.HOT_PLATE.min_z + lab.HOT_PLATE.max_z) * 0.5
}

cold_spot :: proc() -> (x, z: f32) {
	return (lab.ICE_BATH.min_x + lab.ICE_BATH.max_x) * 0.5, (lab.ICE_BATH.min_z + lab.ICE_BATH.max_z) * 0.5
}

// Runs the heat of every vessel for `n` seconds with the player at the middle of the room, and
// returns how many events there were in all.
seconds :: proc(props: ^Props, n: f32) -> int {
	events: [MAX_EVENTS]Mix_Result
	count := 0
	for _ in 0 ..< int(n * 60) {
		count += props_heat_update(props, 1.0 / 60, {0, 1.6, 0}, &events)
	}
	return count
}

@(test)
a_vessel_on_the_hot_plate_warms_and_one_in_the_ice_bath_cools :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hx, hz := hot_spot()
	cx, cz := cold_spot()
	props_add(props, l, .Flask, hx, hz, id(.Water), 300)
	props_add(props, l, .Flask, cx, cz, id(.Water), 300)
	props_add(props, l, .Flask, 0, 0.4, id(.Water), 300)
	seconds(props, 1)
	testing.expect(t, near(props.items[0].mix.heat_c, 26, 0.05), "6 degrees warmer after a second")
	testing.expect(t, near(props.items[1].mix.heat_c, 14, 0.05), "6 degrees cooler")
	testing.expect_value(t, props.items[2].mix.heat_c, ROOM_C) // the one on the bench stays at the room
	seconds(props, 29)
	testing.expect_value(t, props.items[0].mix.heat_c, HOT_PLATE_C) // 160 in about 23 seconds, and no further
	testing.expect_value(t, props.items[1].mix.heat_c, ICE_BATH_C)
	testing.expect_value(t, props.items[2].mix.heat_c, ROOM_C)
	testing.expect_value(t, HOT_PLATE_C, f32(160))
	testing.expect_value(t, ICE_BATH_C, f32(0))
}

@(test)
a_hot_vessel_cools_slowly_when_taken_off :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Flask, 0, 0.4, id(.Water), 300)
	props.items[0].mix.heat_c = 100
	seconds(props, 10)
	testing.expect(t, near(props.items[0].mix.heat_c, 80, 0.05), "20 degrees cooler after ten seconds")
	seconds(props, 40)
	testing.expect_value(t, props.items[0].mix.heat_c, ROOM_C) // and it stops at the room
	props.items[0].mix.heat_c = 0
	seconds(props, 5)
	testing.expect(t, near(props.items[0].mix.heat_c, 10, 0.05), "a cold one warms the same way")
	seconds(props, 20)
	testing.expect_value(t, props.items[0].mix.heat_c, ROOM_C)
}

@(test)
only_a_resting_vessel_with_liquid_in_it_takes_the_heat :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hx, hz := hot_spot()
	props_add(props, l, .Flask, hx, hz, 0, 0) // empty
	props_add(props, l, .Flask, hx, hz, id(.Water), 300) // held
	props_add(props, l, .Flask, hx, hz, id(.Water), 300) // in the air
	props_add(props, l, .Flask, lab.HOT_PLATE.max_x + 0.1, hz, id(.Water), 300) // beside the plate
	props.held = 1
	props.items[2].pos.y = lab.COUNTER_HEIGHT + 0.5
	props.items[0].mix.heat_c = 50
	seconds(props, 3)
	testing.expect_value(t, props.items[0].mix.heat_c, 0) // an empty vessel has no temperature
	testing.expect_value(t, props.items[1].mix.heat_c, ROOM_C) // a held one does not heat
	testing.expect_value(t, props.items[2].mix.heat_c, ROOM_C) // nor one in the air
	testing.expect_value(t, props.items[3].mix.heat_c, ROOM_C) // nor one beside the plate
}

@(test)
words_and_numbers_for_the_temperature :: proc(t: ^testing.T) {
	testing.expect_value(t, heat_unit(20), f32(0))
	testing.expect_value(t, heat_unit(100), f32(1))
	testing.expect_value(t, heat_unit(160), f32(1))
	testing.expect_value(t, heat_unit(60), f32(0.5))
	testing.expect_value(t, heat_unit(0), f32(-1))
	testing.expect_value(t, heat_unit(-30), f32(-1))
	testing.expect_value(t, heat_unit(10), f32(-0.5))
	testing.expect_value(t, heat_word(20), "")
	testing.expect_value(t, heat_word(30), "")
	testing.expect_value(t, heat_word(40.5), "warm")
	testing.expect_value(t, heat_word(70), "warm")
	testing.expect_value(t, heat_word(77), "warm")
	testing.expect_value(t, heat_word(80), "hot")
	testing.expect_value(t, heat_word(130), "hot")
	testing.expect_value(t, heat_word(16), "")
	testing.expect_value(t, heat_word(14), "cool")
	testing.expect_value(t, heat_word(10), "cool")
	testing.expect_value(t, heat_word(6), "cool")
	testing.expect_value(t, heat_word(4), "cold")
	testing.expect_value(t, heat_word(-20), "cold")
}

@(test)
vessels_stand_on_the_station_the_pages_name :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hx, hz := hot_spot()
	cx, cz := cold_spot()
	props_add(props, l, .Flask, hx, hz, id(.Water), 100)
	props_add(props, l, .Flask, cx, cz, id(.Water), 100)
	props_add(props, l, .Flask, 0, 0.4, id(.Water), 100)
	testing.expect_value(t, station_of(props.items[0]), chemistry.Station.Hot_Bath)
	testing.expect_value(t, station_of(props.items[1]), chemistry.Station.Cold_Bath)
	testing.expect_value(t, station_of(props.items[2]), chemistry.Station.Any)
}

@(test)
a_drop_keeps_its_purity_when_it_lands_and_a_removed_drop_does_not_mix_up_the_rest :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 1.0, 1.0)
	pr := s.props.items[0]
	events: [MAX_EVENTS]Mix_Result
	// A drop of purity 0.3 over the vessel and one of purity 0.7 beside it, in that order.
	stream_spawn_ml(s.st, s.l, {pr.pos.x, pr.pos.y + 0.1, pr.pos.z}, {}, id(.Water), 10, 0.3, 40)
	stream_spawn_ml(s.st, s.l, {pr.pos.x + 0.4, pr.pos.y + 0.3, pr.pos.z}, {}, id(.Ethanol), 20, 0.7, 60)
	testing.expect_value(t, s.st.sim.count, 2)
	stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	testing.expect_value(t, s.props.items[0].mix.items[0].purity, f32(0.3)) // it landed with its purity
	testing.expect_value(t, s.st.sim.count, 1)
	testing.expect_value(t, s.st.compound[0], id(.Ethanol)) // the one that stayed is the one that stayed
	testing.expect_value(t, s.st.purity[0], f32(0.7))
	testing.expect_value(t, s.st.heat[0], f32(60))
	testing.expect_value(t, s.st.ml[0], f32(20))
}

@(test)
a_hot_drop_warms_the_liquid_it_joins_by_its_share :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Beaker, 0, 0.4, id(.Water), 100)
	props_add(props, l, .Beaker, 0, 0.9)
	apply_droplet(props, 0, id(.Water), 100, {0, 1.6, 0}, 80)
	testing.expect(t, near(props.items[0].mix.heat_c, 50, 1e-3), "half at 20, half at 80")
	apply_droplet(props, 1, id(.Water), 10, {0, 1.6, 0}, 64)
	testing.expect_value(t, props.items[1].mix.heat_c, f32(64)) // into an empty one, it is the drop's own
}

@(test)
a_vessel_that_is_heated_into_a_window_reacts :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hx, hz := hot_spot()
	props_add(props, l, .Flask, hx, hz, id(.Ethanol), 100)
	m := &props.items[0].mix
	chemistry.mix_add(m, .Acetic_Acid, 100, 1, ROOM_C)
	chemistry.mix_add(m, .Sulfuric_Acid, 3, 1, ROOM_C) // the catalyst, a little of it
	testing.expect_value(t, chemistry.settle(m, .Hot_Bath).count, 0) // too cold
	testing.expect(t, near(ml_of(m), 203, 0.05), "nothing has happened yet")
	count := seconds(props, 8) // 20 to 68 degrees
	testing.expect_value(t, count, 0)
	count = seconds(props, 4) // through 75
	testing.expect_value(t, count, 1)
	testing.expect_value(t, chemistry.dominant(m), chemistry.Id.Ethyl_Acetate)
	testing.expect(t, m.heat_c > 75 && m.heat_c < 100, "and it is still heating")
	testing.expect_value(t, seconds(props, 20), 0) // nothing more to happen
}

@(test)
a_vessel_heated_past_a_limit_spatters_and_one_past_a_burst_breaks :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hx, hz := hot_spot()
	// Acid and water that were mixed the right way round and are just under the boil.
	props_add(props, l, .Flask, hx, hz)
	m := &props.items[0].mix
	chemistry.mix_add(m, .Water, 90, 0.7, 99.95)
	chemistry.mix_add(m, .Sulfuric_Acid, 10, 1, 99.95)
	m.ran = u64(1) << u64(chemistry.reaction_index("dilute_acid_clean")) // as if it had been held there
	events: [MAX_EVENTS]Mix_Result
	n := props_heat_update(props, 1.0 / 60, {0, 1.6, 0}, &events)
	testing.expect_value(t, n, 1)
	testing.expect_value(t, events[0].kind, Mix_Kind.Spatter)
	testing.expect_value(t, props.count, 1)
	testing.expect(t, near(ml_of(&props.items[0].mix), 80, 0.01), "a fifth is thrown out")

	// Four things together, held just under the burst, and past it.
	props_add(props, l, .Flask, hx + 0.2, hz)
	b := &props.items[1].mix
	chemistry.mix_add(b, .Water, 100, 1, 149.95)
	chemistry.mix_add(b, .Ethanol, 100, 1, 149.95)
	chemistry.mix_add(b, .Acetic_Acid, 100, 1, 149.95)
	chemistry.mix_add(b, .Sulfuric_Acid, 100, 1, 149.95)
	b.ran = u64(1) << u64(chemistry.reaction_index("spirit_and_acids"))
	n = props_heat_update(props, 1.0 / 60, {0, 1.6, 0}, &events)
	testing.expect_value(t, n, 1)
	testing.expect_value(t, events[0].kind, Mix_Kind.Blast)
	testing.expect_value(t, props.count, 1) // the vessel broke
}

@(test)
a_pour_carries_the_heat_of_the_vessel_it_comes_from :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 0, 0.5, id(.Water), 400)
	s.props.items[0].mix.heat_c = 80
	s.props.held = 0
	s.props.pouring = true
	look_at(s.p, {0, 1.2, 3})
	found := false
	for _ in 0 ..< 240 {
		update(s.props, s.l, s.p, 1.0 / 60)
		pour_flow(s.props, s.st, s.l, 1.0 / 60)
		if s.st.sim.count > 0 {
			testing.expect_value(t, s.st.heat[0], f32(80))
			testing.expect_value(t, s.st.purity[0], SINK_PURITY)
			found = true
			break
		}
	}
	testing.expect(t, found, "a drop left the vessel")
}

@(test)
the_balloon_takes_the_heat_of_what_is_poured_in :: proc(t: ^testing.T) {
	f := fresh_filler()
	for _ in 0 ..< 50 {
		filler_take_drop(&f, id(.Water), DROP_ML, EYE, 90)
	}
	testing.expect(t, near(f.mix.heat_c, 90, 1e-3), "a balloon filled with hot water is hot")
	fill_with(&f.mix, id(.Ethanol), 300, 90)
	filler_take_drop(&f, id(.Water), DROP_ML, EYE, 20)
	testing.expect(t, near(f.mix.heat_c, (90 * 300 + 20 * DROP_ML) / (300 + DROP_ML), 1e-3), "a cool drop cools it by its share")
}

@(test)
a_hot_drop_that_lands_in_a_vessel_or_the_funnel_brings_its_heat :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 1.0, 1.0)
	pr := s.props.items[0]
	events: [MAX_EVENTS]Mix_Result
	stream_spawn_ml(s.st, s.l, {pr.pos.x, pr.pos.y + 0.1, pr.pos.z}, {}, id(.Water), 50, 1, 90)
	stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	testing.expect_value(t, ml_of(&s.props.items[0].mix), 50)
	testing.expect_value(t, s.props.items[0].mix.heat_c, f32(90))

	f := fresh_filler()
	m := lab.FILLER_MOUTH
	stream_spawn_ml(s.st, s.l, {m.x, m.y - 0.05, m.z}, {}, id(.Water), 50, 1, 5)
	fill_events: [MAX_EVENTS]Fill_Result
	filler_capture(s.st, &f, EYE, &fill_events)
	testing.expect_value(t, ml_of(&f.mix), 50)
	testing.expect_value(t, f.mix.heat_c, f32(5))
}

@(test)
a_burst_balloon_loses_its_heat_with_its_liquid :: proc(t: ^testing.T) {
	f := fresh_filler()
	fill_with(&f.mix, id(.Water), 1340, 80)
	r := filler_take_drop(&f, id(.Water), 20, EYE, 80)
	testing.expect(t, r.popped, "overfilled")
	testing.expect_value(t, f.mix.heat_c, 0)
}

@(test)
the_liquid_in_the_balloon_drifts_back_to_the_room :: proc(t: ^testing.T) {
	f := fresh_filler()
	fill_with(&f.mix, id(.Ethanol), 300, 100)
	for _ in 0 ..< 10 * 60 {
		filler_update(&f, 1.0 / 60)
	}
	testing.expect(t, near(f.mix.heat_c, 80, 0.05), "still warm after ten seconds, as a vessel is")
	for _ in 0 ..< 40 * 60 {
		filler_update(&f, 1.0 / 60)
	}
	testing.expect_value(t, f.mix.heat_c, ROOM_C)

	fill_with(&f.mix, id(.Ethanol), 300, 0)
	for _ in 0 ..< 50 * 60 {
		filler_update(&f, 1.0 / 60)
	}
	testing.expect_value(t, f.mix.heat_c, ROOM_C) // a cold balloon warms back the same way
}

@(test)
an_empty_balloon_has_no_temperature_and_cooling_does_not_overshoot :: proc(t: ^testing.T) {
	f := fresh_filler()
	f.mix.heat_c = 90
	filler_update(&f, 1.0 / 60)
	testing.expect_value(t, f.mix.heat_c, 0)
	fill_with(&f.mix, id(.Water), 100, 20.1)
	filler_update(&f, 10)
	testing.expect_value(t, f.mix.heat_c, ROOM_C) // it stops at the room and does not go cold
}

@(test)
tied_balloons_cool_in_the_hand_the_clamp_and_on_the_hooks :: proc(t: ^testing.T) {
	lo := new_loadout()
	lo.hand = balloon(id(.Water), 100)
	lo.hand.mix.heat_c = 100
	lo.paint = balloon(id(.Water), 100)
	lo.paint.mix.heat_c = 12
	lo.slots[1] = balloon(id(.Water), 100)
	lo.slots[1].mix.heat_c = 60
	lo.slots[2] = balloon(id(.Water), 0) // nothing in it
	for _ in 0 ..< 3 * 60 {
		loadout_heat_update(&lo, 1.0 / 60)
	}
	testing.expect(t, near(lo.hand.mix.heat_c, 94, 0.05), "the hand")
	testing.expect(t, near(lo.paint.mix.heat_c, 18, 0.05), "the clamp")
	testing.expect(t, near(lo.slots[1].mix.heat_c, 54, 0.05), "a hook")
	testing.expect_value(t, lo.slots[2].mix.heat_c, 0) // nothing in it
	testing.expect_value(t, lo.slots[0].mix.heat_c, 0) // no balloon there
	for _ in 0 ..< 60 * 60 {
		loadout_heat_update(&lo, 1.0 / 60)
	}
	testing.expect(t, lo.hand.mix.heat_c == ROOM_C && lo.paint.mix.heat_c == ROOM_C && lo.slots[1].mix.heat_c == ROOM_C, "all back to the room")
}

@(test)
a_hot_plate_and_an_ice_bath_that_are_moved_heat_and_cool_where_they_now_stand :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	// The plate is moved to x 8 and the bath to x 9.2, along the north counter. Where they stood is bare counter.
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.63, 0})
	lab.placed_add(&props.placed, {.Ice_Bath, 9.2, -7.63, 0})
	ox, oz := hot_spot() // where the plate used to be
	props_add(props, l, .Flask, 8, -7.63, id(.Water), 300)
	props_add(props, l, .Flask, 9.2, -7.63, id(.Water), 300)
	props_add(props, l, .Flask, ox, oz, id(.Water), 300)
	seconds(props, 1)
	testing.expect(t, near(props.items[0].mix.heat_c, 26, 0.05), "warmed on the plate at its new place")
	testing.expect(t, near(props.items[1].mix.heat_c, 14, 0.05), "cooled in the bath at its new place")
	testing.expect_value(t, props.items[2].mix.heat_c, ROOM_C) // the old place does nothing
}

@(test)
a_station_that_is_turned_heats_where_its_plate_now_is :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.63, 1}) // turned a quarter: 0.6 along z, 0.5 along x
	props_add(props, l, .Flask, 8, -7.63 + 0.29, id(.Water), 300) // on the turned plate, off the plate as it was
	props_add(props, l, .Flask, 8 + 0.29, -7.63, id(.Water), 300) // on the plate as it was, off it turned
	seconds(props, 1)
	testing.expect(t, near(props.items[0].mix.heat_c, 26, 0.05), "warmed on the turned plate")
	testing.expect_value(t, props.items[1].mix.heat_c, ROOM_C)
}

@(test)
the_station_a_vessel_stands_on_is_where_the_stations_stand :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hx, hz := hot_spot()
	props_add(props, l, .Flask, hx, hz, id(.Water), 100)
	testing.expect_value(t, station_of(props.items[0], &props.placed), chemistry.Station.Hot_Bath)
	lab.placed_remove(&props.placed, 0) // the plate is taken away
	testing.expect_value(t, station_of(props.items[0], &props.placed), chemistry.Station.Any)
	testing.expect_value(t, station_heat(props.items[0], &props.placed), f32(0))
	lab.placed_add(&props.placed, {.Ice_Bath, hx, hz, 0}) // and a bath is put where it was
	testing.expect_value(t, station_of(props.items[0], &props.placed), chemistry.Station.Cold_Bath)
	testing.expect_value(t, target_c(props.items[0], false, &props.placed), ICE_BATH_C)
	testing.expect_value(t, station_of(props.items[0]), chemistry.Station.Hot_Bath) // with none given, the starting stations are meant
}

@(test)
a_drop_into_a_vessel_reacts_by_the_station_where_the_vessel_stands_now :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.63, 0})
	props_add(props, l, .Beaker, 8, -7.63, id(.Ethanol), 100)
	testing.expect_value(t, station_of(props.items[0], &props.placed), chemistry.Station.Hot_Bath)
	result := apply_droplet(props, 0, id(.Water), 5, {0, 1.6, 0})
	testing.expect(t, result.kind != .Blast, "a little water in ethanol is a mix, whatever the station")
	// The station that the drop saw is the one at the vessel: with the plate gone, the vessel is on bare counter.
	props.placed = {}
	testing.expect_value(t, station_of(props.items[0], &props.placed), chemistry.Station.Any)
}

@(test)
a_drop_that_makes_a_hot_bath_reaction_runs_only_where_the_vessel_stands_on_the_plate_now :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.63, 0}) // moved from where it was
	ox, oz := hot_spot() // where the plate used to be: bare counter now
	// Ethanol and acetic acid, with sulfuric acid to help, at 80 degrees: ethyl acetate is made in a hot bath.
	props_add(props, l, .Beaker, 8, -7.63, id(.Ethanol), 100)
	props_add(props, l, .Beaker, ox, oz, id(.Ethanol), 100)
	for k in 0 ..< 2 {
		m := &props.items[k].mix
		chemistry.mix_add(m, .Acetic_Acid, 100, 1, 80)
		chemistry.mix_add(m, .Sulfuric_Acid, 10, 1, 80)
		m.heat_c = 80
	}
	apply_droplet(props, 0, id(.Ethanol), 1, {0, 1.6, 0}, 80)
	apply_droplet(props, 1, id(.Ethanol), 1, {0, 1.6, 0}, 80)
	has_ester :: proc(m: ^chemistry.Mixture) -> bool {
		for i in 0 ..< m.count {
			if m.items[i].compound == .Ethyl_Acetate {
				return true
			}
		}
		return false
	}
	testing.expect(t, has_ester(&props.items[0].mix), "on the plate where it now stands, the hot bath reaction runs")
	testing.expect(t, !has_ester(&props.items[1].mix), "on the bare counter where the plate was, it does not")
}
