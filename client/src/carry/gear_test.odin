// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "gear_test.odin"
// ============================================================================

package carry

import "../chemistry"
import "../lab"
import "core:testing"

// Runs `seconds` of the carrying system with nobody holding anything.
settle_for :: proc(props: ^Props, l: ^lab.Layout, p: ^lab.Player, seconds: f32) {
	for _ in 0 ..< int(seconds * 60) {
		update(props, l, p, 1.0 / 60)
	}
}

// ---------------------------------------------------------------- the vial racks

@(test)
every_hole_of_every_rack_is_over_a_counter_and_a_vial_apart_from_the_next :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	for rack in 0 ..< lab.VIAL_RACK_COUNT {
		for i in 0 ..< lab.VIAL_SLOTS_PER_RACK {
			s := lab.vial_slot(rack, i)
			testing.expect_value(t, support_height(l, s.x, s.z, 0.016), lab.COUNTER_HEIGHT)
			testing.expect_value(t, s.y, lab.VIAL_SLOT_FLOOR)
			if i % lab.VIAL_RACK_COLS != 0 {
				before := lab.vial_slot(rack, i - 1)
				testing.expect(t, near(s.x - before.x, lab.VIAL_SLOT_SPACING) && near(s.z, before.z), "a row is evenly spaced")
			}
			if i >= lab.VIAL_RACK_COLS {
				front := lab.vial_slot(rack, i - lab.VIAL_RACK_COLS)
				testing.expect(t, near(abs(s.z - front.z), lab.VIAL_SLOT_SPACING) && near(s.x, front.x), "and so is a column")
				// The first row is the one nearer the player.
				racks := lab.VIAL_RACKS
				testing.expect(t, (front.z - s.z) * racks[rack].front > 0, "the first row is nearer the player")
			}
		}
	}
	// A vial is narrower than the hole spacing, so two never touch.
	testing.expect(t, kind_dims(.Vial).radius * 2 < lab.VIAL_SLOT_SPACING, "a vial fits its hole")
}

near :: proc(a, b: f32, tolerance: f32 = 0.0005) -> bool {
	return abs(a - b) <= tolerance
}

@(test)
the_vials_start_in_the_holes_empty_and_standing_on_the_lower_plate :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	per_rack: [lab.VIAL_RACK_COUNT]int
	for i in 0 ..< props.count {
		pr := props.items[i]
		if pr.kind != .Vial {
			continue
		}
		slot, in_hole := vial_slot_at(pr.pos.x, pr.pos.z)
		testing.expect(t, in_hole, "every vial starts in a hole")
		testing.expect_value(t, pr.pos.y, slot.y)
		testing.expect_value(t, main_of(&pr.mix), u16(0))
		testing.expect_value(t, ml_of(&pr.mix), f32(0))
		for rack in 0 ..< lab.VIAL_RACK_COUNT {
			for n in 0 ..< lab.VIAL_SLOTS_PER_RACK {
				s := lab.vial_slot(rack, n)
				if near(s.x, pr.pos.x, 0.002) && near(s.z, pr.pos.z, 0.002) {
					per_rack[rack] += 1
				}
			}
		}
	}
	testing.expect_value(t, per_rack, [lab.VIAL_RACK_COUNT]int{6, 6, 6, 6})
	// And they stay put when the system runs.
	snapshot := props.items
	settle_for(props, l, p, 1)
	for i in 0 ..< props.count {
		testing.expect_value(t, props.items[i].pos, snapshot[i].pos)
	}
}

@(test)
a_vial_let_go_near_a_free_hole_is_drawn_into_it_and_falls_in :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	free_slot := lab.vial_slot(0, 10) // the first rack has its first six holes taken
	props_add(props, l, .Vial, free_slot.x + 0.02, free_slot.z - 0.015)
	i := props.count - 1
	props.items[i].pos.y = 1.5 // let go in the air
	settle_for(props, l, p, 1)
	testing.expect_value(t, props.items[i].pos.x, free_slot.x)
	testing.expect_value(t, props.items[i].pos.z, free_slot.z)
	testing.expect_value(t, props.items[i].pos.y, free_slot.y)
}

