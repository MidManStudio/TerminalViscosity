// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "heat_test.odin"
// ============================================================================

package carry

import "../chem"
import "../lab"
import "core:testing"

hot_spot :: proc() -> (x, z: f32) {
	return (lab.HOT_PLATE.min_x + lab.HOT_PLATE.max_x) * 0.5, (lab.HOT_PLATE.min_z + lab.HOT_PLATE.max_z) * 0.5
}

cold_spot :: proc() -> (x, z: f32) {
	return (lab.ICE_BATH.min_x + lab.ICE_BATH.max_x) * 0.5, (lab.ICE_BATH.min_z + lab.ICE_BATH.max_z) * 0.5
}

seconds :: proc(props: ^Props, n: f32) {
	for _ in 0 ..< int(n * 60) {
		props_heat_update(props, 1.0 / 60)
	}
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
	testing.expect(t, props.items[0].heat > 0.15 && props.items[0].heat < 0.25, "a fifth warmer after a second")
	testing.expect(t, props.items[1].heat < -0.15 && props.items[1].heat > -0.25, "a fifth cooler")
	testing.expect_value(t, props.items[2].heat, 0) // the one on the bench stays at the room
	seconds(props, 6)
	testing.expect_value(t, props.items[0].heat, 1) // fully hot in about five seconds, and no further
	testing.expect_value(t, props.items[1].heat, -1)
	testing.expect_value(t, props.items[2].heat, 0)
}

@(test)
a_hot_vessel_cools_slowly_when_taken_off :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Flask, 0, 0.4, id(.Water), 300)
	props.items[0].heat = 1
	seconds(props, 10)
	testing.expect(t, props.items[0].heat < 0.8 && props.items[0].heat > 0.6, "still warm after ten seconds")
	seconds(props, 40)
	testing.expect_value(t, props.items[0].heat, 0)
	props.items[0].heat = -1
	seconds(props, 10)
	testing.expect(t, props.items[0].heat > -0.8 && props.items[0].heat < -0.6, "a cold one warms the same way")
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
	props.items[0].heat = 0.5
	seconds(props, 3)
	testing.expect_value(t, props.items[0].heat, 0) // an empty vessel has no temperature
	testing.expect_value(t, props.items[1].heat, 0) // a held one does not heat
	testing.expect_value(t, props.items[2].heat, 0) // nor one in the air
	testing.expect_value(t, props.items[3].heat, 0) // nor one beside the plate
}

@(test)
words_for_the_temperature :: proc(t: ^testing.T) {
	testing.expect_value(t, heat_word(0), "")
	testing.expect_value(t, heat_word(0.2), "")
	testing.expect_value(t, heat_word(0.4), "warm")
	testing.expect_value(t, heat_word(0.6), "warm")
	testing.expect_value(t, heat_word(0.75), "hot")
	testing.expect_value(t, heat_word(0.9), "hot")
	testing.expect_value(t, heat_word(-0.4), "cool")
	testing.expect_value(t, heat_word(-0.6), "cool")
	testing.expect_value(t, heat_word(-0.75), "cold")
	testing.expect_value(t, heat_word(-0.9), "cold")
}

@(test)
a_hot_drop_warms_the_liquid_it_joins_by_its_share :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Beaker, 0, 0.4, id(.Water), 100)
	apply_droplet(props, 0, id(.Water), 100, {0, 1.6, 0}, 1)
	testing.expect(t, abs(props.items[0].heat - 0.5) < 1e-4, "half hot, half not")
	props_add(props, l, .Beaker, 1, 0.4)
	apply_droplet(props, 1, id(.Water), 10, {0, 1.6, 0}, 0.8)
	testing.expect_value(t, props.items[1].heat, 0.8) // into an empty one, it is the drop's own
}

