// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "blueprint_test.odin"
// ============================================================================

package carry

import "../inventory"
import "../lab"
import "core:math"
import "core:testing"

// A view from `eye` looking at `target`.
view_toward :: proc(eye, target: Vec3) -> View {
	d := target - eye
	n := math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
	return View{eye = eye, back = -(d / n)}
}

// The player's eye, 1.6 m up, 1 m from the north counter and looking at (x, z) on the counter top.
eye_at_counter :: proc(x, z: f32) -> View {
	return view_toward({x, 1.6, -6.6}, {x, lab.COUNTER_HEIGHT, z})
}

// A copy of kind `kind` that is carried, as if taken from the bag.
carried :: proc(props: ^Props, kind: lab.Station_Kind) -> (bp: Blueprint, bag: inventory.Container) {
	inventory.container_init(&bag, BAG_SIZE)
	inventory.put(&bag, 3, station_item(kind), 1)
	blueprint_take_from_bag(&bp, props, &bag, 3)
	return
}

@(test)
picking_up_a_station_takes_it_off_the_counter_and_makes_it_the_copy :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	props.placed.items[1].quarter = 3 // the bath is turned
	bp: Blueprint
	testing.expect(t, blueprint_pick_up(&bp, props, 1), "picked up")
	testing.expect(t, bp.active, "carried")
	testing.expect_value(t, bp.kind, lab.Station_Kind.Ice_Bath)
	testing.expect_value(t, bp.quarter, u8(3))
	testing.expect_value(t, bp.x, f32(-2.4))
	testing.expect_value(t, bp.z, f32(-7.63))
	testing.expect_value(t, bp.origin, Blueprint_Origin.Placed)
	testing.expect_value(t, bp.from, lab.Placement{.Ice_Bath, -2.4, -7.63, 3})
	testing.expect_value(t, props.placed.count, 2)
	testing.expect_value(t, props.placed.items[0].kind, lab.Station_Kind.Hot_Plate)
	testing.expect_value(t, props.placed.items[1].kind, lab.Station_Kind.Scale)
	testing.expect_value(t, props.placed.items[2], lab.Placement{})
}

@(test)
a_station_is_not_picked_up_that_is_not_there_or_with_full_hands_or_while_one_is_carried :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	before := props.placed
	bp: Blueprint
	testing.expect(t, !blueprint_pick_up(&bp, props, -1), "no station -1")
	testing.expect(t, !blueprint_pick_up(&bp, props, 3), "no station 3")
	testing.expect(t, !bp.active, "nothing carried")
	props.held = 0
	testing.expect(t, !blueprint_pick_up(&bp, props, 0), "the hands are full")
	props.held = -1
	testing.expect_value(t, props.placed, before)
	testing.expect(t, blueprint_pick_up(&bp, props, 0), "now it can")
	after_first := props.placed
	testing.expect(t, !blueprint_pick_up(&bp, props, 0), "one is carried already")
	testing.expect_value(t, props.placed, after_first)
	testing.expect_value(t, bp.kind, lab.Station_Kind.Hot_Plate)
}

@(test)
choosing_a_station_in_the_bag_takes_it_out_of_the_bag :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bag: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	inventory.put(&bag, 3, station_item(.Scale), 1)
	inventory.put(&bag, 5, {.Dispenser, 2}, 1)
	bp: Blueprint
	testing.expect(t, !blueprint_take_from_bag(&bp, props, &bag, 4), "an empty slot")
	testing.expect(t, !blueprint_take_from_bag(&bp, props, &bag, 5), "a dispenser is not a station")
	testing.expect(t, !blueprint_take_from_bag(&bp, props, &bag, -1), "no slot -1")
	testing.expect(t, !blueprint_take_from_bag(&bp, props, &bag, BAG_SIZE), "no slot past the end")
	props.held = 0
	testing.expect(t, !blueprint_take_from_bag(&bp, props, &bag, 3), "the hands are full")
	props.held = -1
	testing.expect(t, !bp.active, "none of those started anything")
	testing.expect_value(t, bag.slots[3], inventory.Slot{{.Scale, 0}, 1})
	testing.expect(t, blueprint_take_from_bag(&bp, props, &bag, 3), "the scale")
	testing.expect_value(t, bp.kind, lab.Station_Kind.Scale)
	testing.expect_value(t, bp.origin, Blueprint_Origin.Bag)
	testing.expect_value(t, bp.slot, 3)
	testing.expect_value(t, bp.quarter, u8(0))
	testing.expect_value(t, bag.slots[3], inventory.Slot{})
	testing.expect_value(t, bag.slots[5], inventory.Slot{{.Dispenser, 2}, 1}) // the rest is as it was
	inventory.put(&bag, 6, station_item(.Hot_Plate), 1)
	testing.expect(t, !blueprint_take_from_bag(&bp, props, &bag, 6), "one is carried already")
	testing.expect_value(t, bag.slots[6], inventory.Slot{{.Hot_Plate, 0}, 1})
	testing.expect_value(t, bp.kind, lab.Station_Kind.Scale)
}

