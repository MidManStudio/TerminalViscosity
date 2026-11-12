// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "chemistry_test.odin"
// ============================================================================

package chemistry

import "core:testing"

// These tests read the real pages, so a page edit that changes a number pinned here has to change
// the test in the same delivery. Every mixture starts at 20 degrees.

near :: proc(a, b: f32, eps := f32(0.01)) -> bool {
	return abs(a - b) <= eps
}

start :: proc(heat_c := f32(20)) -> Mixture {
	return {heat_c = heat_c}
}

// Pours into a mixture at the mixture's own temperature, so that pouring does not change it.
pour :: proc(m: ^Mixture, id: Id, ml: f32, purity := f32(1)) {
	mix_add(m, id, ml, purity, m.heat_c)
}

// The amount of a compound in a mixture, 0 if it is not there.
amount :: proc(m: ^Mixture, id: Id) -> f32 {
	at := mix_find(m, id)
	return at < 0 ? 0 : m.items[at].ml
}

@(test)
pages_are_numbered_by_the_index :: proc(t: ^testing.T) {
	testing.expect_value(t, COMPOUND_COUNT, 17)
	testing.expect_value(t, int(Id.Water), 1)
	testing.expect_value(t, int(Id.Acetic_Acid), 2)
	testing.expect_value(t, int(Id.Ethanol), 3)
	testing.expect_value(t, int(Id.Sulfuric_Acid), 4)
	testing.expect_value(t, int(Id.Persulfate), 17)
	testing.expect_value(t, compounds[0].id, "water")
	testing.expect_value(t, compounds[16].id, "persulfate")
	testing.expect_value(t, id_of("sulfuric_acid"), Id.Sulfuric_Acid)
	testing.expect_value(t, id_of("no_such_thing"), Id.None)
	testing.expect(t, compound_of(.None) == nil, "number 0 is no compound")
	testing.expect(t, compound_of(Id(18)) == nil, "and so is a number past the last")
	testing.expect_value(t, compound_of(.Ethanol).name, "Ethanol")
	testing.expect_value(t, compound_of(.Ethanol).formula, "C2H5OH")
	testing.expect_value(t, compound_of(.Chlorine).phase, Phase.Gas)
	testing.expect_value(t, compound_of(.Persulfate).phase, Phase.Solid)
	testing.expect_value(t, compound_of(.Ethanol).color, [3]u8{0xb7, 0x9a, 0xe0})
	testing.expect_value(t, compound_of(.Ethanol).seed, u32(303))
	testing.expect_value(t, compound_of(.Ethanol).effect, Liquid_Effect.Swirl)
	testing.expect(t, near(compound_of(.Ethanol).flash_c, 13), "ethanol flashes at 13 degrees")
}

@(test)
pages_hold_what_they_hold :: proc(t: ^testing.T) {
	testing.expect_value(t, REACTION_COUNT, 11)
	testing.expect_value(t, ELECTROLYSIS_COUNT, 9)
	testing.expect_value(t, FORM_COUNT, 9)
	testing.expect(t, reaction_index("dilute_acid_clean") >= 0, "a reaction can be found by its id")
	testing.expect_value(t, reaction_index("no_such_reaction"), -1)
	r := reactions[reaction_index("ethyl_acetate_synthesis")]
	testing.expect_value(t, r.owner, Id.Ethanol)
	testing.expect_value(t, r.station, Station.Hot_Bath)
	testing.expect_value(t, r.catalyst, Id.Sulfuric_Acid)
	testing.expect_value(t, r.gear, Gear{.Goggles, .Gas_Mask})
	testing.expect_value(t, r.inputs.count, u16(2))
	d := reactions[reaction_index("spirit_and_acids")]
	testing.expect_value(t, d.inputs.count, u16(4))
	testing.expect_value(t, d.failure_outputs.count, u16(3))
	testing.expect_value(t, d.gear, Gear{.Ballistic_Shield, .Gas_Mask, .Fire_Extinguisher})
	for i in 0 ..< REACTION_COUNT {
		each := reactions[i]
		testing.expect(t, each.inputs.count >= 2, "every reaction has at least two inputs")
		testing.expect_value(t, parts[each.inputs.first].compound, each.owner)
	}
}

