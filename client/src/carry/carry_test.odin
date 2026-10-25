// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "carry_test.odin"
// ============================================================================

package carry

import "../chem"
import "../lab"
import "core:math"
import "core:testing"

length :: proc(a: Vec3) -> f32 {
	return math.sqrt(dot(a, a))
}

// A layout, a player at the south edge of the island looking at its top, and
// an empty list of props.
make_scene :: proc() -> (l: ^lab.Layout, p: ^lab.Player, props: ^Props) {
	l = new(lab.Layout)
	p = new(lab.Player)
	props = new(Props)
	lab.build(l)
	lab.player_init(p, l)
	p.x, p.z = 0, 1.2
	props_init(props)
	return
}

free_scene :: proc(l: ^lab.Layout, p: ^lab.Player, props: ^Props) {
	free(l)
	free(p)
	free(props)
}

// Points the view at a spot in the world.
look_at :: proc(p: ^lab.Player, target: Vec3) {
	d := target - Vec3{p.x, lab.EYE_HEIGHT, p.z}
	p.yaw = math.atan2(d.x, -d.z)
	p.pitch = math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z))
}

// Bands in the glass of each kind: up the outside, over the rim, down the inside.
glass_bands :: proc(k: Kind) -> int {
	switch k {
	case .Beaker:
		return 5
	case .Flask:
		return 7
	case .Bottle:
		return 9
	}
	return 0
}

// Bands in the liquid solid of each kind.
liquid_bands :: proc(k: Kind) -> int {
	switch k {
	case .Beaker:
		return 3
	case .Flask:
		return 4
	case .Bottle:
		return 5
	}
	return 0
}

vertices_for :: proc(bands: int) -> int {
	return bands * 2 * (SHAPE_SEGMENTS + 1)
}

check_shape :: proc(t: ^testing.T, s: ^Shape, name: string) {
	testing.expectf(t, s.vert_count > 0 && s.vert_count < MAX_SHAPE_VERTS, "%v: %v vertices", name, s.vert_count)
	testing.expectf(t, s.index_count > 0 && s.index_count < MAX_SHAPE_INDICES && s.index_count % 3 == 0, "%v: %v indices", name, s.index_count)
	for i in 0 ..< s.vert_count {
		n := length(s.normals[i])
		testing.expectf(t, abs(n - 1) < 1e-4, "%v: normal %v has length %v", name, i, n)
	}
	for i := 0; i < s.index_count; i += 3 {
		a, b, c := int(s.indices[i]), int(s.indices[i + 1]), int(s.indices[i + 2])
		testing.expectf(t, a < s.vert_count && b < s.vert_count && c < s.vert_count, "%v: index out of range", name)
		facing := cross(s.positions[b] - s.positions[a], s.positions[c] - s.positions[a])
		if length(facing) < 1e-9 {
			continue // a sliver where a band touches the axis
		}
		average := s.normals[a] + s.normals[b] + s.normals[c]
		testing.expectf(t, dot(facing, average) > 0, "%v: triangle %v faces inward", name, i / 3)
	}
}

@(test)
every_shape_faces_outward_and_fits :: proc(t: ^testing.T) {
	s := new(Shape)
	defer free(s)
	for k in Kind {
		vessel_shape(s, k)
		check_shape(t, s, "glass")
		testing.expect_value(t, s.vert_count, vertices_for(glass_bands(k)))
		liquid_shape(s, k)
		check_shape(t, s, "liquid")
		testing.expect_value(t, s.vert_count, vertices_for(liquid_bands(k)))
		has_cap := cap_shape(s, k)
		testing.expect_value(t, has_cap, k == .Bottle)
		if has_cap {
			check_shape(t, s, "cap")
			testing.expect_value(t, s.vert_count, vertices_for(3))
		}
	}
	box_build(s, {255, 255, 255, 255})
	check_shape(t, s, "box")
	testing.expect_value(t, s.vert_count, 24)
	testing.expect_value(t, s.index_count, 36)
}