@(test)
the_copy_turns_a_quarter_at_a_time_and_only_while_it_is_carried :: proc(t: ^testing.T) {
	bp: Blueprint
	blueprint_rotate(&bp)
	testing.expect_value(t, bp.quarter, u8(0)) // nothing carried
	bp.active = true
	for want in ([5]u8{1, 2, 3, 0, 1}) {
		blueprint_rotate(&bp)
		testing.expect_value(t, bp.quarter, want)
	}
}

@(test)
the_copy_follows_the_crosshair_over_a_counter_and_is_fine_where_there_is_room :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Hot_Plate)
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect(t, bp.ok, "room for it")
	testing.expect_value(t, bp.problem, Blueprint_Problem.None)
	testing.expect_value(t, bp.x, f32(8))
	testing.expect_value(t, bp.z, f32(-7.6))
	blueprint_aim(&bp, props, eye_at_counter(9.5, -7.6))
	testing.expect(t, bp.ok && bp.x == f32(9.5), "it follows along the counter")
	blueprint_aim(&bp, props, eye_at_counter(9.5, -7.4)) // near the front edge: moved in until it is on
	testing.expect(t, bp.ok && bp.z == f32(-7.55), "the front edge is forgiven")
	blueprint_aim(&bp, props, eye_at_counter(9.5, -7.98)) // at the wall
	testing.expect(t, bp.ok && bp.z == f32(-7.7), "so is the wall")
}

@(test)
the_copy_is_not_fine_off_a_counter_too_far_or_with_the_crosshair_up :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Hot_Plate)
	// On the floor of the room.
	blueprint_aim(&bp, props, view_toward({0, 1.6, 4.5}, {0, 1.1, 3.5}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Off_Counter)
	testing.expect(t, !bp.ok, "not ok")
	// On the counter of the bottle wall, which stations do not go on.
	blueprint_aim(&bp, props, view_toward({10.4, 1.6, 0}, {11.63, 1.1, 0}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Off_Counter)
	// A counter that is too far: 3.6 m of floor and 0.5 m of height away.
	blueprint_aim(&bp, props, view_toward({8, 1.6, -4.0}, {8, 1.1, -7.6}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	testing.expect(t, !bp.ok, "not ok")
	testing.expect_value(t, bp.z, f32(-7.6)) // the copy is still where the crosshair is
	// Level, and up: no plane to meet, and the copy floats a metre in front.
	blueprint_aim(&bp, props, View{eye = {3, 1.6, 1}, back = {0, 0, 1}})
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	testing.expect(t, !bp.ok, "not ok")
	testing.expect_value(t, bp.x, f32(3))
	testing.expect_value(t, bp.z, f32(0))
	blueprint_aim(&bp, props, View{eye = {3, 1.6, 1}, back = {0, -1, 0}}) // straight up
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	testing.expect_value(t, [2]f32{bp.x, bp.z}, [2]f32{3, 0})
	blueprint_aim(&bp, props, View{eye = {3, 1.6, 1}, back = {-1, -0.5, 0}}) // up and to the east
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	testing.expect_value(t, [2]f32{bp.x, bp.z}, [2]f32{4, 1}) // a metre to the east, on the level of the eye
	blueprint_aim(&bp, props, View{eye = {3, 1.6, 1}, back = {-2, -1, 0}}) // the same way, with a longer direction
	testing.expect_value(t, [2]f32{bp.x, bp.z}, [2]f32{4, 1}) // still a metre: only the way counts, not how long the direction is
	// An eye at exactly the height of the counter tops looking straight down meets the plane where it is: no plane to meet.
	blueprint_aim(&bp, props, View{eye = {3, lab.COUNTER_HEIGHT, 1}, back = {0, 1, 0}})
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	testing.expect_value(t, [2]f32{bp.x, bp.z}, [2]f32{3, 0})
	// A counter far past the limit that the plane is looked for: the copy is where the limit is on the crosshair, which here is the
	// island, 6 m from the eye along a crosshair that falls 0.5 m in 10, and not 10 m along it, which is floor.
	blueprint_aim(&bp, props, View{eye = {0, 1.6, 6}, back = {0, 0.05, 0.99875}})
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	testing.expect_value(t, [2]f32{bp.x, bp.z}, [2]f32{0, 0})
}

@(test)
the_copy_is_red_where_something_is_in_the_way_and_says_what :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Scale)
	// The sink is on the west counter: aimed at from the east.
	blueprint_aim(&bp, props, view_toward({-10.4, 1.6, -4.2}, {-11.63, 1.1, -4.2}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Fixture)
	testing.expect(t, !bp.ok, "not ok at the sink")
	blueprint_aim(&bp, props, eye_at_counter(-3.5, -7.63)) // on the hot plate
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Station)
	blueprint_aim(&bp, props, eye_at_counter(-6.0, -7.63)) // on the fume hood
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Station)
	blueprint_aim(&bp, props, eye_at_counter(3.0, -7.63)) // in the oven
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Station)
	blueprint_aim(&bp, props, view_toward({-10.4, 1.6, 2.0}, {-11.63, 1.1, 2.0})) // in the paint station
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Fixture)
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect_value(t, bp.problem, Blueprint_Problem.None)
	props_add(props, l, .Beaker, 8, -7.6, 0, 0) // a vessel where it would go
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Vessel)
	testing.expect(t, !bp.ok, "not ok over a vessel")
	props.held = 0 // the same vessel in the hands is not in the way
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect(t, bp.ok, "ok again")
}