@(test)
purity_bands_include_their_floor_and_the_top_band_its_ceiling :: proc(t: ^testing.T) {
	cases := [?]struct {
		id:     Id,
		purity: f32,
		band:   string,
	}{{.Water, 0, "sink"}, {.Water, 0.3, "sink"}, {.Water, 0.5, "distilled"}, {.Water, 0.94, "distilled"}, {.Water, 0.95, "ultra_pure"}, {.Water, 1, "ultra_pure"}, {.Acetic_Acid, 0.49, "dilute"}, {.Acetic_Acid, 0.5, "glacial"}}
	for c in cases {
		f, ok := form_of(c.id, c.purity)
		testing.expect(t, ok && f.id == c.band, "the band a purity falls in")
	}
	f, _ := form_of(.Water, 0.7)
	testing.expect_value(t, f.label, "Distilled water")
	_, ok := form_of(.Hydrogen, 0.5)
	testing.expect(t, !ok, "a compound with no bands has none")
	_, ok = form_of(.Water, 1.2)
	testing.expect(t, !ok, "and a purity past 1 is in none")
}

@(test)
pouring_joins_the_same_compound_and_averages_what_it_should :: proc(t: ^testing.T) {
	m := start(10)
	testing.expect(t, mix_add(&m, .Water, 300, 1.0, 10), "the first pour goes in")
	testing.expect(t, mix_add(&m, .Water, 100, 0.2, 90), "and more of the same joins it")
	testing.expect_value(t, m.count, 1)
	testing.expect(t, near(m.items[0].ml, 400), "the amounts add")
	testing.expect(t, near(m.items[0].purity, 0.8), "the purities are the mean by volume")
	testing.expect(t, near(m.heat_c, 30), "so is the temperature")
	testing.expect(t, !mix_add(&m, .None, 100, 1, 20), "nothing is not poured")
	testing.expect(t, !mix_add(&m, .Water, 0, 1, 20), "and neither is no amount")
	testing.expect_value(t, m.count, 1)
}

@(test)
a_mixture_holds_eight_compounds_and_no_more :: proc(t: ^testing.T) {
	m := start()
	for i in 1 ..= MAX_INGREDIENTS {
		testing.expect(t, mix_add(&m, Id(i), 10, 1, 20), "room for another compound")
	}
	testing.expect_value(t, m.count, MAX_INGREDIENTS)
	before := m
	testing.expect(t, !mix_add(&m, .Chlorine, 10, 1, 20), "a ninth does not fit")
	testing.expect_value(t, m, before)
	testing.expect(t, mix_add(&m, .Water, 10, 1, 20), "though more of one that is in still does")
}

@(test)
acid_into_clean_water_dilutes_it :: proc(t: ^testing.T) {
	m := start()
	pour(&m, .Water, 900, 0.7)
	pour(&m, .Sulfuric_Acid, 100)
	done := settle(&m, .Any)
	testing.expect_value(t, done.count, 1)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("dilute_acid_clean"))
	testing.expect_value(t, done.steps[0].event, Event.None)
	testing.expect_value(t, m.count, 1)
	testing.expect_value(t, m.items[0].compound, Id.Dilute_Sulfuric_Acid)
	testing.expect(t, near(m.items[0].ml, 1000), "the whole volume is kept")
	testing.expect(t, near(m.items[0].purity, 0.73, 0.001), "a purity of -1 is the mean by volume: 0.7 for 900, 1 for 100")
	testing.expect(t, near(m.heat_c, 60), "it warms by 40 degrees")
	testing.expect(t, near(m.unsafe, 0.5), "and adds 0.5 to the unsafe meter")
	testing.expect(t, m.items[0].made, "the product was made, not poured")
	testing.expect_value(t, settle(&m, .Any).count, 0)
}

