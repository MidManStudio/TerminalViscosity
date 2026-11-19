// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stock_test.odin"
// ============================================================================

package carry

import "../chemistry"
import "../inventory"
import "../lab"
import "core:testing"

@(test)
the_wall_starts_with_a_dispenser_of_each_starting_chemical_but_water :: proc(t: ^testing.T) {
	s: Stock
	stock_init(&s)
	testing.expect_value(t, s.wall.size, lab.DISPENSER_COUNT)
	testing.expect_value(t, s.bag.size, BAG_SIZE)
	testing.expect_value(t, s.wall.slots[0], inventory.Slot{{.Dispenser, u16(chemistry.Id.Acetic_Acid)}, 1})
	testing.expect_value(t, s.wall.slots[1], inventory.Slot{{.Dispenser, u16(chemistry.Id.Ethanol)}, 1})
	testing.expect_value(t, s.wall.slots[2], inventory.Slot{{.Dispenser, u16(chemistry.Id.Sulfuric_Acid)}, 1})
	for i in 3 ..< lab.DISPENSER_COUNT {
		testing.expect_value(t, s.wall.slots[i].count, u16(0))
	}
	for i in 0 ..< BAG_SIZE {
		testing.expect_value(t, s.bag.slots[i].count, u16(0))
	}
	testing.expect_value(t, s.wall.requires, inventory.Tags{.Mountable})
}

@(test)
the_taps_follow_what_is_mounted_on_the_wall :: proc(t: ^testing.T) {
	s: Stock
	stock_init(&s)
	st: Station
	station_sync(&st, &s.wall)
	testing.expect_value(t, st.items[0], Dispenser{u16(chemistry.Id.Acetic_Acid), true})
	testing.expect_value(t, st.items[1], Dispenser{u16(chemistry.Id.Ethanol), true})
	testing.expect_value(t, st.items[2], Dispenser{u16(chemistry.Id.Sulfuric_Acid), true})
	testing.expect_value(t, st.items[3], Dispenser{})
	// Take the ethanol off the wall into the bag, and put it on mount 6.
	testing.expect(t, inventory.move(&s.wall, 1, &s.bag, 0), "into the bag")
	station_sync(&st, &s.wall)
	testing.expect_value(t, st.items[1], Dispenser{})
	testing.expect(t, inventory.move(&s.bag, 0, &s.wall, 6), "and onto mount 6")
	station_sync(&st, &s.wall)
	testing.expect_value(t, st.items[6], Dispenser{u16(chemistry.Id.Ethanol), true})
	testing.expect_value(t, st.items[1], Dispenser{})
}

@(test)
a_dispenser_with_nothing_in_it_gives_nothing_and_the_faucet_is_left_alone :: proc(t: ^testing.T) {
	s: Stock
	stock_init(&s)
	inventory.put(&s.wall, 4, {.Dispenser, 0}, 1)
	st: Station
	station_init(&st)
	station_sync(&st, &s.wall)
	testing.expect_value(t, st.items[4], Dispenser{})
	testing.expect_value(t, st.items[lab.SINK_TAP], Dispenser{u16(chemistry.Id.Water), true})
}

@(test)
syncing_clears_taps_that_were_set_before :: proc(t: ^testing.T) {
	st: Station
	for i in 0 ..< lab.DISPENSER_COUNT {
		st.items[i] = {7, true}
	}
	wall: inventory.Container
	inventory.container_init(&wall, lab.DISPENSER_COUNT, {.Mountable})
	station_sync(&st, &wall)
	for i in 0 ..< lab.DISPENSER_COUNT {
		testing.expect_value(t, st.items[i], Dispenser{})
	}
}

@(test)
a_wall_with_fewer_mounts_than_taps_leaves_the_rest_empty :: proc(t: ^testing.T) {
	wall: inventory.Container
	inventory.container_init(&wall, 2, {.Mountable})
	inventory.put(&wall, 1, {.Dispenser, 3}, 1)
	st: Station
	station_sync(&st, &wall)
	testing.expect_value(t, st.items[1], Dispenser{3, true})
	testing.expect_value(t, st.items[2], Dispenser{})
	colors, present := wall_look(&wall)
	testing.expect(t, present[1] && !present[0] && !present[2], "only the mounted one")
	testing.expect_value(t, colors[2], [4]u8{70, 74, 80, 255})
}

@(test)
the_taps_at_the_start_are_those_of_the_default_wall :: proc(t: ^testing.T) {
	a, b: Station
	station_init(&a)
	wall: inventory.Container
	wall_default(&wall)
	station_sync(&b, &wall)
	b.items[lab.SINK_TAP] = a.items[lab.SINK_TAP]
	testing.expect_value(t, a, b)
}

@(test)
the_look_of_the_wall_is_the_color_of_each_liquid_and_which_mounts_have_a_dispenser :: proc(t: ^testing.T) {
	s: Stock
	stock_init(&s)
	colors, present := wall_look(&s.wall)
	for i in 0 ..< lab.DISPENSER_COUNT {
		testing.expect_value(t, present[i], i < 3)
	}
	c := chemistry.compound_of(chemistry.Id.Ethanol)
	testing.expect_value(t, colors[1], [4]u8{c.color.r, c.color.g, c.color.b, 255})
	testing.expect_value(t, colors[5], [4]u8{70, 74, 80, 255})
	inventory.put(&s.wall, 5, {.Dispenser, 0}, 1) // a dispenser with nothing in it
	colors, present = wall_look(&s.wall)
	testing.expect(t, present[5], "it is there")
	testing.expect_value(t, colors[5], [4]u8{70, 74, 80, 255}) // and grey
	testing.expect_value(t, colors, station_colors_with(&s.wall))
}

// The colors for a wall, for the test above to compare with the one the lab starts with.
station_colors_with :: proc(wall: ^inventory.Container) -> [lab.DISPENSER_COUNT][4]u8 {
	colors, _ := wall_look(wall)
	return colors
}

@(test)
the_colors_the_lab_starts_with_are_those_of_the_default_wall :: proc(t: ^testing.T) {
	wall: inventory.Container
	wall_default(&wall)
	colors, _ := wall_look(&wall)
	testing.expect_value(t, station_colors(), colors)
}

@(test)
a_dispenser_in_a_slot_past_the_end_of_a_small_wall_gives_no_tap :: proc(t: ^testing.T) {
	wall: inventory.Container
	inventory.container_init(&wall, 2, {.Mountable})
	wall.slots[5] = {{.Dispenser, 3}, 1} // left over from a bigger wall, and not one of its slots
	st: Station
	station_sync(&st, &wall)
	testing.expect_value(t, st.items[5], Dispenser{})
	_, present := wall_look(&wall)
	testing.expect(t, !present[5], "and no bottle")
}
