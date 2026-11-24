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

@(test)
a_stock_is_a_bag_and_a_wall_and_a_station_is_an_item_of_the_bag :: proc(t: ^testing.T) {
	s: Stock
	stock_init(&s)
	testing.expect_value(t, s.bag.size, BAG_SIZE)
	testing.expect(t, inventory.can_move(&s.wall, 0, &s.bag, 0), "a dispenser moves from the wall to the bag")
	testing.expect_value(t, inventory.add(&s.bag, station_item(.Scale), 1), 1)
	testing.expect(t, !inventory.can_move(&s.bag, 0, &s.wall, 5), "a station does not go on the wall")
}

@(test)
station_items_and_station_kinds_map_both_ways :: proc(t: ^testing.T) {
	for kind in ([3]lab.Station_Kind{.Hot_Plate, .Ice_Bath, .Scale}) {
		testing.expect_value(t, item_station(station_item(kind)), kind)
	}
	testing.expect_value(t, station_item(.None), inventory.Item{})
	testing.expect_value(t, item_station(inventory.Item{.Dispenser, 3}), lab.Station_Kind.None)
	testing.expect_value(t, item_station(inventory.Item{}), lab.Station_Kind.None)
	testing.expect_value(t, station_item(.Hot_Plate), inventory.Item{.Hot_Plate, 0})
	testing.expect_value(t, station_item(.Ice_Bath), inventory.Item{.Ice_Bath, 0})
	testing.expect_value(t, station_item(.Scale), inventory.Item{.Scale, 0})
	testing.expect_value(t, station_name(.Hot_Plate), "hot plate")
	testing.expect_value(t, station_name(.Ice_Bath), "ice bath")
	testing.expect_value(t, station_name(.Scale), "scale")
	testing.expect_value(t, station_name(.None), "")
}

// A view that looks straight at the station that stands at (x, z) from the front, 0.9 m away, at the height of the counter
// top plus 4 cm, which is inside the box of every kind of station.
station_view :: proc(x, z: f32) -> View {
	return View{eye = {x, lab.COUNTER_HEIGHT + 0.04, z + 0.9}, back = {0, 0, 1}}
}

@(test)
a_station_is_aimed_at_when_the_crosshair_is_on_it_and_bare_counter_is_not :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	pk: Pickup
	props.aimed = -1
	testing.expect(t, pickup_aim(&pk, props, station_view(-3.5, -7.63)), "the hot plate")
	testing.expect_value(t, pk.index, 0)
	testing.expect(t, pickup_aim(&pk, props, station_view(-2.4, -7.63)), "the ice bath")
	testing.expect_value(t, pk.index, 1)
	testing.expect(t, pickup_aim(&pk, props, station_view(0, -7.625)), "the scale")
	testing.expect_value(t, pk.index, 2)
	testing.expect(t, !pickup_aim(&pk, props, station_view(-1.2, -7.63)), "bare counter between them")
	testing.expect(t, !pk.aimed, "so it is not aimed")
	v := station_view(-3.5, -7.63)
	v.eye.z += 4 // out of reach
	testing.expect(t, !pickup_aim(&pk, props, v), "too far")
	v = station_view(-3.5, -7.63)
	v.back = {0, 0, -1} // looking away
	testing.expect(t, !pickup_aim(&pk, props, v), "looking away")
	props.aimed = 0 // a vessel comes first
	testing.expect(t, !pickup_aim(&pk, props, station_view(-3.5, -7.63)), "a vessel is under the crosshair")
}

@(test)
the_station_that_is_aimed_at_follows_where_it_stands :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	pk: Pickup
	props.aimed = -1
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.63, 0})
	testing.expect(t, !pickup_aim(&pk, props, station_view(-3.5, -7.63)), "the old place has nothing")
	testing.expect(t, pickup_aim(&pk, props, station_view(8, -7.63)), "the new one has the plate")
	testing.expect_value(t, pk.index, 0)
	// Turned a quarter the plate is 0.5 along x: a view 0.28 to the side misses it.
	props.placed.items[0].quarter = 1
	testing.expect(t, !pickup_aim(&pk, props, station_view(8.28, -7.63)), "past the turned plate")
	props.placed.items[0].quarter = 0
	testing.expect(t, pickup_aim(&pk, props, station_view(8.28, -7.63)), "on the plate as it is made")
}

@(test)
the_nearer_of_two_stations_is_the_one_aimed_at :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	pk: Pickup
	props.aimed = -1
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.9 + 0.25, 0}) // behind: z -7.9 to -7.4
	lab.placed_add(&props.placed, {.Hot_Plate, 8, 7.63, 0}) // on the south counter, behind the viewer
	v := View{eye = {8, lab.COUNTER_HEIGHT + 0.04, -6.7}, back = {0, 0, 1}}
	testing.expect(t, pickup_aim(&pk, props, v), "the one in front")
	testing.expect_value(t, pk.index, 0)
	v = View{eye = {8, lab.COUNTER_HEIGHT + 0.04, 6.7}, back = {0, 0, -1}}
	testing.expect(t, pickup_aim(&pk, props, v), "the one on the other side")
	testing.expect_value(t, pk.index, 1)
}