@(test)
a_vial_is_not_drawn_into_a_hole_that_is_taken_or_too_far_or_when_it_is_not_a_vial_or_is_held :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	taken := lab.vial_slot(0, 3)
	free_slot := lab.vial_slot(0, 10)
	props_add(props, l, .Vial, taken.x + 0.01, taken.z) // next to a hole with a vial in it
	props_add(props, l, .Vial, free_slot.x + 0.325, free_slot.z) // more than 3 cm from every hole
	props_add(props, l, .Beaker, free_slot.x, free_slot.z + 0.005) // not a vial
	props_add(props, l, .Vial, free_slot.x + 0.01, free_slot.z) // a vial that is held
	props_add(props, l, .Vial, free_slot.x, free_slot.z - 0.04) // 4 cm behind a free hole: too far to be drawn in
	first := props.count - 5
	props.held = props.count - 2
	before: [5]Vec3
	for k in 0 ..< 5 {
		before[k] = props.items[first + k].pos
		vial_snap(props, first + k)
	}
	for k in 0 ..< 5 {
		testing.expect_value(t, props.items[first + k].pos.x, before[k].x)
		testing.expect_value(t, props.items[first + k].pos.z, before[k].z)
	}
	// None of them is in a hole, so each stands on the counter and not on the lower plate of a rack. The one that
	// was held is let go of at the end, and then it is drawn into the hole beside it.
	held := props.held - first
	props.held = -1
	settle_for(props, l, p, 1)
	for k in 0 ..< 5 {
		if k == held {
			testing.expect_value(t, props.items[first + k].pos.y, lab.VIAL_SLOT_FLOOR)
		} else {
			testing.expect_value(t, props.items[first + k].pos.y, lab.COUNTER_HEIGHT)
		}
	}
}

@(test)
two_vials_let_go_over_one_hole_do_not_share_it :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	slot := lab.vial_slot(1, 9) // the second rack has six, in the row nearer the player
	props_add(props, l, .Vial, slot.x + 0.01, slot.z)
	props_add(props, l, .Vial, slot.x - 0.01, slot.z + 0.005)
	vial_snap(props, 0)
	vial_snap(props, 1)
	testing.expect_value(t, props.items[0].pos.x, slot.x)
	// The second finds the hole taken and, with no other within reach, stays where it is.
	testing.expect_value(t, props.items[1].pos.x, slot.x - 0.01)
}

@(test)
a_vial_goes_into_the_nearest_of_two_free_holes :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	a, b := lab.vial_slot(1, 10), lab.vial_slot(1, 11)
	props_add(props, l, .Vial, (a.x + b.x) * 0.5 + 0.004, a.z)
	vial_snap(props, 0)
	testing.expect_value(t, props.items[0].pos.x, b.x)
	props.items[0].pos = {(a.x + b.x) * 0.5 - 0.004, 0, a.z}
	vial_snap(props, 0)
	testing.expect_value(t, props.items[0].pos.x, a.x)
}

@(test)
the_crosshair_is_on_the_vial_it_looks_to_be_on_in_a_full_row :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	for col in 0 ..< lab.VIAL_RACK_COLS {
		slot := lab.vial_slot(0, col)
		p.x, p.z = slot.x, -6.4
		look_at(p, {slot.x, slot.y + 0.05, slot.z})
		update(props, l, p, 1.0 / 60)
		testing.expect(t, props.aimed != -1, "the crosshair is on a vial")
		got := props.items[props.aimed].pos
		testing.expectf(t, near(got.x, slot.x, 0.002) && near(got.z, slot.z, 0.002), "aimed at hole %d and got the vial at %v", col, got)
	}
}