@(test)
sink_water_makes_a_cloudier_acid :: proc(t: ^testing.T) {
	m := start()
	pour(&m, .Water, 900, 0.25)
	pour(&m, .Sulfuric_Acid, 100)
	done := settle(&m, .Any)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("dilute_acid_sink"))
	testing.expect_value(t, m.items[0].compound, Id.Dilute_Sulfuric_Acid)
	testing.expect(t, near(m.items[0].purity, 0.5), "the product comes out at the purity the page gives")
	testing.expect(t, near(m.unsafe, 0.7), "and is more unsafe")
}

@(test)
water_into_acid_splashes_and_makes_nothing :: proc(t: ^testing.T) {
	m := start()
	pour(&m, .Sulfuric_Acid, 100)
	pour(&m, .Water, 900, 0.7)
	done := settle(&m, .Any)
	testing.expect_value(t, done.count, 1)
	testing.expect(t, done.steps[0].wrong_order, "the wrong order is what happened")
	testing.expect_value(t, done.steps[0].event, Event.Splash)
	testing.expect(t, !done.steps[0].failed, "it is not a failure")
	testing.expect_value(t, m.count, 2)
	testing.expect(t, near(amount(&m, .Sulfuric_Acid), 100) && near(amount(&m, .Water), 900), "the vessel is as it was")
	testing.expect_value(t, settle(&m, .Any).count, 0)
	// More water poured in gives it another go at splashing.
	pour(&m, .Water, 5, 0.7)
	testing.expect_value(t, settle(&m, .Any).count, 1)
}

@(test)
a_mix_that_is_off_its_ratio_does_nothing :: proc(t: ^testing.T) {
	m := start()
	pour(&m, .Water, 500, 0.7)
	pour(&m, .Sulfuric_Acid, 500)
	testing.expect_value(t, settle(&m, .Any).count, 0)
	// 9 to 1 with a tolerance of a half: the share of acid may be from 0.05 to 0.15.
	for acid in ([?]f32{60, 100, 140}) {
		w := start()
		pour(&w, .Water, 1000 - acid, 0.7)
		pour(&w, .Sulfuric_Acid, acid)
		testing.expect_value(t, settle(&w, .Any).count, 1)
	}
	for acid in ([?]f32{10, 30, 170, 300}) {
		w := start()
		pour(&w, .Water, 1000 - acid, 0.7)
		pour(&w, .Sulfuric_Acid, acid)
		testing.expect_value(t, settle(&w, .Any).count, 0)
	}
}

@(test)
a_boiling_mix_fails_and_the_failure_is_the_splash :: proc(t: ^testing.T) {
	m := start(100)
	pour(&m, .Water, 900, 0.7)
	pour(&m, .Sulfuric_Acid, 100)
	done := settle(&m, .Any)
	testing.expect_value(t, done.count, 1)
	testing.expect(t, done.steps[0].failed, "at 100 degrees the acid mix goes wrong")
	testing.expect_value(t, done.steps[0].event, Event.Splash)
	testing.expect_value(t, m.count, 2)
	testing.expect(t, near(m.heat_c, 100) && near(m.unsafe, 0), "a failure that makes nothing leaves the vessel as it is")
	testing.expect_value(t, settle(&m, .Any).count, 0)

	cool := start(99.9)
	pour(&cool, .Water, 900, 0.7)
	pour(&cool, .Sulfuric_Acid, 100)
	testing.expect(t, !settle(&cool, .Any).steps[0].failed, "just under the limit it runs")
}