@(test)
vessels_stay_inside_their_footprint :: proc(t: ^testing.T) {
	s := new(Shape)
	defer free(s)
	for k in Kind {
		d := kind_dims(k)
		for part in 0 ..< 3 {
			switch part {
			case 0:
				vessel_shape(s, k)
			case 1:
				liquid_shape(s, k)
			case:
				if !cap_shape(s, k) {
					continue
				}
			}
			for i in 0 ..< s.vert_count {
				p := s.positions[i]
				reach := math.sqrt(p.x * p.x + p.z * p.z)
				testing.expectf(t, reach <= d.radius + 1e-4 && p.y >= -1e-4 && p.y <= d.height + 1e-4, "%v part %v vertex %v is outside its size", k, part, i)
			}
		}
	}
}

@(test)
the_view_is_a_right_handed_set :: proc(t: ^testing.T) {
	p := new(lab.Player)
	defer free(p)
	for yaw := f32(-3); yaw < 3.2; yaw += 0.7 {
		for pitch := f32(-1.2); pitch <= 1.2; pitch += 0.4 {
			p.yaw, p.pitch = yaw, pitch
			v := view_of(p)
			forward := lab.player_forward(p)
			testing.expect(t, length(v.right - cross(v.up, v.back)) < 1e-4)
			testing.expect(t, length(v.back + forward) < 1e-4)
			testing.expect(t, abs(length(v.up) - 1) < 1e-4 && abs(length(v.right) - 1) < 1e-4)
			testing.expect(t, abs(dot(v.right, v.up)) < 1e-4 && abs(dot(v.up, v.back)) < 1e-4)
		}
	}
}

@(test)
the_defaults_stand_on_the_island :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	testing.expect_value(t, props.count, 23)
	empty := 0
	for i in 0 ..< props.count {
		pr := props.items[i]
		testing.expect_value(t, pr.pos.y, lab.COUNTER_HEIGHT)
		testing.expectf(t, abs(pr.pos.x) < 5 && abs(pr.pos.z) < 0.7, "a vessel is off the island at %v", pr.pos)
		testing.expect(t, pr.ml >= 0 && pr.ml <= capacity_ml(pr.kind))
		testing.expect_value(t, pr.compound == 0, pr.ml == 0)
		if pr.compound == 0 {
			empty += 1
		}
	}
	testing.expect_value(t, empty, 13)
	// One vessel of each stock liquid, so every mix can be tried.
	for stock in 1 ..= chem.STOCK_COUNT {
		found := 0
		for i in 0 ..< props.count {
			if props.items[i].compound == u16(stock) {
				found += 1
			}
		}
		testing.expectf(t, found == 1, "%v appears %v times", chem.compound_name(u16(stock)), found)
	}
}

@(test)
no_two_vessels_on_the_island_overlap :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	for i in 0 ..< props.count {
		for j in i + 1 ..< props.count {
			a, b := props.items[i], props.items[j]
			reach := kind_dims(a.kind).radius + kind_dims(b.kind).radius
			dx, dz := a.pos.x - b.pos.x, a.pos.z - b.pos.z
			testing.expectf(t, dx * dx + dz * dz > reach * reach, "vessels %v and %v overlap", i, j)
		}
	}
}

@(test)
a_vessel_cannot_hold_more_than_its_capacity :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Flask, 0, 0.35, u16(chem.Id.Water), 1e6)
	props_add(props, l, .Beaker, 1, 0.35, 0, 500) // no compound, so nothing in it
	testing.expect_value(t, props.items[0].ml, capacity_ml(.Flask))
	testing.expect_value(t, props.items[1].ml, 0)
}

@(test)
capacities_come_from_the_shape :: proc(t: ^testing.T) {
	for k in Kind {
		c := capacity_ml(k)
		testing.expectf(t, c > 400 && c < 1000, "%v holds %v ml", k, c)
	}
	// A beaker is a plain cylinder inside, so it can be worked out by hand.
	d := kind_dims(.Beaker)
	inner := d.radius - VESSEL_WALL
	by_hand := math.PI * inner * inner * (d.height - VESSEL_WALL) * 1e6
	testing.expect(t, abs(capacity_ml(.Beaker) - by_hand) < 1)
}

@(test)
the_fill_height_matches_the_volume :: proc(t: ^testing.T) {
	for k in Kind {
		previous := f32(0)
		for ml := f32(0); ml <= capacity_ml(k); ml += 25 {
			h := fill_height(k, ml)
			testing.expectf(t, h >= previous, "%v: the level dropped at %v ml", k, ml)
			previous = h
			if ml > 0 {
				testing.expectf(t, abs(interior_volume(k, h) - ml) < 0.5, "%v: %v ml gave a level holding %v", k, ml, interior_volume(k, h))
			}
		}
		testing.expect_value(t, fill_height(k, 1e6), brim_height(k))
		testing.expect_value(t, fill_height(k, 0), VESSEL_WALL)
	}
}