@(test)
a_vial_can_be_taken_out_of_a_rack_and_put_back :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	slot := lab.vial_slot(0, 2)
	p.x, p.z = slot.x, -6.4
	look_at(p, {slot.x, slot.y + 0.05, slot.z})
	update(props, l, p, 1.0 / 60)
	testing.expect(t, props.aimed != -1, "the crosshair is on a vial")
	i := props.aimed
	testing.expect_value(t, props.items[i].kind, Kind.Vial)
	testing.expect(t, near(props.items[i].pos.x, slot.x, 0.002) && near(props.items[i].pos.z, slot.z, 0.002), "the one in that hole")
	testing.expect(t, grab(props), "it is taken")
	testing.expect_value(t, props.held, i)
	// Let go of it a little off the hole.
	props.items[props.held].pos = {slot.x + 0.012, 1.3, slot.z + 0.01}
	release(props)
	settle_for(props, l, p, 1)
	testing.expect_value(t, props.items[i].pos.x, slot.x)
	testing.expect_value(t, props.items[i].pos.z, slot.z)
	testing.expect_value(t, props.items[i].pos.y, slot.y)
}

// ---------------------------------------------------------------- the scale

plate_middle :: proc() -> (x, z: f32) {
	p := lab.SCALE_PLATE
	return (p.min_x + p.max_x) * 0.5, (p.min_z + p.max_z) * 0.5
}

@(test)
a_vessel_on_the_plate_stands_on_it_and_is_weighed_with_its_glass :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	x, z := plate_middle()
	sc: Scale
	_, loaded := scale_reading(&sc, props)
	testing.expect(t, !loaded, "nothing on the plate")
	props_add(props, l, .Beaker, x, z, u16(chemistry.Id.Water), 100)
	settle_for(props, l, p, 1)
	testing.expect_value(t, props.items[0].pos.y, lab.COUNTER_HEIGHT + lab.SCALE_PLATE_TOP)
	grams, ok := scale_reading(&sc, props)
	testing.expect(t, ok, "something on the plate")
	testing.expect(t, near(grams, 160, 0.01), "60 g of glass and 100 ml at 1 g a ml")
	// The other kinds of glass.
	props.items[0].kind = .Flask
	fill_with(&props.items[0].mix, 0, 0)
	grams, _ = scale_reading(&sc, props)
	testing.expect(t, near(grams, 85, 0.01), "an empty flask")
	props.items[0].kind = .Bottle
	grams, _ = scale_reading(&sc, props)
	testing.expect(t, near(grams, 110, 0.01), "an empty bottle")
	props.items[0].kind = .Vial
	grams, _ = scale_reading(&sc, props)
	testing.expect(t, near(grams, 8, 0.01), "an empty vial")
}

@(test)
a_vessel_that_is_beside_the_plate_or_held_or_in_the_air_is_not_weighed :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	x, z := plate_middle()
	props_add(props, l, .Beaker, x + 0.5, z, u16(chemistry.Id.Water), 100) // on the counter beside it
	sc: Scale
	_, count := scale_load(props)
	testing.expect_value(t, count, 0)
	props_add(props, l, .Beaker, x, z, u16(chemistry.Id.Water), 100)
	_, count = scale_load(props)
	testing.expect_value(t, count, 1)
	props.held = 1
	_, count = scale_load(props)
	testing.expect_value(t, count, 0)
	props.held = -1
	props.items[1].pos.y = 1.4 // not yet down
	_, count = scale_load(props)
	testing.expect_value(t, count, 0)
	_, loaded := scale_reading(&sc, props)
	testing.expect(t, !loaded, "nothing is weighed")
}

// A beaker of 100 ml of water (160 g) and an empty flask (85 g) on either side of the middle of
// the plate, which is 0.4 m wide.
two_on_the_plate :: proc(l: ^lab.Layout, p: ^lab.Player, props: ^Props) {
	x, z := plate_middle()
	props_add(props, l, .Beaker, x - 0.1, z, u16(chemistry.Id.Water), 100)
	props_add(props, l, .Flask, x + 0.1, z)
	settle_for(props, l, p, 1)
}

@(test)
every_vessel_on_the_plate_is_weighed_together :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	two_on_the_plate(l, p, props)
	sc: Scale
	grams, count := scale_load(props)
	testing.expect_value(t, count, 2)
	testing.expect(t, near(grams, 245, 0.01), "160 g and 85 g")
	reading, loaded := scale_reading(&sc, props)
	testing.expect(t, loaded, "something is on the plate")
	testing.expect(t, near(reading, 245, 0.01), "the display reads both")
	// A third one, a vial, in front of them.
	x, z := plate_middle()
	props_add(props, l, .Vial, x, z + 0.1, u16(chemistry.Id.Water), 10)
	settle_for(props, l, p, 1)
	grams, count = scale_load(props)
	testing.expect_value(t, count, 3)
	testing.expect(t, near(grams, 263, 0.01), "and 8 g of glass and 10 ml more")
}