@(test)
heat_turns_a_calm_mix_into_a_blast_and_cold_tames_one :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	eye := Vec3{0, 1.6, 3}
	props_add(props, l, .Flask, 0, 0.4, id(.Soda_Base), 300)
	r := apply_droplet(props, 0, id(.Fizz_Acid), DROP_ML, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Mixed) // calm in the room

	props_add(props, l, .Flask, 0, 0.4, id(.Soda_Base), 300)
	props.items[props.count - 1].heat = 0.5
	r = apply_droplet(props, props.count - 1, id(.Fizz_Acid), DROP_ML, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Spatter) // warm

	props_add(props, l, .Flask, 0, 0.4, id(.Soda_Base), 300)
	props.items[props.count - 1].heat = 1
	before := props.count
	r = apply_droplet(props, props.count - 1, id(.Fizz_Acid), DROP_ML, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Blast) // hot
	testing.expect_value(t, props.count, before - 1) // and the vessel is gone
	testing.expect(t, r.volatility > 0.6, "and it says how violent")

	props_add(props, l, .Flask, 0, 0.4, id(.Ember_Oil), 300)
	props.items[props.count - 1].heat = -1
	r = apply_droplet(props, props.count - 1, id(.Spark_Blue), DROP_ML, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Spatter) // the worst blast, tamed by the ice
	testing.expect(t, r.damage < 40, "and it hurts far less")
}

@(test)
a_pour_carries_the_heat_of_the_vessel_it_comes_from :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 0, 0.5, id(.Water), 400)
	s.props.items[0].heat = 0.8
	s.props.held = 0
	s.props.pouring = true
	look_at(s.p, {0, 1.2, 3})
	found := false
	for _ in 0 ..< 240 {
		update(s.props, s.l, s.p, 1.0 / 60)
		pour_flow(s.props, s.st, s.l, 1.0 / 60)
		if s.st.sim.count > 0 {
			testing.expect_value(t, s.st.heat[0], 0.8)
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
		filler_take_drop(&f, id(.Water), DROP_ML, EYE, 1)
	}
	testing.expect_value(t, f.heat, 1)
	f.compound, f.ml, f.heat = id(.Soda_Base), 300, 1
	r := filler_take_drop(&f, id(.Fizz_Acid), DROP_ML, EYE, 0)
	testing.expect_value(t, r.mix.kind, Mix_Kind.Blast) // a hot balloon is dangerous to pour acid into
	testing.expect(t, !f.present, "and it bursts")
	testing.expect_value(t, f.heat, 0)
	testing.expect_value(t, chem.hazard_of(chem.react(id(.Soda_Base), id(.Fizz_Acid)).volatility), chem.Hazard.Calm)
}

@(test)
a_hot_drop_that_lands_in_a_vessel_or_the_funnel_brings_its_heat :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 1.0, 1.0)
	pr := s.props.items[0]
	events: [MAX_EVENTS]Mix_Result
	stream_spawn_ml(s.st, s.l, {pr.pos.x, pr.pos.y + 0.1, pr.pos.z}, {}, id(.Water), 50, 0.9)
	stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	testing.expect_value(t, s.props.items[0].ml, 50)
	testing.expect_value(t, s.props.items[0].heat, 0.9)

	f := fresh_filler()
	m := lab.FILLER_MOUTH
	stream_spawn_ml(s.st, s.l, {m.x, m.y - 0.05, m.z}, {}, id(.Water), 50, -0.7)
	fill_events: [MAX_EVENTS]Fill_Result
	filler_capture(s.st, &f, EYE, &fill_events)
	testing.expect_value(t, f.ml, 50)
	testing.expect_value(t, f.heat, -0.7)
}

@(test)
a_burst_balloon_loses_its_heat_with_its_liquid :: proc(t: ^testing.T) {
	f := fresh_filler()
	f.compound, f.ml, f.heat = id(.Water), 1340, 0.8
	r := filler_take_drop(&f, id(.Water), 20, EYE, 0.8)
	testing.expect(t, r.popped, "overfilled")
	testing.expect_value(t, f.heat, 0)
}