@(test)
too_far_comes_before_the_other_problems_and_a_full_lab_before_all :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Scale)
	blueprint_aim(&bp, props, view_toward({-3.5, 1.6, -4.5}, {-3.5, 1.1, -7.63})) // the hot plate, out of reach
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	room := lab.MAX_PLACED - props.placed.count
	for k in 0 ..< room {
		lab.placed_add(&props.placed, {.Hot_Plate, f32(k) * 0.7, 0, 0})
	}
	testing.expect_value(t, props.placed.count, lab.MAX_PLACED)
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6)) // room on the counter, none in the lab
	testing.expect_value(t, bp.problem, Blueprint_Problem.Too_Many)
	testing.expect(t, !bp.ok, "not ok")
	testing.expect(t, !blueprint_place(&bp, props), "and it cannot be put down")
}

@(test)
a_vessel_is_in_the_way_when_it_is_within_a_radius_of_the_footprint :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	r := kind_dims(.Beaker).radius
	props_add(props, l, .Beaker, 8 + 0.3 + r - 0.005, -7.63) // just inside the radius from the edge of a hot plate at 8
	testing.expect(t, vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "inside")
	props.items[0].pos.x = 8 + 0.3 + r + 0.005
	testing.expect(t, !vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "outside")
	props.items[0].pos = {8, 0, -7.63} // on the floor, under the counter
	testing.expect(t, !vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "a vessel on the floor is not on the counter")
	props.items[0].pos = {8, lab.COUNTER_HEIGHT, -7.63 + 0.25 + r - 0.005}
	testing.expect(t, vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "inside along z")
	props.items[0].pos = {8, lab.COUNTER_HEIGHT, -7.63 + 0.25 + r + 0.005}
	testing.expect(t, !vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "outside along z")
	testing.expect(t, vessel_in_way(props, .Hot_Plate, 8, -7.63, 1), "turned a quarter the plate is 0.6 along z, and the same vessel is in the way")
	props.items[0].pos = {8 + 0.25 + r + 0.005, lab.COUNTER_HEIGHT, -7.63}
	testing.expect(t, vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "as it was made the plate is 0.6 along x, and a vessel there is in the way")
	testing.expect(t, !vessel_in_way(props, .Hot_Plate, 8, -7.63, 1), "turned, it is not")
	props.held = 0
	testing.expect(t, !vessel_in_way(props, .Hot_Plate, 8, -7.63, 0), "a vessel in the hands is never in the way")
}