@(test)
a_vessel_that_is_held_or_beside_the_plate_is_left_out_of_the_load_of_the_others :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	two_on_the_plate(l, p, props)
	x, z := plate_middle()
	props_add(props, l, .Beaker, x + 0.5, z, u16(chemistry.Id.Water), 100)
	settle_for(props, l, p, 1)
	grams, count := scale_load(props)
	testing.expect_value(t, count, 2)
	testing.expect(t, near(grams, 245, 0.01), "the one beside the plate is not weighed")
	props.held = 0
	grams, count = scale_load(props)
	testing.expect_value(t, count, 1)
	testing.expect(t, near(grams, 85, 0.01), "the held one is lifted off, the flask stays")
	testing.expect(t, !scale_on(props, 0), "the held one is not on the plate")
	testing.expect(t, scale_on(props, 1), "the flask is")
	testing.expect(t, !scale_on(props, 2), "and the one beside it is not")
	testing.expect(t, !scale_on(props, -1), "no vessel is not on it")
	testing.expect(t, !scale_on(props, props.count), "nor one past the list")
}

@(test)
a_stale_slot_past_the_end_of_the_list_is_not_on_the_plate :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	two_on_the_plate(l, p, props)
	// Taking the first vessel out shifts the list down and leaves the old last slot as it was, so
	// slot 1 is now a stale copy of the flask that is still on the plate.
	props_remove(props, 0)
	testing.expect_value(t, props.count, 1)
	testing.expect(t, scale_on(props, 0), "the flask is on the plate")
	testing.expect(t, !scale_on(props, 1), "its stale copy past the end of the list is not")
	_, count := scale_load(props)
	testing.expect_value(t, count, 1)
}

@(test)
zeroing_takes_the_whole_load_off_the_display_and_a_vessel_added_reads_alone :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	two_on_the_plate(l, p, props)
	sc := Scale {
		aimed = true,
	}
	testing.expect(t, scale_zero(&sc, props), "zeroed with two on it")
	testing.expect(t, near(sc.tare, 245, 0.01), "at the weight of both")
	reading, _ := scale_reading(&sc, props)
	testing.expect(t, near(reading, 0, 0.01), "the display reads nothing")
	// Pour 40 ml into the beaker: the display reads the 40.
	fill_with(&props.items[0].mix, id(.Water), ml_of(&props.items[0].mix) + 40)
	reading, _ = scale_reading(&sc, props)
	testing.expect(t, near(reading, 40, 0.01), "what was added to either")
	// A vial put on it reads its own weight on top.
	x, z := plate_middle()
	props_add(props, l, .Vial, x, z + 0.1)
	settle_for(props, l, p, 1)
	reading, _ = scale_reading(&sc, props)
	testing.expect(t, near(reading, 48, 0.01), "40 ml and 8 g of glass")
}

@(test)
taking_one_vessel_off_keeps_the_tare_and_taking_all_off_clears_it :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	two_on_the_plate(l, p, props)
	sc := Scale {
		aimed = true,
	}
	scale_zero(&sc, props)
	props.items[0].pos.x += 0.6 // the beaker is taken off
	scale_update(&sc, props)
	testing.expect(t, near(sc.tare, 245, 0.01), "the flask is still on, so the tare is kept")
	reading, loaded := scale_reading(&sc, props)
	testing.expect(t, loaded, "the flask is weighed")
	testing.expect(t, near(reading, -160, 0.01), "and the display reads 160 g less than nothing")
	props.items[1].pos.x += 0.6 // and the flask
	scale_update(&sc, props)
	testing.expect_value(t, sc.tare, f32(0))
}

