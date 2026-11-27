// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout_test.odin"
// ============================================================================

package carry

import "../chemistry"
import "../lab"
import "core:testing"

new_loadout :: proc() -> Loadout {
	return Loadout{spot_slot = -1}
}

balloon :: proc(compound: u16, ml: f32) -> Item {
	item := Item {
		used = true,
	}
	fill_with(&item.mix, compound, ml)
	return item
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

	incinerator, _ := lab.placed_find(&props.placed, .Incinerator)
	p.x, p.z = incinerator.x, 6.9
	look_at(p, lab.incinerator_mouth(incinerator))
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.Burn)
	testing.expect_value(t, lo.spot_slot, -1)

	p.x, p.z = -10.98, lab.TABLET_CENTER.z
	look_at(p, lab.TABLET_CENTER)
	filler_aim(&f, props, view_of(p))
	loadout_aim(&lo, &f, props, view_of(p))
	testing.expect_value(t, lo.spot, Spot.Tablet)

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
	fill_with(&f.mix, id(.Water), 400)
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
	lo.paint = balloon(id(.Ethyl_Acetate), 50)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // taken
	lo.hand = {}
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Take_Paint)

	lo.spot = .Tablet
	lo.paint = {}
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // no balloon clamped to draw on
	lo.paint = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Paint)
	lo.hand = balloon(id(.Ethyl_Acetate), 50)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Paint) // a balloon in the hand does not stop it
	lo.hand = {}
	lo.paint = {}

	lo.spot, lo.spot_slot = .Slot, 1
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // hand empty, hook empty
	lo.hand = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Store)
	lo.slots[1] = balloon(id(.Ethyl_Acetate), 50)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // the hook is taken
	lo.hand = {}
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Take_Slot)

	lo.spot = .Burn
	lo.hand = {}
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // nothing in the hand to burn
	lo.hand = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Burn)
	lo.paint = balloon(id(.Ethyl_Acetate), 50) // balloons elsewhere do not matter
	lo.slots[0] = balloon(id(.Ethyl_Acetate), 50)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.Burn)
	lo.hand, lo.paint, lo.slots[0] = {}, {}, {}

	lo.spot, lo.spot_slot = .Slot, 1
	props_add(props, l, .Beaker, 0, 0.5)
	props.held = 0
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // a vessel in the hands
	lo.spot = .Burn
	lo.hand = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // and none for burning either
	lo.spot = .Tablet
	lo.paint = balloon(id(.Water), 100)
	testing.expect_value(t, balloon_action(&lo, &f, props), Balloon_Action.None) // and none for drawing either
}

@(test)
drawing_moves_nothing :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	lo.paint = balloon(id(.Water), 400)
	lo.paint.art = 3
	lo.hand = balloon(id(.Ethyl_Acetate), 50)
	before := lo
	_, ok := balloon_do(&lo, &f, .Paint)
	testing.expect(t, ok, "it can start")
	testing.expect_value(t, lo.paint, before.paint)
	testing.expect_value(t, lo.hand, before.hand)
	lo.paint = {}
	_, ok = balloon_do(&lo, &f, .Paint)
	testing.expect(t, !ok, "with no balloon there is nothing to draw on")
}

@(test)
tying_a_balloon_takes_what_is_in_it_and_the_station_makes_another :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	fill_with(&f.mix, id(.Ethanol), 640, 50)
	chemistry.mix_add(&f.mix, .Water, 100, 0.25, 50)
	before := f.mix
	let_out, ok := balloon_do(&lo, &f, .Tie_Take)
	testing.expect(t, ok, "it works")
	testing.expect_value(t, let_out, 0)
	testing.expect_value(t, lo.hand, Item{used = true, mix = before})
	testing.expect_value(t, lo.hand.mix.count, 2)
	testing.expect_value(t, lo.hand.mix.heat_c, f32(50))
	testing.expect(t, !f.present, "the clamp is empty")
	testing.expect_value(t, ml_of(&f.mix), 0)
	testing.expect_value(t, f.mix.heat_c, 0)
	filler_update(&f, FILLER_RESPAWN + 0.1)
	testing.expect(t, f.present, "and fresh in a moment")
	testing.expect_value(t, ml_of(&f.mix), 0)
	_, again := balloon_do(&lo, &f, .Tie_Take)
	testing.expect(t, !again, "an empty balloon is not tied")
}

@(test)
a_stretched_balloon_is_let_down_to_full_when_tied :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	fill_with(&f.mix, id(.Water), 1250)
	let_out, ok := balloon_do(&lo, &f, .Tie_Take)
	testing.expect(t, ok, "it works")
	testing.expect_value(t, ml_of(&lo.hand.mix), BALLOON_REST_ML)
	testing.expect_value(t, let_out, 250)
}