@(test)
see_through_things_are_ordered_far_to_near :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_place_defaults(props, l)
	eye := Vec3{0.4, 1.7, 2.0}
	order: [MAX_PROPS]int
	n := far_to_near(props, eye, &order)
	testing.expect_value(t, n, props.count)
	for i in 1 ..< n {
		a := props.items[order[i - 1]].pos - eye
		b := props.items[order[i]].pos - eye
		testing.expect(t, dot(a, a) >= dot(b, b))
	}
}

@(test)
the_view_rises_with_a_jump :: proc(t: ^testing.T) {
	p := new(lab.Player)
	defer free(p)
	p.jump = 0.3
	testing.expect_value(t, view_of(p).eye.y, lab.EYE_HEIGHT + 0.3)
}

@(test)
the_crosshair_picks_a_prop_it_points_at :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Beaker, 0, 0.35)
	d := kind_dims(.Beaker)

	look_at(p, {0, lab.COUNTER_HEIGHT + d.height * 0.5, 0.35})
	update(props, l, p, 1.0 / 60)
	testing.expect_value(t, props.aimed, 0)
	testing.expect_value(t, state_of(props), State.Reaching)

	p.pitch = 0 // straight ahead, over the top of it
	update(props, l, p, 1.0 / 60)
	testing.expect_value(t, props.aimed, -1)
	testing.expect_value(t, state_of(props), State.Idle)

	p.x, p.z = 0, 3.2 // too far away
	look_at(p, {0, lab.COUNTER_HEIGHT + d.height * 0.5, 0.35})
	update(props, l, p, 1.0 / 60)
	testing.expect_value(t, props.aimed, -1)
}

@(test)
a_counter_hides_what_is_behind_it :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	eye := Vec3{0, lab.EYE_HEIGHT, 1.2}
	behind := Vec3{0, 0.05, -0.9} - eye // the floor behind the island
	testing.expect(t, hidden_by_counter(l, eye, behind / length(behind), length(behind)))
	on_top := Vec3{0, lab.COUNTER_HEIGHT + 0.05, 0.35} - eye
	testing.expect(t, !hidden_by_counter(l, eye, on_top / length(on_top), length(on_top)))
}

@(test)
grabbing_takes_the_aimed_prop_once :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	testing.expect(t, !grab(props)) // nothing aimed at yet
	props_add(props, l, .Flask, 0, 0.35)
	look_at(p, {0, lab.COUNTER_HEIGHT + 0.09, 0.35})
	update(props, l, p, 1.0 / 60)
	testing.expect(t, grab(props))
	testing.expect_value(t, props.held, 0)
	testing.expect(t, !grab(props))
	release(props)
	testing.expect_value(t, props.held, -1)
}

@(test)
a_held_prop_never_enters_a_counter_or_a_wall :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	for k in Kind {
		props_init(props)
		props_add(props, l, k, 0, 0.35)
		props.held = 0
		d := kind_dims(k)
		for x := f32(-11.5); x <= 11.5; x += 0.7 {
			for z := f32(-7.5); z <= 7.5; z += 0.5 {
				if lab.blocked(l, x, z) {
					continue
				}
				p.x, p.z = x, z
				for yaw := f32(0); yaw < math.TAU; yaw += 0.5 {
					for pitch := f32(-1.2); pitch <= 1.2; pitch += 0.4 {
						p.yaw, p.pitch = yaw, pitch
						update(props, l, p, 1.0 / 60)
						pos := props.items[0].pos
						inside := abs(pos.x) <= lab.ROOM_W * 0.5 && abs(pos.z) <= lab.ROOM_D * 0.5
						testing.expectf(t, inside && pos.y >= 0 && pos.y + d.height <= lab.ROOM_H + 1e-4, "%v left the room at %v", k, pos)
						if support_height(l, pos.x, pos.z, d.radius) > 0 {
							testing.expectf(t, pos.y >= lab.COUNTER_HEIGHT - 1e-4, "%v is inside a counter at %v", k, pos)
						}
					}
				}
			}
		}
	}
}