@(test)
zeroing_takes_what_is_on_the_plate_off_the_display_until_it_is_taken_off :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	x, z := plate_middle()
	props_add(props, l, .Beaker, x, z, u16(chemistry.Id.Water), 100)
	settle_for(props, l, p, 1)
	sc := Scale {
		aimed = true,
	}
	testing.expect(t, scale_zero_ready(&sc, props), "ready with a vessel on it")
	testing.expect(t, scale_zero(&sc, props), "zeroed")
	grams, _ := scale_reading(&sc, props)
	testing.expect(t, near(grams, 0, 0.01), "the display reads nothing")
	testing.expect(t, !scale_zero_ready(&sc, props), "and there is nothing to zero")
	testing.expect(t, !scale_zero(&sc, props), "so zeroing again does nothing")
	// Pour 50 ml in: the display reads the 50.
	fill_with(&props.items[0].mix, id(.Water), ml_of(&props.items[0].mix) + 50)
	grams, _ = scale_reading(&sc, props)
	testing.expect(t, near(grams, 50, 0.01), "what was added")
	// Take the vessel off, and the tare goes.
	props.items[0].pos.x += 0.6
	scale_update(&sc, props)
	testing.expect_value(t, sc.tare, f32(0))
	// While it is on, the tare is kept.
	props.items[0].pos.x -= 0.6
	scale_update(&sc, props)
	testing.expect_value(t, sc.tare, f32(0))
	sc.tare = 30
	scale_update(&sc, props)
	testing.expect_value(t, sc.tare, f32(30))
}

@(test)
the_scale_is_zeroed_only_when_aimed_at_with_empty_hands :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	x, z := plate_middle()
	props_add(props, l, .Beaker, x, z, u16(chemistry.Id.Water), 100)
	settle_for(props, l, p, 1)
	sc: Scale
	testing.expect(t, !scale_zero_ready(&sc, props), "not aimed at")
	sc.aimed = true
	props_add(props, l, .Flask, 2, 0.4)
	props.held = 1
	testing.expect(t, !scale_zero_ready(&sc, props), "a vessel in the hands")
	props.held = -1
	testing.expect(t, scale_zero_ready(&sc, props), "ready")
}

@(test)
the_scale_and_the_cabinet_are_aimed_at_within_reach_unless_a_vessel_is_nearer :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	x, z := plate_middle()
	sc: Scale
	fa: First_Aid
	// Standing at the counter, looking at the scale.
	p.x, p.z = x, z + 1.0
	look_at(p, {x, lab.COUNTER_HEIGHT + 0.08, z})
	update(props, l, p, 1.0 / 60)
	testing.expect(t, scale_aim(&sc, props, view_of(p)), "aimed at the scale")
	testing.expect(t, !first_aid_aim(&fa, props, view_of(p)), "and not at the cabinet")
	// Too far away.
	p.z = z + 3
	look_at(p, {x, lab.COUNTER_HEIGHT + 0.08, z})
	update(props, l, p, 1.0 / 60)
	testing.expect(t, !scale_aim(&sc, props, view_of(p)), "out of reach")
	// A vessel on the plate under the crosshair comes first.
	props_add(props, l, .Beaker, x, z, u16(chemistry.Id.Water), 100)
	p.z = z + 1.0
	look_at(p, {x, lab.COUNTER_HEIGHT + 0.12, z})
	settle_for(props, l, p, 1)
	testing.expect(t, props.aimed != -1, "the crosshair is on the vessel")
	testing.expect(t, !scale_aim(&sc, props, view_of(p)), "so it is not on the scale")
	// The cabinet, on the wall over the counter.
	props.count = 0
	c := lab.FIRST_AID_CENTER
	p.x, p.z = c.x, -6.3
	look_at(p, c)
	update(props, l, p, 1.0 / 60)
	testing.expect(t, first_aid_aim(&fa, props, view_of(p)), "aimed at the cabinet")
	testing.expect(t, !scale_aim(&sc, props, view_of(p)), "and not at the scale")
	// A vessel under the crosshair comes before the cabinet, as before the scale.
	p.z = -6.3
	look_at(p, c)
	update(props, l, p, 1.0 / 60)
	props_add(props, l, .Beaker, 0, 0.4)
	props.aimed = 0
	testing.expect(t, !first_aid_aim(&fa, props, view_of(p)), "a vessel is nearer the crosshair")
	props.aimed = -1
	testing.expect(t, first_aid_aim(&fa, props, view_of(p)), "and with none it is the cabinet again")
	p.z = -3
	look_at(p, c)
	update(props, l, p, 1.0 / 60)
	testing.expect(t, !first_aid_aim(&fa, props, view_of(p)), "out of reach")
}