@(test)
balloons_move_between_the_hand_the_paint_station_and_the_hooks_unchanged :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	item := balloon(id(.Ethanol), 777)
	item.mix.heat_c = 5
	item.art = 42
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
burning_takes_the_balloon_in_the_hand_and_nothing_else :: proc(t: ^testing.T) {
	f := fresh_filler()
	lo := new_loadout()
	kept := balloon(id(.Ethanol), 600)
	kept.art = 9
	lo.paint = kept
	lo.slots[0] = kept
	lo.slots[2] = kept
	lo.hand = balloon(id(.Ethyl_Acetate), 800)
	_, ok := balloon_do(&lo, &f, .Burn)
	testing.expect(t, ok && !lo.hand.used, "the balloon in the hand is gone")
	testing.expect(t, lo.hand == Item{}, "and nothing of it is left in the hand")
	testing.expect(t, lo.paint == kept && lo.slots[0] == kept && lo.slots[2] == kept && !lo.slots[1].used, "the others are as they were")
	testing.expect_value(t, loadout_count(&lo), 2)
	_, ok = balloon_do(&lo, &f, .Burn)
	testing.expect(t, !ok, "with empty hands there is nothing to burn")
	testing.expect_value(t, loadout_count(&lo), 2)
}

@(test)
the_presets_are_what_the_server_needs_of_the_balloons_on_the_hooks :: proc(t: ^testing.T) {
	lo := new_loadout()
	testing.expect_value(t, loadout_count(&lo), 0)
	_, n := loadout_presets(&lo)
	testing.expect_value(t, n, 0)

	lo.slots[0] = balloon(id(.Ethanol), 640.4)
	lo.slots[0].art = 7
	chemistry.mix_add(&lo.slots[0].mix, .Water, 0.2, 0.25, ROOM_C)
	lo.slots[2] = balloon(id(.Acetic_Acid), 999.7)
	lo.paint = balloon(id(.Water), 500) // not on a hook, so not in the loadout
	lo.hand = balloon(id(.Water), 500)
	out, count := loadout_presets(&lo)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, out[0], Preset{mix = lo.slots[0].mix, compound = id(.Ethanol), volume_ml = 641, art = 7})
	testing.expect_value(t, out[0].mix.count, 2) // the whole mixture goes, not only what there is most of
	testing.expect_value(t, out[1], Preset{mix = lo.slots[2].mix, compound = id(.Acetic_Acid), volume_ml = 1000, art = 0})

	lo.slots[1] = balloon(id(.Water), 5000) // cannot happen, and is held to a full balloon if it does
	out, count = loadout_presets(&lo)
	testing.expect_value(t, count, 3)
	testing.expect_value(t, out[1].volume_ml, 1000)
}

@(test)
the_incinerator_is_burned_in_wherever_it_stands :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	f := fresh_filler()
	lo := new_loadout()
	start, _ := lab.placed_find(&props.placed, .Incinerator)
	aim_at :: proc(p: ^lab.Player, props: ^Props, f: ^Filler, lo: ^Loadout, at: Vec3, from_x: f32) {
		p.x, p.z = from_x, at.z - 0.8
		look_at(p, at)
		filler_aim(f, props, view_of(p))
		loadout_aim(lo, f, props, view_of(p))
	}
	aim_at(p, props, &f, &lo, lab.incinerator_mouth(start), start.x)
	testing.expect_value(t, lo.spot, Spot.Burn)
	// Moved along the counter to the free place between the fill station and the rack, the mouth is there.
	for i in 0 ..< props.placed.count {
		if props.placed.items[i].kind == .Incinerator {
			props.placed.items[i].x = 7.3
		}
	}
	moved, _ := lab.placed_find(&props.placed, .Incinerator)
	aim_at(p, props, &f, &lo, lab.incinerator_mouth(moved), 7.3)
	testing.expect_value(t, lo.spot, Spot.Burn)
	testing.expect_value(t, lo.spot_slot, -1)
	// And not where it stood.
	aim_at(p, props, &f, &lo, lab.incinerator_mouth(start), start.x)
	testing.expect_value(t, lo.spot, Spot.None)
	// Turned about, the mouth is still the place to aim at.
	for i in 0 ..< props.placed.count {
		if props.placed.items[i].kind == .Incinerator {
			props.placed.items[i].quarter = 2
		}
	}
	turned, _ := lab.placed_find(&props.placed, .Incinerator)
	aim_at(p, props, &f, &lo, lab.incinerator_mouth(turned), 7.3)
	testing.expect_value(t, lo.spot, Spot.Burn)
	// Taken off the counter, there is nothing to burn a balloon in anywhere.
	for i in 0 ..< props.placed.count {
		if props.placed.items[i].kind == .Incinerator {
			lab.placed_remove(&props.placed, i)
			break
		}
	}
	aim_at(p, props, &f, &lo, lab.incinerator_mouth(moved), 7.3)
	testing.expect_value(t, lo.spot, Spot.None)
	aim_at(p, props, &f, &lo, lab.incinerator_mouth(start), start.x)
	testing.expect_value(t, lo.spot, Spot.None)
}