@(test)
a_vessel_in_open_space_sits_at_the_hold_point :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	p.x, p.z = 3, 4.5
	props_add(props, l, .Beaker, 3, 3)
	props.held = 0
	update(props, l, p, 1.0 / 60)
	grip, radius := grip_of(props, view_of(p))
	testing.expect(t, length(grip - Vec3{HOLD_RIGHT, -HOLD_DOWN, -HOLD_AHEAD}) < 1e-4)
	testing.expect_value(t, radius, kind_dims(.Beaker).radius)
}

@(test)
a_released_prop_falls_until_something_holds_it :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_add(props, l, .Bottle, 5, 5)
	props_add(props, l, .Beaker, 0, 0.35)
	props.items[0].pos.y = 1.5 // in the air above the floor
	props.items[1].pos.y = 1.8 // in the air above the island
	for _ in 0 ..< 120 {
		update(props, l, p, 1.0 / 60)
	}
	testing.expect_value(t, props.items[0].pos.y, 0)
	testing.expect_value(t, props.items[1].pos.y, lab.COUNTER_HEIGHT)
	testing.expect_value(t, props.items[0].vy, 0)
}

@(test)
the_hands_close_when_holding_and_open_again :: proc(t: ^testing.T) {
	h := new(Hands)
	defer free(h)
	for _ in 0 ..< 120 {
		hands_update(h, .Holding, 1.0 / 60)
	}
	testing.expect(t, h.curl[RIGHT] > 0.99 && h.lift[RIGHT] > 0.99)
	for _ in 0 ..< 120 {
		hands_update(h, .Idle, 1.0 / 60)
	}
	testing.expect(t, h.curl[RIGHT] < 0.2 && h.lift[RIGHT] < 0.01)
}

@(test)
every_hand_part_is_a_proper_box :: proc(t: ^testing.T) {
	h := new(Hands)
	defer free(h)
	p := new(lab.Player)
	defer free(p)
	p.yaw, p.pitch = 0.9, -0.4
	v := view_of(p)
	states := [?]State{.Idle, .Reaching, .Holding}
	for state in states {
		for _ in 0 ..< 120 {
			hands_update(h, state, 1.0 / 60)
		}
		placed: [MAX_HAND_PARTS]Placed
		n := hands_place(h, v, {HOLD_RIGHT, -HOLD_DOWN, -HOLD_AHEAD}, 0.05, &placed)
		testing.expect_value(t, n, 10)
		for i in 0 ..< n {
			a := placed[i].axes
			// A reflected box would be drawn inside out: the three edges must be right-handed.
			testing.expectf(t, dot(cross(a[0], a[1]), a[2]) > 0, "part %v is mirrored in state %v", i, state)
			offset := placed[i].origin - v.eye
			testing.expectf(t, length(offset) < 1.2, "part %v strays %v m from the eye", i, length(offset))
		}
	}
}

@(test)
an_unturned_part_follows_the_view :: proc(t: ^testing.T) {
	p := new(lab.Player)
	defer free(p)
	p.yaw, p.pitch = -0.6, 0.3
	v := view_of(p)
	placed := place_part({center = {0, 0, -1}, size = {1, 1, 1}, rot = Mat3(1)}, v)
	testing.expect(t, length(placed.axes[0] - v.right) < 1e-4)
	testing.expect(t, length(placed.axes[1] - v.up) < 1e-4)
	testing.expect(t, length(placed.axes[2] - v.back) < 1e-4)
	testing.expect(t, length(placed.origin - (v.eye - v.back)) < 1e-4) // one metre ahead
}

@(test)
a_turned_prop_keeps_a_right_handed_frame :: proc(t: ^testing.T) {
	for yaw := f32(-3); yaw < 3.2; yaw += 0.6 {
		pr := Prop{pos = {1, 2, 3}, yaw = yaw}
		placed := prop_placed(&pr)
		a := placed.axes
		testing.expect(t, dot(cross(a[0], a[1]), a[2]) > 0.999)
		testing.expect(t, placed.origin == Vec3{1, 2, 3})
	}
}

