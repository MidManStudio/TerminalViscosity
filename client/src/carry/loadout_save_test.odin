// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout_save_test.odin"
// ============================================================================

package carry

import "core:strings"
import "core:testing"

drawn :: proc(store: ^Art_Store, color: u8) -> u16 {
	id := art_new(store)
	c := art_get(store, id)
	canvas_dab(c, 100, 100, 30, color)
	canvas_dab(c, 255, 40, 12, color) // across the seam
	return id
}

@(test)
a_loadout_survives_being_saved_and_read_back :: proc(t: ^testing.T) {
	store, fresh := new(Art_Store), new(Art_Store)
	defer free(store)
	defer free(fresh)
	lo := new_loadout()
	lo.hand = Item{used = true, compound = id(.Water), ml = 400, heat = 0.7}
	lo.paint = Item{used = true, compound = id(.Dye_Red), ml = 1000, art = drawn(store, 5)}
	lo.slots[0] = Item{used = true, compound = id(.Fizz_Acid), ml = 640, art = drawn(store, 9)}
	lo.slots[2] = Item{used = true, compound = id(.Frost_Gel), ml = 1}
	text := loadout_serialize(&lo, store)
	defer delete(text)

	back := new_loadout()
	testing.expect_value(t, loadout_deserialize(text, &back, fresh), 4)
	testing.expect_value(t, back.hand.compound, id(.Water))
	testing.expect_value(t, back.hand.ml, 400)
	testing.expect_value(t, back.hand.heat, 0) // the temperature is not kept
	testing.expect(t, back.hand.art == 0, "no drawing, none made")
	testing.expect_value(t, back.paint.compound, id(.Dye_Red))
	testing.expect_value(t, back.paint.ml, 1000)
	testing.expect_value(t, back.slots[0].compound, id(.Fizz_Acid))
	testing.expect_value(t, back.slots[0].ml, 640)
	testing.expect(t, !back.slots[1].used, "an empty hook stays empty")
	testing.expect_value(t, back.slots[2].ml, 1)
	for pair in ([][2]^Item{{&lo.paint, &back.paint}, {&lo.slots[0], &back.slots[0]}}) {
		was, now := art_get(store, pair[0].art), art_get(fresh, pair[1].art)
		testing.expect(t, was != nil && now != nil, "the drawing came back")
		testing.expect(t, was.px == now.px, "pixel for pixel")
	}
	testing.expect(t, back.paint.art != back.slots[0].art, "each has a drawing of its own")
}

@(test)
an_empty_loadout_is_just_the_header_and_reads_back_empty :: proc(t: ^testing.T) {
	store := new(Art_Store)
	defer free(store)
	lo := new_loadout()
	text := loadout_serialize(&lo, store)
	defer delete(text)
	testing.expect_value(t, text, "tvloadout 1\n")
	testing.expect_value(t, loadout_deserialize(text, &lo, store), 0)
}

@(test)
text_without_the_header_is_not_read_at_all :: proc(t: ^testing.T) {
	store := new(Art_Store)
	defer free(store)
	lo := new_loadout()
	testing.expect_value(t, loadout_deserialize("item slot0 3 500 -\n", &lo, store), 0)
	testing.expect_value(t, loadout_deserialize("tvloadout 2\nitem slot0 3 500 -\n", &lo, store), 0)
	testing.expect_value(t, loadout_deserialize("", &lo, store), 0)
	testing.expect(t, !lo.slots[0].used, "nothing was put in")
}

@(test)
a_bad_line_is_skipped_and_the_good_ones_still_come_back :: proc(t: ^testing.T) {
	store := new(Art_Store)
	defer free(store)
	lo := new_loadout()
	text := strings.join(
		[]string{
			"tvloadout 1",
			"item slot0 3 500 -", // good
			"item nowhere 3 500 -", // no such place
			"item slot1 0 500 -", // no compound
			"item slot1 3 0 -", // no liquid
			"item slot1 3 99999 -", // more than a balloon holds
			"item slot1 3 abc -", // not a number
			"item slot1 3 500", // a field short
			"item slot1 3 500 - extra", // a field over
			"junk",
			"",
			"item slot1 7 250 zz", // art that is not hex: the balloon comes back without it
			"item slot2 9 1000 0100", // art that is hex but too short to decode
		},
		"\n",
		context.temp_allocator,
	)
	testing.expect_value(t, loadout_deserialize(text, &lo, store), 3)
	testing.expect_value(t, lo.slots[0].compound, 3)
	testing.expect(t, lo.slots[1].used && lo.slots[1].compound == 7 && lo.slots[1].art == 0, "a bad drawing is left off")
	testing.expect(t, lo.slots[2].used && lo.slots[2].art == 0, "and so is one that does not decode")
	count := 0
	for used in store.used {
		if used {
			count += 1
		}
	}
	testing.expect_value(t, count, 0) // and no drawing is left in use for them
}

@(test)
when_the_store_is_full_balloons_come_back_without_drawings :: proc(t: ^testing.T) {
	src, dst := new(Art_Store), new(Art_Store)
	defer free(src)
	defer free(dst)
	lo := new_loadout()
	lo.slots[0] = Item{used = true, compound = 3, ml = 100, art = drawn(src, 5)}
	text := loadout_serialize(&lo, src)
	defer delete(text)
	for _ in 0 ..< ART_POOL {
		art_new(dst)
	}
	back := new_loadout()
	testing.expect_value(t, loadout_deserialize(text, &back, dst), 1)
	testing.expect(t, back.slots[0].used && back.slots[0].art == 0, "the balloon came back, with no room for its drawing")
}

@(test)
the_place_names_are_the_hand_the_paint_station_and_each_hook :: proc(t: ^testing.T) {
	testing.expect_value(t, place_name(0), "hand")
	testing.expect_value(t, place_name(1), "paint")
	testing.expect_value(t, place_name(2), "slot0")
	testing.expect_value(t, place_name(2 + LOADOUT_SLOTS - 1), "slot2")
	lo := new_loadout()
	testing.expect(t, place_item(&lo, 0) == &lo.hand && place_item(&lo, 1) == &lo.paint, "the first two")
	testing.expect(t, place_item(&lo, 2) == &lo.slots[0], "then the hooks")
	testing.expect(t, place_item(&lo, 2 + LOADOUT_SLOTS) == nil, "and nothing after")
}

@(test)
the_amount_is_saved_to_the_nearest_millilitre :: proc(t: ^testing.T) {
	store := new(Art_Store)
	defer free(store)
	lo := new_loadout()
	lo.slots[0] = Item{used = true, compound = 3, ml = 640.6}
	lo.slots[1] = Item{used = true, compound = 3, ml = 640.4}
	text := loadout_serialize(&lo, store)
	defer delete(text)
	testing.expect(t, strings.contains(text, "item slot0 3 641 -"), "up")
	testing.expect(t, strings.contains(text, "item slot1 3 640 -"), "and down")
}
