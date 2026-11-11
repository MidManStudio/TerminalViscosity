// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "arena_test.odin"
// ============================================================================

package arena

import "../carry"
import "../chem"
import "core:math"
import "core:testing"

near :: proc(a, b: f32, tolerance: f32 = 0.0001) -> bool {
	return abs(a - b) <= tolerance
}

@(test)
looking_follows_the_labs_headings :: proc(t: ^testing.T) {
	d := look_dir({yaw = 0, pitch = 0})
	testing.expect(t, near(d.x, 0) && near(d.y, 0) && near(d.z, -1), "yaw 0 looks toward -z")
	d = look_dir({yaw = math.PI * 0.5, pitch = 0})
	testing.expect(t, near(d.x, 1) && near(d.z, 0), "a quarter turn looks toward +x")
	d = look_dir({yaw = 1, pitch = 0.7})
	testing.expect(t, near(d.x * d.x + d.y * d.y + d.z * d.z, 1), "the direction is a unit vector")
	testing.expect(t, d.y > 0.6 && d.y < 0.7, "looking up points up")
}

@(test)
looking_up_and_down_stops_short_of_straight :: proc(t: ^testing.T) {
	l: Look
	look_turn(&l, 0.5, 5)
	testing.expect_value(t, l.pitch, PITCH_LIMIT)
	testing.expect_value(t, l.yaw, f32(0.5))
	look_turn(&l, 0.25, -50)
	testing.expect_value(t, l.pitch, -PITCH_LIMIT)
	testing.expect_value(t, l.yaw, f32(0.75))
}

@(test)
the_wire_direction_keeps_its_heading_and_is_scaled_to_1000 :: proc(t: ^testing.T) {
	d := dir_wire({0, 0, -0.5})
	testing.expect_value(t, d, [3]i16{0, 0, -1000})
	d = dir_wire({0.6, 0.3, -1.2})
	testing.expect_value(t, d, [3]i16{500, 250, -1000})
	d = dir_wire({-2, 4, 1})
	testing.expect_value(t, d, [3]i16{-500, 1000, 250})
	testing.expect_value(t, dir_wire({0, 0, 0}), [3]i16{})
}

@(test)
a_throw_charges_over_the_set_time_and_stops_at_full :: proc(t: ^testing.T) {
	c := f32(0)
	for _ in 0 ..< 60 {
		c = charge_step(c, CHARGE_SECONDS / 120)
	}
	testing.expect(t, near(c, 0.5, 0.001), "half the time is half the charge")
	for _ in 0 ..< 200 {
		c = charge_step(c, 0.1)
	}
	testing.expect_value(t, c, f32(1))
	testing.expect_value(t, charge_step(0.3, -10), f32(0))
}

@(test)
power_runs_from_the_weakest_to_the_strongest_throw :: proc(t: ^testing.T) {
	testing.expect_value(t, charge_power(0), POWER_MIN)
	testing.expect_value(t, charge_power(1), POWER_MAX)
	testing.expect_value(t, charge_power(7), POWER_MAX)
	testing.expect_value(t, charge_power(-3), POWER_MIN)
	mid := charge_power(0.5)
	testing.expect_value(t, mid, u8((int(POWER_MIN) + int(POWER_MAX)) / 2))
	last := POWER_MIN
	for i in 0 ..= 20 {
		p := charge_power(f32(i) / 20)
		testing.expect(t, p >= last, "power never falls as the charge grows")
		last = p
	}
}

loadout_with :: proc(hooks: [carry.LOADOUT_SLOTS]carry.Item) -> carry.Loadout {
	return carry.Loadout{slots = hooks, spot_slot = -1}
}

@(test)
slots_follow_the_hooks_one_for_one :: proc(t: ^testing.T) {
	lo := loadout_with({{}, {used = true, compound = 4, ml = 640.4, art = 7}, {used = true, compound = 9, ml = 1000}})
	s := slots_from_loadout(&lo)
	testing.expect(t, !s[0].used, "an empty hook stays empty")
	testing.expect_value(t, s[1], Slot{used = true, compound = 4, ml = 640, art = 7})
	testing.expect_value(t, s[2], Slot{used = true, compound = 9, ml = 1000})
}

@(test)
fill_is_rounded_and_kept_inside_what_a_balloon_holds :: proc(t: ^testing.T) {
	lo := loadout_with({{used = true, compound = 1, ml = 0.2}, {used = true, compound = 1, ml = 640.6}, {used = true, compound = 1, ml = 5000}})
	s := slots_from_loadout(&lo)
	testing.expect_value(t, s[0].ml, u16(1))
	testing.expect_value(t, s[1].ml, u16(641))
	testing.expect_value(t, s[2].ml, u16(carry.BALLOON_REST_ML))
}