@(test)
a_reaction_with_no_outputs_leaves_the_ingredients_and_runs_once :: proc(t: ^testing.T) {
	m := start()
	pour(&m, .Water, 500, 0.7)
	pour(&m, .Ethanol, 500, 0.8)
	done := settle(&m, .Any)
	testing.expect_value(t, done.count, 1)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("hydrated_spirit"))
	testing.expect_value(t, m.count, 2)
	testing.expect(t, near(amount(&m, .Water), 500) && near(amount(&m, .Ethanol), 500), "the ingredients stay")
	testing.expect(t, near(m.heat_c, 22) && near(m.unsafe, 0.05), "it warms by 2 degrees and adds 0.05 once")
	testing.expect_value(t, settle(&m, .Any).count, 0)
	testing.expect(t, near(m.heat_c, 22), "settling again changes nothing")
	pour(&m, .Water, 10, 0.7)
	testing.expect_value(t, settle(&m, .Any).count, 1)
	testing.expect(t, near(m.heat_c, 24, 0.1), "pouring in more lets it run again, and the heat adds up")
}

@(test)
the_reaction_with_the_most_inputs_runs :: proc(t: ^testing.T) {
	m := start(40)
	pour(&m, .Water, 250, 1)
	pour(&m, .Ethanol, 250, 0.95)
	pour(&m, .Acetic_Acid, 250, 0.9)
	pour(&m, .Sulfuric_Acid, 250, 1)
	done := settle(&m, .Any)
	testing.expect_value(t, done.count, 1)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("spirit_and_acids"))
	testing.expect_value(t, m.count, 2)
	testing.expect(t, near(amount(&m, .Ethyl_Acetate), 500) && near(amount(&m, .Water), 500), "a million parts split by the parts of the outputs")
	testing.expect(t, near(m.heat_c, 41) && near(m.unsafe, 0.3), "with the page's heat and unsafe")
}

@(test)
all_four_hot_burst_into_the_failure_outputs :: proc(t: ^testing.T) {
	m := start(160)
	pour(&m, .Water, 250, 1)
	pour(&m, .Ethanol, 250, 0.95)
	pour(&m, .Acetic_Acid, 250, 0.9)
	pour(&m, .Sulfuric_Acid, 250, 1)
	done := settle(&m, .Any)
	testing.expect_value(t, done.count, 1)
	testing.expect(t, done.steps[0].failed, "it failed")
	testing.expect_value(t, done.steps[0].event, Event.Burst)
	testing.expect_value(t, m.count, 3)
	third := f32(1000) / 3
	testing.expect(t, near(amount(&m, .Diethyl_Ether), third) && near(amount(&m, .Ethylene), third) && near(amount(&m, .Sulfur_Dioxide), third), "the failure outputs in place of the outputs")
	testing.expect_value(t, settle(&m, .Any).count, 0)
}

@(test)
a_catalyst_is_needed_and_is_not_used_up :: proc(t: ^testing.T) {
	m := start(80)
	pour(&m, .Ethanol, 500, 0.95)
	pour(&m, .Acetic_Acid, 500, 0.8)
	testing.expect_value(t, settle(&m, .Hot_Bath).count, 0)
	pour(&m, .Sulfuric_Acid, 20)
	done := settle(&m, .Hot_Bath)
	testing.expect_value(t, done.count, 1)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("ethyl_acetate_synthesis"))
	testing.expect(t, near(amount(&m, .Ethyl_Acetate), 500) && near(amount(&m, .Water), 500), "ethyl acetate and water")
	testing.expect(t, near(amount(&m, .Sulfuric_Acid), 20), "the catalyst is still there, all of it")
	testing.expect_value(t, amount(&m, .Ethanol), 0)
	testing.expect(t, near(m.heat_c, 83), "the reaction warmed it by 3")
	testing.expect(t, near(m.items[mix_find(&m, .Water)].purity, 0.875, 0.001), "water made from ethanol and acetic acid has their mean purity")
}