@(test)
a_station_with_a_vessel_on_it_is_busy_and_cannot_be_picked_up :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	pk: Pickup
	props.aimed = -1
	props.held = -1
	pickup_aim(&pk, props, station_view(-3.5, -7.63))
	testing.expect(t, !pk.busy, "nothing on it")
	testing.expect(t, pickup_ready(&pk, props), "ready")
	hx, hz := hot_spot()
	props_add(props, l, .Flask, hx, hz, id(.Water), 100)
	props.aimed = -1
	pickup_aim(&pk, props, station_view(-3.5, -7.63))
	testing.expect(t, pk.aimed && pk.busy, "a flask stands on the plate")
	testing.expect(t, !pickup_ready(&pk, props), "so it cannot be picked up")
	props.held = 0 // the flask is in the hands, which are not empty
	pickup_aim(&pk, props, station_view(-3.5, -7.63))
	testing.expect(t, !pk.busy, "a vessel in the hands is not standing on it")
	testing.expect(t, !pickup_ready(&pk, props), "but the hands are full")
	props.held = -1
	props.items[0].pos.x += 0.45 // beside the plate
	pickup_aim(&pk, props, station_view(-3.5, -7.63))
	testing.expect(t, !pk.busy && pickup_ready(&pk, props), "beside it, it is free again")
	props.items[0].pos = {hx, lab.COUNTER_HEIGHT + 0.5, hz} // over it, in the air
	testing.expect(t, !station_busy(props, props.placed.items[0]), "a vessel in the air over it is not on it")
	pk.aimed = false
	testing.expect(t, !pickup_ready(&pk, props), "nothing is aimed at")
}

@(test)
a_vessel_on_the_scale_plate_makes_the_scale_busy :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	x, z := plate_middle()
	props_add(props, l, .Beaker, x, z, id(.Water), 100)
	props.items[0].pos.y = lab.COUNTER_HEIGHT + lab.SCALE_PLATE_TOP // resting on the plate
	testing.expect(t, station_busy(props, props.placed.items[2]), "on the plate of the scale")
	testing.expect(t, !station_busy(props, props.placed.items[0]), "and not on the hot plate")
	props.items[0].pos.y = 0 // the same place on the floor, which is under the counter, is not on the plate
	testing.expect(t, !station_busy(props, props.placed.items[2]), "a vessel on the floor is not on the plate")
}

@(test)
the_nearer_of_two_stations_in_one_line_is_the_one_aimed_at :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	pk: Pickup
	props.aimed = -1
	props.placed = {}
	lab.placed_add(&props.placed, {.Hot_Plate, 0, -0.45, 0}) // on the island, z -0.7 to -0.2: the one behind
	lab.placed_add(&props.placed, {.Hot_Plate, 0, 0.05, 0}) // z -0.2 to 0.3: the one in front
	v := View{eye = {0, lab.COUNTER_HEIGHT + 0.04, 1.2}, back = {0, 0, 1}}
	testing.expect(t, pickup_aim(&pk, props, v), "aimed at one of them")
	testing.expect_value(t, pk.index, 1)
	props.placed.items[0], props.placed.items[1] = props.placed.items[1], props.placed.items[0] // in the other order
	testing.expect(t, pickup_aim(&pk, props, v), "aimed at one of them")
	testing.expect_value(t, pk.index, 0)
}

// The text of a file with a bench of six spots, as the version before this one wrote it.
bench_file :: proc(items: [BENCH_SPOTS]inventory.Item) -> string {
	bench: inventory.Container
	inventory.container_init(&bench, BENCH_SPOTS, {.Benchable})
	for item, i in items {
		if item.kind != .None {
			inventory.put(&bench, i, item, 1)
		}
	}
	bag: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	names := [2]string{"bag", "bench"}
	containers := [2]^inventory.Container{&bag, &bench}
	return inventory.serialize(names[:], containers[:], context.temp_allocator)
}

@(test)
a_file_from_before_stations_could_stand_anywhere_keeps_the_stations_where_its_bench_had_them :: proc(t: ^testing.T) {
	// The bench as the lab started: the hot plate at spot 1, the bath at 2 and the scale at 4.
	text := bench_file({{}, {.Hot_Plate, 0}, {.Ice_Bath, 0}, {}, {.Scale, 0}, {}})
	p, had := placed_from_bench_file(text)
	testing.expect(t, had, "it had a bench")
	testing.expect_value(t, p, lab.default_placed())
	// The plate moved to the first spot, the scale to the last, and the bath taken off.
	text2 := bench_file({{.Hot_Plate, 0}, {}, {}, {}, {}, {.Scale, 0}})
	p2, had2 := placed_from_bench_file(text2)
	testing.expect(t, had2, "it had a bench")
	testing.expect_value(t, p2.count, 2)
	testing.expect_value(t, p2.items[0], lab.Placement{.Hot_Plate, -4.5, -7.63, 0})
	testing.expect_value(t, p2.items[1], lab.Placement{.Scale, 1.2, -7.625, 0})
	testing.expect_value(t, p2.items[2], lab.Placement{})
	// A bench with nothing on it says that no station stands.
	p3, had3 := placed_from_bench_file(bench_file({}))
	testing.expect(t, had3 && p3.count == 0, "an empty bench is an empty counter")
}

@(test)
a_file_with_no_bench_is_the_lab_as_it_starts :: proc(t: ^testing.T) {
	p, had := placed_from_bench_file("tvstock 1\ncontainer bag 12\ncontainer wall 10\n")
	testing.expect(t, !had, "no bench")
	testing.expect_value(t, p, lab.default_placed())
	p2, had2 := placed_from_bench_file("")
	testing.expect(t, !had2, "nothing at all")
	testing.expect_value(t, p2, lab.default_placed())
}

@(test)
the_old_bench_reads_only_what_a_bench_could_hold :: proc(t: ^testing.T) {
	// A dispenser in a slot of the bench is not a station and is not read as one.
	text := "tvstock 1\ncontainer bench 6\nslot 0 1 3 1\nslot 1 2 0 1\nslot 9 2 0 1\n"
	p, had := placed_from_bench_file(text)
	testing.expect(t, had, "a bench")
	testing.expect_value(t, p.count, 1)
	testing.expect_value(t, p.items[0], lab.Placement{.Hot_Plate, -3.5, -7.63, 0})
}