// Two vessels on the island: the first held, just over the second.
mix_setup :: proc(props: ^Props, l: ^lab.Layout, held, target: chem.Id, held_ml, target_ml: f32) {
	props_init(props)
	props_add(props, l, .Beaker, 0, 0.35, u16(held), held_ml)
	props_add(props, l, .Beaker, 0.02, 0.35, u16(target), target_ml)
	props.held = 0
	props.items[0].pos.y = lab.COUNTER_HEIGHT + kind_dims(.Beaker).height + 0.05
}

// An eye 0.8 m from the middle of the target, about where a player holding
// something over it would be.
mix_eye :: proc(props: ^Props) -> Vec3 {
	t := props.items[1]
	return {t.pos.x, t.pos.y + 0.07, t.pos.z + 0.8}
}

@(test)
the_vessel_under_the_held_one_is_the_target :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	mix_setup(props, l, .Water, .Slick, 200, 100)
	testing.expect_value(t, mix_target(props), 1)

	props.items[0].pos.x = 0.5 // off to the side
	testing.expect_value(t, mix_target(props), -1)
	props.items[0].pos.x = 0
	props.items[0].pos.y = lab.COUNTER_HEIGHT + 0.9 // far above
	testing.expect_value(t, mix_target(props), -1)
	props.items[0].pos.y = lab.COUNTER_HEIGHT - 0.3 // far below
	testing.expect_value(t, mix_target(props), -1)

	mix_setup(props, l, .Water, .Slick, 200, 100)
	props.items[0].ml = 0 // nothing to pour
	testing.expect_value(t, mix_target(props), -1)
	mix_setup(props, l, .Water, .Slick, 200, capacity_ml(.Beaker)) // nowhere to pour
	testing.expect_value(t, mix_target(props), -1)
	mix_setup(props, l, .Water, .Slick, 200, 100)
	props.held = -1
	testing.expect_value(t, mix_target(props), -1)
}

@(test)
pouring_into_an_empty_vessel_moves_the_liquid :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	mix_setup(props, l, .Dye_Red, .None, 300, 0)
	r := mix(props, mix_eye(props))
	testing.expect_value(t, r.kind, Mix_Kind.Poured)
	testing.expect_value(t, props.items[1].compound, u16(chem.Id.Dye_Red))
	testing.expect_value(t, props.items[1].ml, 300)
	testing.expect_value(t, props.items[0].ml, 0)
	testing.expect_value(t, props.items[0].compound, 0)
	testing.expect_value(t, r.damage, 0)
}

@(test)
two_of_the_same_liquid_just_add_up :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	mix_setup(props, l, .Water, .Water, 200, 300)
	r := mix(props, mix_eye(props))
	testing.expect_value(t, r.kind, Mix_Kind.Poured)
	testing.expect_value(t, props.items[1].ml, 500)
	testing.expect_value(t, props.items[1].compound, u16(chem.Id.Water))
}

@(test)
only_what_fits_is_poured_and_the_rest_stays :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	full := capacity_ml(.Beaker)
	mix_setup(props, l, .Dye_Red, .None, 300, 0)
	props_init(props)
	props_add(props, l, .Beaker, 0, 0.35, u16(chem.Id.Dye_Red), 300)
	props_add(props, l, .Beaker, 0.02, 0.35, u16(chem.Id.Dye_Red), full - 100)
	props.held = 0
	props.items[0].pos.y = lab.COUNTER_HEIGHT + 0.18
	mix(props, mix_eye(props))
	testing.expect(t, abs(props.items[1].ml - full) < 0.01)
	testing.expect(t, abs(props.items[0].ml - 200) < 0.01)
	testing.expect_value(t, props.items[0].compound, u16(chem.Id.Dye_Red))
}

@(test)
acid_and_base_make_foam_and_keep_all_the_liquid :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	mix_setup(props, l, .Fizz_Acid, .Soda_Base, 200, 300)
	r := mix(props, mix_eye(props))
	testing.expect_value(t, r.kind, Mix_Kind.Mixed)
	testing.expect_value(t, props.items[1].compound, u16(chem.Id.Neutral_Foam))
	testing.expect_value(t, props.items[1].ml, 500)
	testing.expect_value(t, r.damage, 0)
	testing.expect_value(t, props.count, 2)
}

