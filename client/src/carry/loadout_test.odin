// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout_test.odin"
// ============================================================================

package carry

import "../lab"
import "core:testing"

new_loadout :: proc() -> Loadout {
	return Loadout{spot_slot = -1}
}

balloon :: proc(compound: u16, ml: f32) -> Item {
	return {used = true, compound = compound, ml = ml}
}

@(test)
the_crosshair_finds_the_paint_station_and_each_hook :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	lo := new_loadout()

	p.x, p.z = -10.98, lab.PAINT_CLAMP.z
	look_at(p, lab.PAINT_CLAMP)
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.Paint)

	for i in 0 ..< LOADOUT_SLOTS {
		c := lab.slot_clamp(i)
		p.x, p.z = c.x, 6.9
		look_at(p, c)
		filler_aim(&f, props, view_of(p))
		loadout_aim(&lo, &f, props, view_of(p))
		testing.expect_value(t, lo.spot, Spot.Slot)
		testing.expect_value(t, lo.spot_slot, i)
	}

	p.x, p.z = lab.FILLER_CLAMP.x, 6.9
	look_at(p, lab.FILLER_MOUTH)
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.Fill)
	testing.expect_value(t, lo.spot_slot, -1)

	look_at(p, {0, 1.6, 0})
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.None)
}

@(test)
nothing_is_aimed_at_when_too_far_or_when_a_vessel_is_nearer :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	lo := new_loadout()
	c := lab.slot_clamp(1)
	p.x, p.z = c.x, 3.0
	look_at(p, c)
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.None) // too far

	p.z = 6.9
	look_at(p, c)
	props.aimed, props.aimed_t = 0, 0.2
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.None) // a vessel is nearer
	props.aimed = -1
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.Slot)
}

@(test)
the_grab_button_does_the_right_thing_at_each_place :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	lo := new_loadout()

	lo.spot = .Fill
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // nothing in the balloon
	f.compound, f.ml = id(.Water), 400
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Tie_Take)
	lo.hand = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // the hand is full
	lo.hand = {}
	f.present = false
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // no balloon there

	lo.spot = .Paint
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // nothing to do
	lo.hand = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Clamp)
	lo.paint = balloon(id(.Slurry), 50)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // taken
	lo.hand = {}
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Take_Paint)

	lo.spot, lo.spot_slot = .Slot, 1
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // hand empty, hook empty
	lo.hand = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Store)
	lo.slots[1] = balloon(id(.Slurry), 50)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // the hook is taken
	lo.hand = {}
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Take_Slot)

	props_add(props, l, .Beaker, 0, 0.5)
	props.held = 0
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // a vessel in the hands
}

@(test)
tying_a_balloon_takes_what_is_in_it_and_the_station_makes_another :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	f.compound, f.ml, f.heat = id(.Fizz_Acid), 640, 0.5
	let_out, ok := balloon_do(&lo, &f, .Tie_Take)
	testing.expect(t, ok, "it works")
	testing.expect_value(t, let_out, 0)
	testing.expect_value(t, lo.hand, Item{used = true, compound = id(.Fizz_Acid), ml = 640, heat = 0.5})
	testing.expect(t, !f.present, "the clamp is empty")
	testing.expect_value(t, f.ml, 0)
	testing.expect_value(t, f.heat, 0)
	filler_update(&f, FILLER_RESPAWN + 0.1)
	testing.expect(t, f.present, "and fresh in a moment")
	testing.expect_value(t, f.ml, 0)
	_, again := balloon_do(&lo, &f, .Tie_Take)
	testing.expect(t, !again, "an empty balloon is not tied")
}

@(test)
a_stretched_balloon_is_let_down_to_full_when_tied :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	f.compound, f.ml = id(.Water), 1250
	let_out, ok := balloon_do(&lo, &f, .Tie_Take)
	testing.expect(t, ok, "it works")
	testing.expect_value(t, lo.hand.ml, BALLOON_REST_ML)
	testing.expect_value(t, let_out, 250)
}

@(test)
balloons_move_between_the_hand_the_paint_station_and_the_hooks_unchanged :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	item := Item {
		used     = true,
		compound = id(.Dye_Red),
		ml       = 777,
		heat     = -0.3,
		art      = 42,
	}
	lo.hand = item
	_, ok := balloon_do(&lo, &f, .Clamp)
	testing.expect(t, ok && !lo.hand.used && lo.paint == item, "clamped")
	_, ok = balloon_do(&lo, &f, .Take_Paint)
	testing.expect(t, ok && lo.hand == item && !lo.paint.used, "taken back")
	lo.spot_slot = 2
	_, ok = balloon_do(&lo, &f, .Store)
	testing.expect(t, ok && !lo.hand.used && lo.slots[2] == item, "hung on a hook")
	testing.expect_value(t, loadout_count(&lo), 1)
	_, ok = balloon_do(&lo, &f, .Take_Slot)
	testing.expect(t, ok && lo.hand == item && !lo.slots[2].used, "taken off it")
	testing.expect_value(t, loadout_count(&lo), 0)
	_, ok = balloon_do(&lo, &f, .None)
	testing.expect(t, !ok, "no action, no change")
	testing.expect(t, loadout_hands_full(&lo), "the hand holds it")
}

@(test)
the_presets_are_what_the_server_needs_of_the_balloons_on_the_hooks :: proc(t: ^testing.T) {
	lo := new_loadout()
	testing.expect_value(t, loadout_count(&lo), 0)
	_, n := loadout_presets(&lo)
	testing.expect_value(t, n, 0)

	lo.slots[0] = {used = true, compound = id(.Fizz_Acid), ml = 640.4, art = 7}
	lo.slots[2] = {used = true, compound = id(.Frost_Gel), ml = 999.7}
	lo.paint = balloon(id(.Water), 500) // not on a hook, so not in the loadout
	lo.hand = balloon(id(.Water), 500)
	out, count := loadout_presets(&lo)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, out[0], Preset{compound = id(.Fizz_Acid), volume_ml = 640, art = 7})
	testing.expect_value(t, out[1], Preset{compound = id(.Frost_Gel), volume_ml = 1000, art = 0})

	lo.slots[1] = {used = true, compound = id(.Water), ml = 5000} // cannot happen, and is held to a full balloon if it does
	out, count = loadout_presets(&lo)
	testing.expect_value(t, count, 3)
	testing.expect_value(t, out[1].volume_ml, 1000)
}