@(test)
an_empty_loadout_offers_one_practice_water_balloon :: proc(t: ^testing.T) {
	lo := loadout_with({})
	s := slots_from_loadout(&lo)
	testing.expect_value(t, s[0], Slot{used = true, compound = u16(chem.Id.Water), ml = PRACTICE_ML, practice = true})
	testing.expect(t, !s[1].used && !s[2].used, "only the first slot is offered")
}

@(test)
a_loadout_with_any_balloon_gets_no_practice_one :: proc(t: ^testing.T) {
	lo := loadout_with({{}, {}, {used = true, compound = 3, ml = 100}})
	s := slots_from_loadout(&lo)
	testing.expect(t, !s[0].used, "hook 0 stays empty")
	testing.expect(t, !s[0].practice && !s[2].practice, "none of them is a practice balloon")
}

ready_slots :: proc(used: [carry.LOADOUT_SLOTS]bool) -> (s: [carry.LOADOUT_SLOTS]Slot) {
	for u, i in used {
		s[i] = {
			used     = u,
			compound = 1,
			ml       = 100,
		}
	}
	return
}

@(test)
the_thrower_starts_on_the_first_balloon_it_has :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({false, false, true})
	thrower_init(&th, &s)
	testing.expect_value(t, th.selected, 2)
	s = ready_slots({true, true, true})
	thrower_init(&th, &s)
	testing.expect_value(t, th.selected, 0)
	s = ready_slots({false, false, false})
	thrower_init(&th, &s)
	testing.expect_value(t, th.selected, 0)
	testing.expect(t, !thrower_ready(&th, &s), "nothing to throw")
}

@(test)
only_a_slot_with_a_balloon_can_be_chosen :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, false, true})
	thrower_init(&th, &s)
	testing.expect(t, !thrower_select(&th, &s, 1), "an empty slot is refused")
	testing.expect_value(t, th.selected, 0)
	testing.expect(t, !thrower_select(&th, &s, -1) && !thrower_select(&th, &s, 3), "slots outside the loadout are refused")
	testing.expect(t, thrower_select(&th, &s, 2), "a slot with a balloon is taken")
	testing.expect_value(t, th.selected, 2)
}

@(test)
choosing_another_balloon_drops_a_throw_in_progress :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, true, true})
	thrower_init(&th, &s)
	thrower_update(&th, &s, true, 0.3)
	testing.expect(t, th.charging && th.charge > 0.2, "charging")
	thrower_select(&th, &s, 1)
	testing.expect(t, !th.charging && th.charge == 0, "the charge was dropped")
	fire, _ := thrower_update(&th, &s, false, 0.016)
	testing.expect(t, !fire, "letting go afterwards throws nothing")
}

@(test)
holding_charges_and_letting_go_throws_at_the_power_reached :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, false, false})
	thrower_init(&th, &s)
	for _ in 0 ..< 36 { // 0.6 s, half way
		fire, _ := thrower_update(&th, &s, true, 1.0 / 60)
		testing.expect(t, !fire, "nothing is thrown while the button is held")
	}
	fire, power := thrower_update(&th, &s, false, 1.0 / 60)
	testing.expect(t, fire, "letting go throws")
	testing.expect(t, power > charge_power(0.45) && power < charge_power(0.55), "about half power")
	testing.expect(t, !th.charging && th.charge == 0, "the charge is spent")
}

@(test)
a_full_charge_is_the_strongest_throw_however_long_it_is_held :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, false, false})
	thrower_init(&th, &s)
	for _ in 0 ..< 600 {
		thrower_update(&th, &s, true, 1.0 / 60)
	}
	fire, power := thrower_update(&th, &s, false, 1.0 / 60)
	testing.expect(t, fire, "thrown")
	testing.expect_value(t, power, POWER_MAX)
}

@(test)
a_balloon_that_goes_while_it_is_being_charged_is_not_thrown :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, false, false})
	thrower_init(&th, &s)
	thrower_update(&th, &s, true, 0.4)
	testing.expect(t, th.charging, "charging")
	s[0].used = false
	fire, _ := thrower_update(&th, &s, false, 0.016)
	testing.expect(t, !fire, "nothing is thrown")
	testing.expect(t, !th.charging && th.charge == 0, "and the charge is dropped")
	testing.expect(t, th.cooldown == 0, "with no cooldown for a throw that did not happen")
}