@(test)
a_spatter_hurts_a_little_and_loses_some_liquid :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	mix_setup(props, l, .Spark_Blue, .Soda_Base, 200, 300)
	r := mix(props, mix_eye(props))
	testing.expect_value(t, r.kind, Mix_Kind.Spatter)
	testing.expect(t, abs(props.items[1].ml - 500 * (1 - chem.SPATTER_LOSS)) < 0.01)
	testing.expect_value(t, props.items[1].compound, u16(chem.Id.Acrid_Brew))
	testing.expect(t, r.damage > 0 && r.damage < 10)
	testing.expect_value(t, props.count, 2)
}

@(test)
a_blast_breaks_the_target_and_hurts :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	mix_setup(props, l, .Spark_Blue, .Ember_Oil, 200, 300)
	r := mix(props, mix_eye(props))
	testing.expect_value(t, r.kind, Mix_Kind.Blast)
	testing.expect_value(t, props.count, 1) // the target is gone
	testing.expect_value(t, props.held, 0) // and the held vessel is still in the hands
	testing.expect_value(t, props.items[0].ml, 0) // emptied by the pour
	testing.expect_value(t, r.product, u16(chem.Id.Char))
	testing.expectf(t, r.damage >= 60 && r.damage < 100, "the blast did %v", r.damage)
}

@(test)
the_held_vessel_is_still_held_when_a_vessel_before_it_breaks :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_init(props)
	props_add(props, l, .Beaker, 0.02, 0.35, u16(chem.Id.Ember_Oil), 300) // the target comes first
	props_add(props, l, .Beaker, 0, 0.35, u16(chem.Id.Spark_Blue), 200)
	props.held = 1
	props.items[1].pos.y = lab.COUNTER_HEIGHT + 0.18
	t0 := props.items[0].pos
	eye := Vec3{t0.x, t0.y + 0.07, t0.z + 0.8}
	r := mix(props, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Blast)
	testing.expect_value(t, props.count, 1)
	testing.expect_value(t, props.held, 0)
	testing.expect_value(t, props.items[0].compound, 0) // it is the emptied one
}

@(test)
nothing_happens_without_a_target :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_init(props)
	testing.expect_value(t, mix(props, {0, 1.6, 0}).kind, Mix_Kind.Nothing)
	props_add(props, l, .Beaker, 0, 0.35, u16(chem.Id.Water), 100)
	props.held = 0
	testing.expect_value(t, mix(props, {0, 1.6, 0}).kind, Mix_Kind.Nothing)
	testing.expect_value(t, props.items[0].ml, 100)
}

@(test)
removing_a_prop_keeps_the_other_indices_right :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	props_init(props)
	for x in 0 ..< 4 {
		props_add(props, l, .Beaker, f32(x) * 0.5, 0.35)
	}
	props.held, props.aimed = 3, 2
	props_remove(props, 1)
	testing.expect_value(t, props.count, 3)
	testing.expect_value(t, props.held, 2)
	testing.expect_value(t, props.aimed, 1)
	props_remove(props, 1) // the aimed one itself
	testing.expect_value(t, props.aimed, -1)
	testing.expect_value(t, props.held, 1)
	props_remove(props, 1) // the held one itself
	testing.expect_value(t, props.held, -1)
}

@(test)
health_drops_comes_back_and_ends_at_zero :: proc(t: ^testing.T) {
	h: Health
	health_init(&h)
	testing.expect_value(t, h.hp, HEALTH_MAX)
	health_hurt(&h, 30)
	testing.expect_value(t, h.hp, 70)
	testing.expect(t, h.flash >= 0.35)
	for _ in 0 ..< 60 { // a second: no recovery yet, but the flash fades
		health_update(&h, 1.0 / 60)
	}
	testing.expect_value(t, h.hp, 70)
	testing.expect(t, h.flash < 0.2)
	for _ in 0 ..< 60 * 10 { // then it comes back
		health_update(&h, 1.0 / 60)
	}
	testing.expect_value(t, h.hp, HEALTH_MAX)
	health_hurt(&h, 0)
	testing.expect_value(t, h.hp, HEALTH_MAX)
	testing.expect(t, !health_dead(&h))
	health_hurt(&h, 500)
	testing.expect_value(t, h.hp, 0)
	testing.expect(t, health_dead(&h))
	health_update(&h, 10) // the dead do not heal
	testing.expect_value(t, h.hp, 0)
}