@(test)
a_copy_that_can_stand_is_put_down_as_a_station_and_heats_there :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	bp: Blueprint
	testing.expect(t, blueprint_pick_up(&bp, props, 0), "the hot plate")
	blueprint_rotate(&bp)
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect(t, bp.ok, "ok at 8")
	testing.expect(t, blueprint_place(&bp, props), "put down")
	testing.expect(t, !bp.active, "no longer carried")
	testing.expect_value(t, props.placed.count, 3)
	testing.expect_value(t, props.placed.items[2], lab.Placement{.Hot_Plate, 8, -7.6, 1})
	props_add(props, l, .Flask, 8, -7.6, id(.Water), 300)
	props_add(props, l, .Flask, -3.5, -7.63, id(.Water), 300) // where it stood
	seconds(props, 1)
	testing.expect(t, near(props.items[0].mix.heat_c, 26, 0.05), "it heats where it was put down")
	testing.expect_value(t, props.items[1].mix.heat_c, ROOM_C)
}

@(test)
a_copy_that_cannot_stand_is_not_put_down :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Ice_Bath)
	before := props.placed
	testing.expect(t, !blueprint_place(&bp, props), "nothing aimed yet, so it is not ok")
	blueprint_aim(&bp, props, eye_at_counter(-3.5, -7.63)) // on the hot plate
	testing.expect(t, !blueprint_place(&bp, props), "on the hot plate")
	testing.expect(t, bp.active, "still carried")
	testing.expect_value(t, props.placed, before)
	// It was fine when it was last aimed, and something has come in the way since.
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect(t, bp.ok, "fine")
	lab.placed_add(&props.placed, {.Hot_Plate, 8, -7.63, 0})
	testing.expect(t, !blueprint_place(&bp, props), "a station came to stand there")
	idle: Blueprint
	testing.expect(t, !blueprint_place(&idle, props), "nothing is carried")
	idle.ok = true
	testing.expect(t, !blueprint_place(&idle, props), "an ok flag alone is not a copy")
	loose := Blueprint{kind = .Hot_Plate, x = 9.5, z = -7.6, ok = true} // a kind and a place and a good flag, and not carried
	count := props.placed.count
	testing.expect(t, !blueprint_place(&loose, props), "a copy that is not carried is not put down")
	testing.expect_value(t, props.placed.count, count)
}

@(test)
a_copy_goes_back_where_it_was_picked_up_from_if_that_is_free :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	bag: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	bp: Blueprint
	before := props.placed
	blueprint_pick_up(&bp, props, 2) // the scale, last
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.Put_Back)
	testing.expect(t, !bp.active, "no longer carried")
	testing.expect_value(t, props.placed, before)
	testing.expect_value(t, inventory.free_room(&bag, station_item(.Scale)), BAG_SIZE) // the bag was not used
	blueprint_pick_up(&bp, props, 0)
	blueprint_rotate(&bp) // turning it and aiming it elsewhere does not change where it goes back
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.Put_Back)
	testing.expect_value(t, props.placed.items[2], lab.Placement{.Hot_Plate, -3.5, -7.63, 0})
}

@(test)
a_copy_goes_to_the_bag_if_where_it_was_is_not_free_any_more :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	bag: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	bp: Blueprint
	blueprint_pick_up(&bp, props, 0)
	props_add(props, l, .Beaker, -3.5, -7.63) // a vessel is put where the plate was
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.In_Bag)
	testing.expect_value(t, props.placed.count, 2)
	testing.expect_value(t, inventory.count_of(&bag, station_item(.Hot_Plate)), 1)
	testing.expect(t, !bp.active, "no longer carried")
	// A station put there in the meantime does the same.
	props.count = 0
	bp = {}
	blueprint_pick_up(&bp, props, 0) // the ice bath now, which is first
	lab.placed_add(&props.placed, {.Hot_Plate, -2.4, -7.63, 0})
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.In_Bag)
	testing.expect_value(t, inventory.count_of(&bag, station_item(.Ice_Bath)), 1)
}

@(test)
a_copy_from_the_bag_goes_back_to_its_slot_or_to_another_if_the_slot_is_taken :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	bp, bag := carried(props, .Scale)
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.In_Bag)
	testing.expect_value(t, bag.slots[3], inventory.Slot{{.Scale, 0}, 1})
	bp, bag = carried(props, .Scale)
	inventory.put(&bag, 3, {.Dispenser, 2}, 1) // the slot is taken
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.In_Bag)
	testing.expect_value(t, bag.slots[3], inventory.Slot{{.Dispenser, 2}, 1})
	testing.expect_value(t, inventory.count_of(&bag, station_item(.Scale)), 1)
	testing.expect_value(t, props.placed.count, 3) // and nothing was put on a counter
}