@(test)
a_tap_is_a_weak_throw_not_no_throw :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, false, false})
	thrower_init(&th, &s)
	thrower_update(&th, &s, true, 1.0 / 60)
	fire, power := thrower_update(&th, &s, false, 1.0 / 60)
	testing.expect(t, fire, "a tap throws")
	testing.expect(t, power >= POWER_MIN && power < POWER_MIN + 4, "and throws gently")
}

@(test)
a_second_throw_has_to_wait_out_the_cooldown :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, false, false})
	thrower_init(&th, &s)
	thrower_update(&th, &s, true, 0.1)
	fire, _ := thrower_update(&th, &s, false, 0.016)
	testing.expect(t, fire, "the first throw goes")
	testing.expect(t, !thrower_ready(&th, &s), "the button shows it is not ready")
	// Holding straight away does not start a charge.
	thrower_update(&th, &s, true, 0.1)
	testing.expect(t, !th.charging, "no charge during the cooldown")
	fire, _ = thrower_update(&th, &s, false, 0.1)
	testing.expect(t, !fire, "and letting go throws nothing")
	// After the cooldown it works again.
	thrower_update(&th, &s, false, THROW_COOLDOWN)
	testing.expect(t, thrower_ready(&th, &s), "ready again")
	thrower_update(&th, &s, true, 0.1)
	fire, _ = thrower_update(&th, &s, false, 0.016)
	testing.expect(t, fire, "the second throw goes")
}

@(test)
nothing_is_thrown_from_an_empty_slot :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({false, false, false})
	thrower_init(&th, &s)
	thrower_update(&th, &s, true, 0.5)
	testing.expect(t, !th.charging, "an empty slot never charges")
	fire, _ := thrower_update(&th, &s, false, 0.016)
	testing.expect(t, !fire, "nothing is thrown")
}

@(test)
releasing_without_ever_pressing_throws_nothing :: proc(t: ^testing.T) {
	th: Thrower
	s := ready_slots({true, true, true})
	thrower_init(&th, &s)
	for _ in 0 ..< 10 {
		fire, _ := thrower_update(&th, &s, false, 1.0 / 60)
		testing.expect(t, !fire, "no throw without a press")
	}
}

@(test)
a_player_is_on_the_floor_until_the_feet_leave_it :: proc(t: ^testing.T) {
	testing.expect(t, on_floor({pos = {1, 0, 2}}), "standing")
	testing.expect(t, on_floor({pos = {1, 0.019, 2}}), "a couple of centimetres is still the floor, for the loose ends of a jump")
	testing.expect(t, !on_floor({pos = {1, 0.05, 2}}), "five centimetres up is not")
	testing.expect(t, !on_floor({pos = {1, 0.4, 2}}), "nor is the top of a jump")
	testing.expect_value(t, eye_of({pos = {0, 0.4, 0}}).y, f32(0.4) + EYE_HEIGHT) // and the eye goes up with the feet
}

@(test)
a_throw_is_seen_when_a_balloon_of_the_owner_appears :: proc(t: ^testing.T) {
	prev, curr: Match_View
	prev.balloons[0] = {id = 5, owner = 1}
	prev.balloon_count = 1
	curr.balloons[0] = {id = 5, owner = 1}
	curr.balloon_count = 1
	testing.expect(t, !thrown_by(&prev, &curr, 1), "the same balloon is not a throw")
	curr.balloons[1] = {id = 6, owner = 1}
	curr.balloon_count = 2
	testing.expect(t, thrown_by(&prev, &curr, 1), "a new one of theirs is")
	testing.expect(t, !thrown_by(&prev, &curr, 2), "and it is not somebody else's")
	curr.balloons[1].owner = 2
	testing.expect(t, thrown_by(&prev, &curr, 2) && !thrown_by(&prev, &curr, 1), "it is the owner's that counts")
	prev.balloon_count = 0
	curr.balloon_count = 0
	testing.expect(t, !thrown_by(&prev, &curr, 1), "no balloons, no throw")
	// A balloon that burst between the views is not a throw either.
	prev.balloons[0] = {id = 9, owner = 1}
	prev.balloon_count = 1
	testing.expect(t, !thrown_by(&prev, &curr, 1), "a balloon that is gone is not a throw")
}

@(test)
players_are_found_by_id_and_the_eye_is_above_the_feet :: proc(t: ^testing.T) {
	v: Match_View
	v.players[0] = {id = 3, pos = {1, 0, 2}, yaw = 0.5}
	v.players[1] = {id = 5, pos = {-4, 0, 6}}
	v.player_count = 2
	p, ok := view_player(&v, 5)
	testing.expect(t, ok && p.pos == Vec3{-4, 0, 6}, "found by id, not by position in the list")
	_, ok = view_player(&v, 4)
	testing.expect(t, !ok, "a player who is not there is not found")
	v.player_count = 1
	_, ok = view_player(&v, 5)
	testing.expect(t, !ok, "only the first player_count entries count")
	testing.expect_value(t, eye_of(v.players[0]), Vec3{1, EYE_HEIGHT, 2})
}

