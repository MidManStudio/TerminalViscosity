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
	blueprint_aim(&bp, props, eye_at_counter(-6.0, -7.63)) // in the fume hood
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