@(test)
a_copy_stays_carried_when_it_has_nowhere_to_go :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	only_plates(&props.placed) // the other stations have no place in what these count
	bag: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	bp: Blueprint
	blueprint_pick_up(&bp, props, 0)
	props_add(props, l, .Beaker, -3.5, -7.63) // where it was is not free
	for i in 0 ..< BAG_SIZE {
		inventory.put(&bag, i, {.Dispenser, 1}, 1)
	}
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag), Cancel_Result.No_Room)
	testing.expect(t, bp.active, "still carried")
	testing.expect_value(t, props.placed.count, 2)
	idle: Blueprint
	testing.expect_value(t, blueprint_cancel(&idle, props, &bag), Cancel_Result.Nothing)
}

@(test)
every_problem_has_its_own_words :: proc(t: ^testing.T) {
	seen: [len(Blueprint_Problem)]string
	for problem in Blueprint_Problem {
		words := blueprint_words(problem)
		testing.expectf(t, len(words) > 5, "%v has words", problem)
		for earlier in seen[:int(problem)] {
			testing.expectf(t, earlier != words, "%v does not repeat the words of another", problem)
		}
		seen[int(problem)] = words
	}
	testing.expect_value(t, blueprint_words(.None), "put it down here")
	testing.expect_value(t, blueprint_words(.Blocked_By_Vessel), "a vessel is in the way")
}

@(test)
a_station_that_does_not_fit_the_counter_it_is_aimed_at_is_told_so :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Ice_Bath)
	bp.quarter = 1 // 0.86 deep, on a counter that is 0.7 deep
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Too_Big)
	testing.expect(t, !bp.ok, "not ok")
	bp.quarter = 0
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6))
	testing.expect(t, bp.ok, "turned the other way it fits")
	// The west counter is 0.7 wide, and the bath is 0.86 wide as it is made.
	blueprint_aim(&bp, props, view_toward({-10.4, 1.6, 0}, {-11.63, 1.1, 0}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Too_Big)
	bp.quarter = 1
	blueprint_aim(&bp, props, view_toward({-10.4, 1.6, 0}, {-11.63, 1.1, 0}))
	testing.expect(t, bp.ok, "and turned a quarter it fits")
	// Over bare floor it is still not on a counter, and too far is still first.
	blueprint_aim(&bp, props, view_toward({0, 1.6, 4.5}, {0, 1.1, 3.5}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Off_Counter)
	bp.quarter = 1
	blueprint_aim(&bp, props, view_toward({8, 1.6, -4.0}, {8, 1.1, -7.6}))
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
}

@(test)
a_station_from_the_bar_goes_back_to_its_slot_of_the_bar :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bag, bar: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	inventory.container_init(&bar, HOTBAR_SIZE, {.Benchable})
	inventory.put(&bar, 2, station_item(.Scale), 1)
	bp: Blueprint
	testing.expect(t, blueprint_take_from(&bp, props, &bar, 2, .Hotbar), "taken from the bar")
	testing.expect_value(t, bp.origin, Blueprint_Origin.Hotbar)
	testing.expect_value(t, bp.slot, 2)
	testing.expect_value(t, bar.slots[2], inventory.Slot{})
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag, &bar), Cancel_Result.In_Bar)
	testing.expect_value(t, bar.slots[2], inventory.Slot{{.Scale, 0}, 1})
	testing.expect_value(t, inventory.count_of(&bag, station_item(.Scale)), 0)
	// A slot that is taken in the meantime sends it to the bag, and then to another slot of the bar if the bag is full.
	blueprint_take_from(&bp, props, &bar, 2, .Hotbar)
	inventory.put(&bar, 2, station_item(.Hot_Plate), 1)
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag, &bar), Cancel_Result.In_Bag)
	testing.expect_value(t, inventory.count_of(&bag, station_item(.Scale)), 1)
	blueprint_take_from(&bp, props, &bag, 0, .Bag)
	for i in 0 ..< BAG_SIZE {
		inventory.put(&bag, i, {.Dispenser, 1}, 1)
	}
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag, &bar), Cancel_Result.In_Bar)
	testing.expect_value(t, inventory.count_of(&bar, station_item(.Scale)), 1)
	// With no bar given, a station that came from the bar goes to the bag, and stays carried if the bag is full.
	bp2: Blueprint
	inventory.put(&bar, 5, station_item(.Ice_Bath), 1)
	blueprint_take_from(&bp2, props, &bar, 5, .Hotbar)
	testing.expect_value(t, blueprint_cancel(&bp2, props, &bag), Cancel_Result.No_Room)
	testing.expect(t, bp2.active, "still carried")
	testing.expect(t, !blueprint_take_from(&bp2, props, &bar, 3, .Hotbar), "one is carried already")
}