// ---------------------------------------------------------------- the first aid cabinet

@(test)
the_cabinet_puts_health_back_at_once_and_then_has_to_rest :: proc(t: ^testing.T) {
	h: Health
	health_init(&h)
	fa: First_Aid
	testing.expect(t, !first_aid_ready(&fa, &h), "nothing to heal at full health")
	testing.expect(t, !first_aid_use(&fa, &h), "so using it does nothing")
	testing.expect_value(t, fa.cooldown, f32(0))
	health_hurt(&h, 60)
	testing.expect(t, first_aid_ready(&fa, &h), "ready when hurt")
	testing.expect(t, first_aid_use(&fa, &h), "used")
	testing.expect_value(t, h.hp, HEALTH_MAX)
	testing.expect_value(t, h.flash, f32(0))
	testing.expect_value(t, fa.cooldown, f32(30))
	// Hurt again straight away: it has to rest.
	health_hurt(&h, 50)
	testing.expect(t, !first_aid_ready(&fa, &h), "resting")
	testing.expect(t, !first_aid_use(&fa, &h), "so nothing happens")
	testing.expect_value(t, h.hp, HEALTH_MAX - 50)
	first_aid_update(&fa, 29)
	testing.expect(t, !first_aid_ready(&fa, &h), "29 s is not enough")
	first_aid_update(&fa, 2)
	testing.expect_value(t, fa.cooldown, f32(0))
	testing.expect(t, first_aid_ready(&fa, &h), "30 s is")
	// Barely hurt is not enough to need it.
	h.hp = HEALTH_MAX - 0.4
	testing.expect(t, !first_aid_ready(&fa, &h), "a scratch")
	h.hp = HEALTH_MAX - 0.6
	testing.expect(t, first_aid_ready(&fa, &h), "a little more than a scratch")
}

@(test)
the_grab_button_uses_the_cabinet_only_aimed_at_with_empty_hands_and_ready :: proc(t: ^testing.T) {
	props: Props
	props_init(&props)
	h: Health
	health_init(&h)
	health_hurt(&h, 50)
	fa := First_Aid {
		aimed = true,
	}
	testing.expect(t, first_aid_use_ready(&fa, &props, &h), "ready")
	props.held = 0
	testing.expect(t, !first_aid_use_ready(&fa, &props, &h), "a vessel in the hands")
	props.held = -1
	fa.aimed = false
	testing.expect(t, !first_aid_use_ready(&fa, &props, &h), "not aimed at")
	fa.aimed = true
	fa.cooldown = 5
	testing.expect(t, !first_aid_use_ready(&fa, &props, &h), "resting")
	fa.cooldown = 0
	h.hp = HEALTH_MAX
	testing.expect(t, !first_aid_use_ready(&fa, &props, &h), "not hurt")
}

// ---------------------------------------------------------------- weights and shelves

@(test)
a_vessel_weighs_its_glass_and_what_is_in_it :: proc(t: ^testing.T) {
	testing.expect_value(t, vessel_grams({kind = .Beaker}), f32(60))
	flask := Prop {
		kind = .Flask,
	}
	fill_with(&flask.mix, 1, 40)
	bottle := Prop {
		kind = .Bottle,
	}
	fill_with(&bottle.mix, 2, 600)
	vial := Prop {
		kind = .Vial,
	}
	fill_with(&vial.mix, 3, 12)
	testing.expect_value(t, vessel_grams(flask), f32(125))
	testing.expect_value(t, vessel_grams(bottle), f32(710))
	testing.expect_value(t, vessel_grams(vial), f32(20))
	// A mixture weighs what all its compounds weigh.
	both := Prop {
		kind = .Beaker,
	}
	fill_with(&both.mix, 1, 100)
	chemistry.mix_add(&both.mix, .Ethanol, 50, 1, ROOM_C)
	testing.expect_value(t, vessel_grams(both), f32(210))
	for id in 0 ..= chemistry.COMPOUND_COUNT {
		testing.expect_value(t, compound_density(u16(id)), f32(1))
	}
}