// A host that only records what it is told and plays back what it is given, which is
// all a scene may rely on.
Fake_Host :: struct {
	view:       Match_View,
	inputs:     [dynamic]Input,
	throws:     [dynamic]Throw,
	steps:      f32,
	accept:     bool,
}

fake_input :: proc(data: rawptr, input: Input) {
	h := cast(^Fake_Host)data
	append(&h.inputs, input)
}

fake_throw :: proc(data: rawptr, throw: Throw) -> bool {
	h := cast(^Fake_Host)data
	append(&h.throws, throw)
	return h.accept
}

fake_step :: proc(data: rawptr, dt: f32) {
	h := cast(^Fake_Host)data
	h.steps += dt
	h.view.tick += 1
}

fake_view :: proc(data: rawptr) -> ^Match_View {
	return &(cast(^Fake_Host)data).view
}

@(test)
a_host_is_driven_only_through_its_table :: proc(t: ^testing.T) {
	fake := Fake_Host{accept = true}
	defer delete(fake.inputs)
	defer delete(fake.throws)
	host := Host{data = &fake, submit_input = fake_input, submit_throw = fake_throw, step = fake_step, view = fake_view}

	host_input(&host, {forward = 1, strafe = -0.5, yaw = 2})
	testing.expect_value(t, len(fake.inputs), 1)
	testing.expect_value(t, fake.inputs[0], Input{forward = 1, strafe = -0.5, yaw = 2})

	ok := host_throw(&host, {slot = 2, compound = 4, ml = 300, dir = {0, 1, 0}, power = 100})
	testing.expect(t, ok, "the answer of the host is passed back")
	testing.expect_value(t, fake.throws[0].slot, u8(2))
	fake.accept = false
	testing.expect(t, !host_throw(&host, {}), "a refusal is passed back too")

	host_step(&host, 0.25)
	host_step(&host, 0.25)
	testing.expect_value(t, fake.steps, f32(0.5))
	testing.expect_value(t, host_view(&host).tick, u32(2))
}

@(test)
headings_turn_the_short_way_round :: proc(t: ^testing.T) {
	d := math.to_radians(f32(1))
	testing.expect(t, near(lerp_angle(350 * d, 10 * d, 0.5), 360 * d, 0.0005), "350 to 10 goes through 0")
	testing.expect(t, near(lerp_angle(10 * d, 350 * d, 0.5), 0, 0.0005), "and back the same way")
	testing.expect(t, near(lerp_angle(0.5, 1.5, 0.25), 0.75), "a plain turn is a plain lerp")
	testing.expect(t, near(lerp_angle(0.5, 1.5, 0), 0.5) && near(lerp_angle(0.5, 1.5, 1), 1.5), "the ends are the ends")
	testing.expect(t, near(lerp_angle(5, 5, 0.7), 5), "no turn stays put")
}

@(test)
drawing_between_ticks_lies_between_them :: proc(t: ^testing.T) {
	prev, curr, out: Match_View
	prev.players[0] = {id = 2, pos = {0, 0, 10}, yaw = 0}
	prev.player_count = 1
	curr.players[0] = {id = 2, pos = {2, 0, 6}, yaw = 1}
	curr.player_count = 1
	prev.balloons[0] = {id = 7, owner = 2, pos = {0, 1, 0}, vel = {1, 0, 0}}
	prev.balloon_count = 1
	curr.balloons[0] = {id = 7, owner = 2, slot = 1, compound = 5, pos = {4, 3, 0}, vel = {1, 0, 0}}
	curr.tick = 99
	curr.balloon_count = 1
	out.burst_count = 3

	view_blend(&out, &prev, &curr, 0.25)
	testing.expect_value(t, out.tick, u32(99))
	testing.expect_value(t, out.players[0].pos, Vec3{0.5, 0, 9})
	testing.expect(t, near(out.players[0].yaw, 0.25), "the heading is blended too")
	testing.expect_value(t, out.balloons[0].pos, Vec3{1, 1.5, 0})
	testing.expect_value(t, out.balloons[0].slot, u8(1))
	testing.expect_value(t, out.balloons[0].compound, u16(5))
	testing.expect_value(t, out.burst_count, 3)

	view_blend(&out, &prev, &curr, 0)
	testing.expect_value(t, out.players[0].pos, prev.players[0].pos)
	view_blend(&out, &prev, &curr, 1)
	testing.expect_value(t, out.players[0].pos, curr.players[0].pos)
	view_blend(&out, &prev, &curr, 7)
	testing.expect_value(t, out.balloons[0].pos, curr.balloons[0].pos)
	view_blend(&out, &prev, &curr, -2)
	testing.expect_value(t, out.balloons[0].pos, prev.balloons[0].pos)
}