@(test)
a_copy_is_stowed_in_the_slot_of_the_bar_that_is_pressed :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bag, bar: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	inventory.container_init(&bar, HOTBAR_SIZE, {.Benchable})
	idle: Blueprint
	testing.expect_value(t, blueprint_stow(&idle, &bag, &bar, 0), Cancel_Result.Nothing)
	bp, _ := carried(props, .Scale)
	testing.expect_value(t, blueprint_stow(&bp, &bag, &bar, 4), Cancel_Result.In_Bar)
	testing.expect(t, !bp.active, "no longer carried")
	testing.expect_value(t, bar.slots[4], inventory.Slot{{.Scale, 0}, 1})
	// A slot that is taken sends it to the first free slot.
	bp, _ = carried(props, .Hot_Plate)
	testing.expect_value(t, blueprint_stow(&bp, &bag, &bar, 4), Cancel_Result.In_Bar)
	testing.expect_value(t, bar.slots[0], inventory.Slot{{.Hot_Plate, 0}, 1})
	// A slot that is not there sends it to the first free slot too.
	bp, _ = carried(props, .Ice_Bath)
	testing.expect_value(t, blueprint_stow(&bp, &bag, &bar, 99), Cancel_Result.In_Bar)
	testing.expect_value(t, bar.slots[1], inventory.Slot{{.Ice_Bath, 0}, 1})
	// A full bar sends it to the bag, and a full bag keeps it carried.
	for i in 0 ..< HOTBAR_SIZE {
		inventory.take(&bar, i, 1)
		inventory.put(&bar, i, station_item(.Scale), 1)
	}
	bp, _ = carried(props, .Hot_Plate)
	testing.expect_value(t, blueprint_stow(&bp, &bag, &bar, 0), Cancel_Result.In_Bag)
	testing.expect_value(t, inventory.count_of(&bag, station_item(.Hot_Plate)), 1)
	for i in 0 ..< BAG_SIZE {
		inventory.take(&bag, i, 1)
		inventory.put(&bag, i, {.Dispenser, 1}, 1)
	}
	bp, _ = carried(props, .Hot_Plate)
	for i in 0 ..< BAG_SIZE {
		inventory.take(&bag, i, 1)
		inventory.put(&bag, i, {.Dispenser, 1}, 1)
	}
	testing.expect_value(t, blueprint_stow(&bp, &bag, &bar, 0), Cancel_Result.No_Room)
	testing.expect(t, bp.active, "still carried")
}

@(test)
a_point_of_the_screen_is_a_ray_through_the_view :: proc(t: ^testing.T) {
	v := View{eye = {1, 2, 3}, right = {1, 0, 0}, up = {0, 1, 0}, back = {0, 0, 1}} // looking along -z
	d := view_ray(v, 0, 0, 1, 1)
	testing.expect(t, near(d.x, 0, 1e-5) && near(d.y, 0, 1e-5) && near(d.z, -1, 1e-5), "the middle of the screen is where the view looks")
	d = view_ray(v, 1, 0, 1, 1) // the right edge of a view that is 90 degrees wide
	testing.expect(t, near(d.x, 0.70710678, 1e-5) && near(d.y, 0, 1e-5) && near(d.z, -0.70710678, 1e-5), "the right edge is 45 degrees to the right")
	d = view_ray(v, -1, 0, 1, 1)
	testing.expect(t, near(d.x, -0.70710678, 1e-5), "and the left edge to the left")
	d = view_ray(v, 0, 1, 1, 1)
	testing.expect(t, near(d.y, 0.70710678, 1e-5) && near(d.z, -0.70710678, 1e-5) && near(d.x, 0, 1e-5), "the top edge is 45 degrees up")
	d = view_ray(v, 1, 0, 0.5, 2) // twice as wide as high, and half as tall: the same width as the first
	testing.expect(t, near(d.x, 0.70710678, 1e-5) && near(d.z, -0.70710678, 1e-5), "aspect widens the view sideways")
	d = view_ray(v, 0, 1, 0.5, 2)
	testing.expect(t, near(d.y, 0.4472136, 1e-5) && near(d.z, -0.8944272, 1e-5), "and the half height gives half as much up")
	d = view_ray(v, 0.6, -0.3, 0.7, 1.8)
	testing.expect(t, near(d.x * d.x + d.y * d.y + d.z * d.z, 1, 1e-5), "the direction is a unit vector")
	turned := View{eye = {0, 0, 0}, right = {0, 0, 1}, up = {0, 1, 0}, back = {-1, 0, 0}} // looking along +x
	d = view_ray(turned, 1, 0, 1, 1)
	testing.expect(t, near(d.x, 0.70710678, 1e-5) && near(d.z, 0.70710678, 1e-5), "right is along the right of the view, wherever it looks")
}