@(test)
a_reaction_needs_its_station_and_its_window_and_its_purity :: proc(t: ^testing.T) {
	mix :: proc(heat, ethanol_purity: f32) -> Mixture {
		m := start(heat)
		pour(&m, .Ethanol, 500, ethanol_purity)
		pour(&m, .Acetic_Acid, 500, 0.8)
		pour(&m, .Sulfuric_Acid, 20)
		return m
	}
	a := mix(80, 0.95)
	testing.expect_value(t, settle(&a, .Any).count, 0)
	b := mix(80, 0.95)
	testing.expect_value(t, settle(&b, .Cold_Bath).count, 0)
	c := mix(74.9, 0.95)
	testing.expect_value(t, settle(&c, .Hot_Bath).count, 0)
	d := mix(90, 0.95)
	testing.expect_value(t, settle(&d, .Hot_Bath).count, 0)
	e := mix(80, 0.5)
	testing.expect_value(t, settle(&e, .Hot_Bath).count, 0)
	f := mix(75, 0.95)
	testing.expect_value(t, settle(&f, .Hot_Bath).count, 1)
	g := mix(89.9, 0.9)
	testing.expect_value(t, settle(&g, .Hot_Bath).count, 1)
}

@(test)
ethanol_and_the_acid_make_three_things_at_three_temperatures :: proc(t: ^testing.T) {
	mix :: proc(heat: f32) -> Mixture {
		m := start(heat)
		pour(&m, .Ethanol, 667, 0.95)
		pour(&m, .Sulfuric_Acid, 333, 0.9)
		return m
	}
	cold := mix(20)
	done := settle(&cold, .Any)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("ethyl_hydrogen_sulfate"))
	testing.expect(t, near(amount(&cold, .Ethyl_Hydrogen_Sulfate), 1000), "cold the acid takes up the spirit")

	bath := mix(140)
	done = settle(&bath, .Hot_Bath)
	testing.expect_value(t, done.count, 1)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("diethyl_ether"))
	testing.expect(t, !done.steps[0].failed, "the ether runs, and the cold reaction does not fail beside it")
	testing.expect(t, near(amount(&bath, .Diethyl_Ether), 500) && near(amount(&bath, .Water), 500), "ether and water")

	furnace := mix(170)
	done = settle(&furnace, .Furnace)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("ethylene"))
	testing.expect(t, near(amount(&furnace, .Ethylene), 500), "ethylene in the furnace")

	over := mix(190)
	done = settle(&over, .Furnace)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("ethylene"))
	testing.expect_value(t, done.steps[0].event, Event.Burst)
	testing.expect(t, done.steps[0].failed, "too hot in the furnace is the ethylene failure and not the fumes of the cold reaction")

	hot_cold := mix(60)
	done = settle(&hot_cold, .Any)
	testing.expect(t, done.count == 1 && done.steps[0].failed && done.steps[0].event == .Fumes, "poured hot at no special station the cold reaction fails in fumes")
}

@(test)
what_is_not_unlocked_does_not_run :: proc(t: ^testing.T) {
	clean := u64(1) << u64(reaction_index("dilute_acid_clean"))
	m := start()
	pour(&m, .Water, 900, 0.7)
	pour(&m, .Sulfuric_Acid, 100)
	testing.expect_value(t, settle(&m, .Any, ALL_UNLOCKED & ~clean).count, 0)
	testing.expect_value(t, m.count, 2)
	testing.expect_value(t, settle(&m, .Any, clean).count, 1)
	none := start()
	pour(&none, .Water, 500, 0.7)
	pour(&none, .Ethanol, 500, 0.8)
	testing.expect_value(t, settle(&none, .Any, 0).count, 0)
}

@(test)
a_made_compound_cannot_be_poured_in_the_wrong_order :: proc(t: ^testing.T) {
	// Water made by a reaction that has acid in the vessel as a catalyst is not water poured in after the acid.
	m := start(80)
	pour(&m, .Ethanol, 500, 0.95)
	pour(&m, .Acetic_Acid, 500, 0.8)
	pour(&m, .Sulfuric_Acid, 52)
	done := settle(&m, .Hot_Bath)
	testing.expect_value(t, done.count, 2)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("ethyl_acetate_synthesis"))
	testing.expect_value(t, done.steps[1].reaction, reaction_index("dilute_acid_clean"))
	testing.expect(t, !done.steps[1].wrong_order, "made water is not a wrong order")
	testing.expect_value(t, m.items[0].compound, Id.Ethyl_Acetate)
}