@(test)
the_shelf_bottles_are_coloured_by_the_compounds_in_turn :: proc(t: ^testing.T) {
	colors := shelf_colors()
	for i in 0 ..< lab.SHELF_BOTTLES {
		c := chemistry.compounds[i % chemistry.COMPOUND_COUNT].color
		testing.expect_value(t, colors[i], [4]u8{c.r, c.g, c.b, 255})
	}
	testing.expect_value(t, colors[0], [4]u8{0x6f, 0xb4, 0xe8, 255}) // water is first and blue
	testing.expect_value(t, colors[chemistry.COMPOUND_COUNT], colors[0]) // and the colours start over after the last compound
}

// The middle of the plate of a scale at spot `i`.
plate_at :: proc(i: int) -> (x, z: f32) {
	r := lab.bench_rect(.Scale, i)
	return (r.min_x + r.max_x) * 0.5, (r.min_z + r.max_z) * 0.5
}

@(test)
a_scale_that_is_moved_weighs_what_stands_on_it_now_and_not_what_stood_on_it :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props.bench = {}
	props.bench.spots[2] = .Scale // moved from spot 4
	nx, nz := plate_at(2)
	ox, oz := plate_middle() // where it used to be
	props_add(props, l, .Beaker, nx, nz, u16(chemistry.Id.Water), 100)
	props_add(props, l, .Beaker, ox, oz, u16(chemistry.Id.Water), 100)
	settle_for(props, l, p, 1)
	grams, count := scale_load(props)
	testing.expect_value(t, count, 1)
	testing.expect(t, near(grams, 160, 0.01), "only the beaker on the plate where it is now")
	testing.expect(t, scale_on(props, 0), "the first is on it")
	testing.expect(t, !scale_on(props, 1), "the second is on bare bench")
}

@(test)
the_plate_of_a_moved_scale_lifts_the_vessels_on_it_and_the_old_place_does_not :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props.bench = {}
	props.bench.spots[0] = .Scale
	nx, nz := plate_at(0)
	ox, oz := plate_middle()
	props_add(props, l, .Beaker, nx, nz, u16(chemistry.Id.Water), 100)
	props_add(props, l, .Beaker, ox, oz, u16(chemistry.Id.Water), 100)
	settle_for(props, l, p, 1)
	plate := lab.COUNTER_HEIGHT + lab.SCALE_PLATE_TOP
	testing.expect(t, near(props.items[0].pos.y, plate, 0.001), "stands on the plate")
	testing.expect(t, near(props.items[1].pos.y, lab.COUNTER_HEIGHT, 0.001), "and on the bare counter at the old place")
	testing.expect_value(t, standing_height(l, &props.items[1], &props.bench), lab.COUNTER_HEIGHT)
	testing.expect(t, standing_height(l, &props.items[1]) > lab.COUNTER_HEIGHT, "with no bench given, the old place is the plate")
}

@(test)
the_scale_is_aimed_at_where_it_stands_now :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props.aimed = -1
	props.bench = {}
	props.bench.spots[3] = .Scale
	sc: Scale
	view := View{eye = {lab.bench_spot_x(3), lab.COUNTER_HEIGHT + 0.1, -7.63 + 0.9}, back = {0, 0, 1}}
	testing.expect(t, scale_aim(&sc, props, view), "at its new place")
	view.eye.x = lab.bench_spot_x(4)
	testing.expect(t, !scale_aim(&sc, props, view), "not at the old one")
	props.bench.spots[4] = .Scale // two scales: the nearer is the one
	testing.expect(t, scale_aim(&sc, props, view), "either of two")
	props.bench = {}
	testing.expect(t, !scale_aim(&sc, props, view), "none at all")
}