@(test)
aiming_along_a_ray_is_aiming_with_the_crosshair_or_at_any_other_point :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Hot_Plate)
	v := eye_at_counter(8, -7.6)
	blueprint_aim(&bp, props, v)
	by_view := bp
	blueprint_aim_ray(&bp, props, v.eye, -v.back)
	testing.expect_value(t, bp, by_view)
	// A ray through another point of the counter puts the copy there.
	d := Vec3{9.5 - v.eye.x, lab.COUNTER_HEIGHT - v.eye.y, -7.6 - v.eye.z}
	blueprint_aim_ray(&bp, props, v.eye, d / sqrt_f32(dot(d, d)))
	testing.expect(t, bp.ok && bp.x == f32(9.5) && bp.z == f32(-7.6), "at the point the ray goes through")
	// And one that is too far is too far.
	far := Vec3{0, -0.05, -0.99875}
	blueprint_aim_ray(&bp, props, {8, 1.6, 0}, far)
	testing.expect_value(t, bp.problem, Blueprint_Problem.Out_Of_Reach)
	idle: Blueprint
	blueprint_aim_ray(&idle, props, v.eye, -v.back)
	testing.expect_value(t, idle, Blueprint{})
}

@(test)
a_full_lab_is_said_before_a_station_that_is_too_big :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Ice_Bath)
	bp.quarter = 1
	room := lab.MAX_PLACED - props.placed.count
	for k in 0 ..< room {
		lab.placed_add(&props.placed, {.Hot_Plate, f32(k) * 0.7, 0, 0})
	}
	blueprint_aim(&bp, props, eye_at_counter(8, -7.6)) // too big for the counter, and no room in the lab
	testing.expect_value(t, bp.problem, Blueprint_Problem.Too_Many)
}

@(test)
a_station_from_the_bag_does_not_go_to_the_bar_when_it_is_put_back :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bag, bar: inventory.Container
	inventory.container_init(&bag, BAG_SIZE)
	inventory.container_init(&bar, HOTBAR_SIZE, {.Benchable})
	inventory.put(&bag, 3, station_item(.Scale), 1)
	bp: Blueprint
	blueprint_take_from(&bp, props, &bag, 3, .Bag)
	testing.expect_value(t, blueprint_cancel(&bp, props, &bag, &bar), Cancel_Result.In_Bag)
	testing.expect_value(t, bag.slots[3], inventory.Slot{{.Scale, 0}, 1})
	testing.expect_value(t, inventory.count_of(&bar, station_item(.Scale)), 0)
}

// The player's eye, 1.6 m up, 1.1 m from the south counter and looking at (x, z) on the counter top.
eye_at_south_counter :: proc(x, z: f32) -> View {
	return view_toward({x, 1.6, 6.6}, {x, lab.COUNTER_HEIGHT, z})
}

@(test)
the_incinerator_is_picked_up_turned_and_put_down_on_the_south_counter :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	index := -1
	for i in 0 ..< props.placed.count {
		if props.placed.items[i].kind == .Incinerator {
			index = i
		}
	}
	testing.expect(t, index >= 0, "it stands where the lab starts it")
	bp: Blueprint
	testing.expect(t, blueprint_pick_up(&bp, props, index), "picked up")
	testing.expect_value(t, bp.kind, lab.Station_Kind.Incinerator)
	testing.expect_value(t, props.placed.count, 6)
	_, standing := lab.placed_find(&props.placed, .Incinerator)
	testing.expect(t, !standing, "it is off the counter while it is carried")
	// Over the fill station it is red, and says why.
	blueprint_aim(&bp, props, eye_at_south_counter(6, 7.63))
	testing.expect(t, !bp.ok, "not on the fill station")
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Station)
	// Turned a quarter and over the free counter between the fill station and the rack, it can be put down.
	blueprint_rotate(&bp)
	blueprint_aim(&bp, props, eye_at_south_counter(7.3, 7.63))
	testing.expect(t, bp.ok, "ok between the fill station and the rack")
	testing.expect(t, blueprint_place(&bp, props), "put down")
	testing.expect_value(t, props.placed.count, 7)
	pl, standing_now := lab.placed_find(&props.placed, .Incinerator)
	testing.expect(t, standing_now, "it stands again")
	testing.expect(t, near(pl.x, 7.3, 0.001) && near(pl.z, 7.65, 0.021) && pl.quarter == 1, "where it was put, turned a quarter")
}