@(test)
colour_seed_and_clarity_of_a_mix :: proc(t: ^testing.T) {
	m := start()
	testing.expect_value(t, mix_color(&m), [3]f32{1, 1, 1})
	testing.expect_value(t, mix_clarity(&m), f32(1))
	pour(&m, .Water, 500)
	testing.expect_value(t, mix_seed(&m), u32(101))
	testing.expect(t, near(mix_color(&m).r, 111.0 / 255, 0.001), "one compound is its own colour")
	pour(&m, .Acetic_Acid, 500)
	c := mix_color(&m)
	testing.expect(t, near(c.r, (111.0 + 230) / 2 / 255, 0.001) && near(c.g, (180.0 + 210) / 2 / 255, 0.001) && near(c.b, (232.0 + 122) / 2 / 255, 0.001), "the colours blend by volume")
	testing.expect(t, near(mix_clarity(&m), 0.85, 0.001), "and so does clarity: 0.9 and 0.8")
	n := start()
	pour(&n, .Acetic_Acid, 500)
	pour(&n, .Water, 500)
	testing.expect_value(t, mix_seed(&n), mix_seed(&m))
	testing.expect(t, mix_seed(&m) != 101 && mix_seed(&m) != 202, "a mix has a seed of its own")
	pour(&m, .Water, 1000)
	c = mix_color(&m)
	testing.expect(t, c.b > (232.0 + 122) / 2 / 255, "more water makes it bluer")
}

@(test)
electrolysis_is_found_by_purity_band :: proc(t: ^testing.T) {
	run, ok := electrolysis_of(.Water, 0.3)
	testing.expect(t, ok && run.form == "sink" && run.event == .Fumes, "sink water makes fumes")
	testing.expect_value(t, run.products.count, u16(3))
	testing.expect_value(t, products[run.products.first].compound, Id.Hydrogen)
	run, ok = electrolysis_of(.Water, 0.99)
	testing.expect(t, ok && run.form == "ultra_pure" && run.catalyst == .Sulfuric_Acid, "ultra pure water needs the acid")
	run, ok = electrolysis_of(.Sulfuric_Acid, 0.9)
	testing.expect(t, ok && products[run.products.first].compound == .Persulfate, "strong acid makes persulfate")
	_, ok = electrolysis_of(.Ethyl_Acetate, 0.5)
	testing.expect(t, !ok, "a compound with no electrolysis has none")
}

@(test)
a_mixture_with_nothing_in_it_reacts_to_nothing :: proc(t: ^testing.T) {
	m := start()
	testing.expect_value(t, settle(&m, .Any).count, 0)
	pour(&m, .Water, 100)
	testing.expect_value(t, settle(&m, .Any).count, 0)
	testing.expect_value(t, mix_volume(&m), f32(100))
}

@(test)
a_made_compound_does_not_count_for_the_order_whichever_input_it_is :: proc(t: ^testing.T) {
	// The acid is first in the list, so it went in before the water, unless a reaction made it.
	poured := start()
	poured.items[0] = {.Sulfuric_Acid, 100, 1, false}
	poured.items[1] = {.Water, 900, 0.7, false}
	poured.count = 2
	testing.expect(t, settle(&poured, .Any).steps[0].wrong_order, "poured acid first is the wrong order")
	made := start()
	made.items[0] = {.Sulfuric_Acid, 100, 1, true}
	made.items[1] = {.Water, 900, 0.7, false}
	made.count = 2
	done := settle(&made, .Any)
	testing.expect(t, done.count == 1 && !done.steps[0].wrong_order, "acid that was made is not acid that was poured in first")
	testing.expect_value(t, made.items[0].compound, Id.Dilute_Sulfuric_Acid)
}