@(test)
things_that_are_new_appear_where_they_are_and_things_that_are_gone_do_not :: proc(t: ^testing.T) {
	prev, curr, out: Match_View
	prev.players[0] = {id = 1, pos = {1, 0, 1}}
	prev.player_count = 1
	prev.balloons[0] = {id = 4, pos = {1, 1, 1}}
	prev.balloons[1] = {id = 5, pos = {2, 2, 2}}
	prev.balloon_count = 2
	// Player 1 has gone, player 3 is new. Balloon 4 burst, 5 flies on, 6 was just thrown.
	curr.players[0] = {id = 3, pos = {9, 0, 9}}
	curr.player_count = 1
	curr.balloons[0] = {id = 5, pos = {4, 4, 4}}
	curr.balloons[1] = {id = 6, pos = {7, 7, 7}}
	curr.balloon_count = 2

	view_blend(&out, &prev, &curr, 0.5)
	testing.expect_value(t, out.player_count, 1)
	testing.expect_value(t, out.players[0].pos, Vec3{9, 0, 9})
	testing.expect_value(t, out.balloon_count, 2)
	testing.expect_value(t, out.balloons[0].pos, Vec3{3, 3, 3})
	testing.expect_value(t, out.balloons[1].pos, Vec3{7, 7, 7})
}

@(test)
balloons_are_matched_by_id_not_by_place_in_the_list :: proc(t: ^testing.T) {
	prev, curr, out: Match_View
	prev.balloons[0] = {id = 1, pos = {0, 0, 0}}
	prev.balloons[1] = {id = 2, pos = {10, 0, 0}}
	prev.balloon_count = 2
	curr.balloons[0] = {id = 2, pos = {12, 0, 0}}
	curr.balloons[1] = {id = 1, pos = {2, 0, 0}}
	curr.balloon_count = 2
	view_blend(&out, &prev, &curr, 0.5)
	testing.expect_value(t, out.balloons[0].pos.x, f32(11))
	testing.expect_value(t, out.balloons[1].pos.x, f32(1))
}

@(test)
a_player_with_no_hit_points_is_knocked_out :: proc(t: ^testing.T) {
	testing.expect(t, knocked_out({id = 1, hp = 0}), "no hit points")
	testing.expect(t, !knocked_out({id = 1, hp = 1}), "one is enough to be standing")
	testing.expect(t, !knocked_out({id = 1, hp = MAX_HEALTH}), "a full set")
}

@(test)
blending_shows_the_hit_points_of_the_later_tick :: proc(t: ^testing.T) {
	prev, curr, out: Match_View
	prev.player_count, curr.player_count = 1, 1
	prev.players[0] = {id = 2, pos = {0, 0, 10}, hp = 100}
	curr.players[0] = {id = 2, pos = {0, 0, 8}, hp = 40}
	view_blend(&out, &prev, &curr, 0.5)
	testing.expect_value(t, out.players[0].hp, u8(40))
	// A player the earlier tick did not have comes as the later tick has them.
	prev.player_count = 0
	view_blend(&out, &prev, &curr, 0.5)
	testing.expect_value(t, out.players[0].hp, u8(40))
}

@(test)
cancelling_a_charge_throws_nothing_and_costs_no_cooldown :: proc(t: ^testing.T) {
	slots: [carry.LOADOUT_SLOTS]Slot
	slots[0] = {
		used     = true,
		compound = u16(chem.Id.Water),
		ml       = 500,
	}
	th: Thrower
	thrower_init(&th, &slots)
	thrower_update(&th, &slots, true, 0.3)
	testing.expect(t, th.charging && th.charge > 0.2, "it is charging")
	thrower_cancel(&th)
	testing.expect(t, !th.charging && th.charge == 0, "not any more")
	fire, _ := thrower_update(&th, &slots, false, 0.1)
	testing.expect(t, !fire, "letting go after that throws nothing")
	testing.expect_value(t, th.cooldown, f32(0))
	// And it can start again at once.
	thrower_update(&th, &slots, true, 0.1)
	testing.expect(t, th.charging, "a new charge starts")
}