@(test)
a_vessel_in_the_middle_of_the_incinerator_does_not_keep_it_from_being_picked_up :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	pl, _ := lab.placed_find(&props.placed, .Incinerator)
	props_add(props, l, .Flask, pl.x, pl.z, id(.Water), 300)
	testing.expect(t, !station_busy(props, pl), "it has no plate, so nothing stands on it")
	// The same vessel on a plate that has one is what keeps a station down.
	hot, _ := lab.placed_find(&props.placed, .Hot_Plate)
	props_add(props, l, .Flask, hot.x, hot.z, id(.Water), 300)
	testing.expect(t, station_busy(props, hot), "a vessel on the hot plate does")
}

@(test)
the_hood_is_picked_up_turned_and_put_down_on_the_west_counter_and_shields_there :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	index := -1
	for i in 0 ..< props.placed.count {
		if props.placed.items[i].kind == .Hood {
			index = i
		}
	}
	testing.expect(t, index >= 0, "it stands where the lab starts it")
	bp: Blueprint
	testing.expect(t, blueprint_pick_up(&bp, props, index), "picked up")
	testing.expect_value(t, bp.kind, lab.Station_Kind.Hood)
	testing.expect(t, !in_hood(&props.placed, {-6.0, 1.2, -7.63}), "there is no hood while it is carried")
	blueprint_rotate(&bp)
	blueprint_aim(&bp, props, view_toward({-10.4, 1.6, -1.5}, {-11.63, 1.1, -1.5}))
	testing.expect(t, bp.ok, "ok on the west counter, clear of the sink and the paint station")
	testing.expect(t, blueprint_place(&bp, props), "put down")
	pl, standing := lab.placed_find(&props.placed, .Hood)
	testing.expect(t, standing && near(pl.x, -11.63, 0.001) && near(pl.z, -1.5, 0.021) && pl.quarter == 1, "turned a quarter on the west counter")
	testing.expect(t, in_hood(&props.placed, {pl.x, 1.2, pl.z}), "it shields where it stands")
	testing.expect(t, !in_hood(&props.placed, {-6.0, 1.2, -7.63}), "and not where it stood")
}

@(test)
a_vessel_in_the_hood_keeps_it_down_and_one_beside_it_does_not :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	hood, _ := lab.placed_find(&props.placed, .Hood)
	props_add(props, l, .Flask, hood.x + 1.2, hood.z, id(.Water), 300) // on the counter past its side
	testing.expect(t, !station_busy(props, hood), "a vessel beside it is no reason")
	props_add(props, l, .Flask, hood.x, hood.z, id(.Water), 300)
	testing.expect(t, station_busy(props, hood), "a vessel in it is")
}

@(test)
the_copy_is_red_under_the_shelves_and_the_cabinet_for_the_tall_stations_only :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	bp, _ := carried(props, .Incinerator)
	blueprint_aim(&bp, props, eye_at_south_counter(-6, 7.63))
	testing.expect(t, !bp.ok, "not under the shelves")
	testing.expect_value(t, bp.problem, Blueprint_Problem.Blocked_By_Fixture)
	blueprint_aim(&bp, props, eye_at_south_counter(7.3, 7.63))
	testing.expect(t, bp.ok, "but past the end of them it is")
	low, _ := carried(props, .Scale)
	blueprint_aim(&low, props, eye_at_south_counter(-6, 7.63))
	testing.expect(t, low.ok, "a scale is low enough to stand under the shelves")
}

// Takes every station but the hot plate, the ice bath and the scale off the counters, for the tests that count the
// stations of the north counter.
only_plates :: proc(placed: ^lab.Placed) {
	for placed.count > 3 {
		lab.placed_remove(placed, 3)
	}
}