@(test)
the_unsafe_meter_makes_a_run_fail_inside_its_window :: proc(t: ^testing.T) {
	mix :: proc(unsafe, heat: f32) -> Mixture {
		m := start(heat)
		m.unsafe = unsafe
		pour(&m, .Water, 900, 0.7)
		pour(&m, .Sulfuric_Acid, 100)
		return m
	}
	// The dilution adds 0.5 to the meter, and the meter reaching 1 is a failure.
	a := mix(0.5, 20)
	done := settle(&a, .Any)
	testing.expect(t, done.count == 1 && done.steps[0].failed && done.steps[0].event == .Splash, "a meter that would reach 1 fails the reaction")
	testing.expect_value(t, a.count, 2)
	b := mix(0.49, 20)
	testing.expect(t, !settle(&b, .Any).steps[0].failed, "and one that stays under 1 does not")

	// Outside its window a reaction does not fail because of the meter: it does not act at all.
	c := start(60)
	c.unsafe = 0.9
	pour(&c, .Ethanol, 500, 0.95)
	pour(&c, .Acetic_Acid, 500, 0.8)
	pour(&c, .Sulfuric_Acid, 20)
	testing.expect_value(t, settle(&c, .Hot_Bath).count, 0)
}

@(test)
the_unsafe_meter_stops_at_one :: proc(t: ^testing.T) {
	quiet := start()
	quiet.unsafe = 0.98
	pour(&quiet, .Water, 500, 0.7)
	pour(&quiet, .Ethanol, 500, 0.8)
	testing.expect_value(t, settle(&quiet, .Any).count, 1)
	testing.expect_value(t, quiet.unsafe, f32(1))

	burst := start(160)
	burst.unsafe = 0.9
	pour(&burst, .Water, 250, 1)
	pour(&burst, .Ethanol, 250, 0.95)
	pour(&burst, .Acetic_Acid, 250, 0.9)
	pour(&burst, .Sulfuric_Acid, 250, 1)
	testing.expect(t, settle(&burst, .Any).steps[0].failed, "it fails")
	testing.expect_value(t, burst.unsafe, f32(1))
}

@(test)
four_inputs_beat_two_even_when_the_two_have_their_own_station :: proc(t: ^testing.T) {
	m := start(80)
	pour(&m, .Water, 250, 1)
	pour(&m, .Ethanol, 250, 0.95)
	pour(&m, .Acetic_Acid, 250, 0.9)
	pour(&m, .Sulfuric_Acid, 250, 1)
	// Ethyl acetate synthesis is also possible here, in the hot bath, with the acid as its catalyst.
	done := settle(&m, .Hot_Bath)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("spirit_and_acids"))
}

@(test)
a_mix_never_has_the_seed_of_a_compound :: proc(t: ^testing.T) {
	for a in 1 ..= COMPOUND_COUNT {
		for b in a + 1 ..= COMPOUND_COUNT {
			m := start()
			pour(&m, Id(a), 10)
			pour(&m, Id(b), 10)
			seed := mix_seed(&m)
			for c in 0 ..< COMPOUND_COUNT {
				testing.expect(t, compounds[c].seed != seed, "a mix would be mistaken for a compound")
			}
		}
	}
}

@(test)
of_two_reactions_that_tie_the_one_listed_first_acts :: proc(t: ^testing.T) {
	// In a hot bath at 140 degrees ether can run, and ethyl acetate synthesis, which is also made for the hot
	// bath and has the same number of inputs, is past its limit and could fail. Both are on the ethanol page,
	// and the ether is listed before the synthesis.
	m := start(140)
	pour(&m, .Ethanol, 400, 0.95)
	pour(&m, .Acetic_Acid, 400, 0.9)
	pour(&m, .Sulfuric_Acid, 200, 0.9)
	done := settle(&m, .Hot_Bath)
	testing.expect_value(t, done.steps[0].reaction, reaction_index("diethyl_ether"))
	testing.expect(t, reaction_index("diethyl_ether") < reaction_index("ethyl_acetate_synthesis"), "the ether is listed first")
	testing.expect(t, !done.steps[0].failed, "and it runs")
}
