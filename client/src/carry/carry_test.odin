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

// ---- tipped vessels ----

@(test)
a_disc_is_cut_by_a_line_at_the_right_area :: proc(t: ^testing.T) {
	r := f32(0.05)
	disc := math.PI * r * r
	testing.expect_value(t, area_below(r, -r), 0)
	testing.expect_value(t, area_below(r, r), disc)
	testing.expect(t, abs(area_below(r, 0) - disc * 0.5) < 1e-7)
	previous := f32(-1)
	for c := -r; c <= r; c += r / 10 {
		a := area_below(r, c)
		testing.expect(t, a >= previous)
		previous = a
	}
	testing.expect_value(t, area_below(0, 0), 0)
}

@(test)
tipped_vessel_geometry_agrees_with_the_upright_one :: proc(t: ^testing.T) {
	for k in Kind {
		sl := slices_of(k)
		for fraction in ([]f32{0.2, 0.5, 0.8}) {
			plane := VESSEL_WALL + (brim_height(k) - VESSEL_WALL) * fraction
			exact := interior_volume(k, plane)
			approx := volume_in_slices(&sl, 0, plane)
			testing.expectf(t, abs(approx - exact) < capacity_ml(k) * 0.03, "%v: %v ml against %v", k, approx, exact)
		}
		testing.expect_value(t, capacity_at_tilt(k, 0), capacity_ml(k))
		testing.expect_value(t, fill_level_tilted(k, 200, 0), fill_height(k, 200))
	}
}

@(test)
the_level_in_a_tipped_vessel_holds_the_same_liquid :: proc(t: ^testing.T) {
	for k in Kind {
		sl := slices_of(k)
		for tilt in ([]f32{0.3, 0.7, 1.1}) {
			ml := capacity_ml(k) * 0.3
			level := fill_level_tilted(k, ml, tilt)
			testing.expectf(t, abs(volume_in_slices(&sl, tilt, level) - ml) < 2, "%v at %v holds %v ml", k, tilt, volume_in_slices(&sl, tilt, level))
		}
	}
}

@(test)
a_vessel_holds_less_the_further_it_tips :: proc(t: ^testing.T) {
	for k in Kind {
		previous := capacity_ml(k) + 1
		for tilt := f32(0); tilt <= TILT_MAX; tilt += 0.1 {
			c := capacity_at_tilt(k, tilt)
			testing.expectf(t, c <= previous + 0.5, "%v holds more at %v than before", k, tilt)
			previous = c
		}
		testing.expectf(t, capacity_at_tilt(k, TILT_MAX) < 5, "%v still holds %v ml at full tilt", k, capacity_at_tilt(k, TILT_MAX))
	}
}

@(test)
the_lip_is_the_lowest_point_of_the_rim :: proc(t: ^testing.T) {
	d := Vec3{0, 0, -1}
	for k in Kind {
		up := lip_offset(k, 0, d)
		testing.expect(t, abs(up.y - brim_height(k)) < 1e-5)
		side := lip_offset(k, math.PI / 2, d)
		testing.expect(t, abs(side.y + mouth_radius(k)) < 1e-5)
		testing.expect(t, abs(side.z + brim_height(k)) < 1e-5)
	}
}

@(test)
a_tipped_prop_keeps_a_right_handed_frame :: proc(t: ^testing.T) {
	for yaw := f32(-3); yaw < 3.2; yaw += 0.7 {
		for tilt := f32(0); tilt <= TILT_MAX; tilt += 0.25 {
			a := prop_axes(yaw, tilt)
			testing.expect(t, dot(cross(a[0], a[1]), a[2]) > 0.999)
			testing.expect(t, abs(length(a[1]) - 1) < 1e-5)
		}
	}
}

// ---- pouring ----

PourScene :: struct {
	l:     ^lab.Layout,
	p:     ^lab.Player,
	props: ^Props,
	st:    ^Stream,
}

pour_scene :: proc() -> PourScene {
	l, p, props := make_scene()
	st := new(Stream)
	stream_init(st)
	return {l, p, props, st}
}

free_pour_scene :: proc(s: PourScene) {
	stream_destroy(s.st)
	free(s.st)
	free_scene(s.l, s.p, s.props)
}

// One frame of everything that happens while pouring: the player and vessels,
// the liquid leaving, the simulation, and the vessels taking what falls.
pour_frame :: proc(s: PourScene, events: ^[MAX_EVENTS]Mix_Result, found: ^[dynamic]Mix_Result) {
	dt := f32(1.0 / 60)
	update(s.props, s.l, s.p, dt)
	pour_flow(s.props, s.st, s.l, dt)
	stream_step(s.st, 21)
	n := stream_capture(s.st, s.props, view_of(s.p).eye, events)
	for i in 0 ..< n {
		append(found, events[i])
	}
}

// A vessel held in the hands, pouring, with another one under the crosshair.
pour_setup :: proc(s: PourScene, held, target: chem.Id, held_ml, target_ml: f32) {
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 0, 0.9, u16(held), held_ml)
	props_add(s.props, s.l, .Beaker, 0, 0.35, u16(target), target_ml)
	s.props.held = 0
	s.props.pouring = true
	look_at(s.p, {0, lab.COUNTER_HEIGHT + kind_dims(.Beaker).height * 0.5, 0.35})
}

@(test)
the_crosshair_picks_a_second_vessel_while_one_is_held :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	pour_setup(s, .Water, .None, 300, 0)
	s.props.pouring = false
	update(s.props, s.l, s.p, 1.0 / 60)
	testing.expect_value(t, s.props.aimed, 1)
	testing.expect_value(t, pour_target(s.props), 1)
	testing.expect(t, s.props.aimed_t < POUR_REACH)

	s.p.z = 3.0 // too far to pour into
	look_at(s.p, {0, lab.COUNTER_HEIGHT + 0.065, 0.35})
	update(s.props, s.l, s.p, 1.0 / 60)
	testing.expect_value(t, pour_target(s.props), -1)

	s.p.z = 1.2
	look_at(s.p, {0, lab.COUNTER_HEIGHT + 0.065, 0.35})
	s.props.items[1].ml = capacity_ml(.Beaker) // a full one cannot be poured into
	s.props.items[1].compound = u16(chem.Id.Water)
	update(s.props, s.l, s.p, 1.0 / 60)
	testing.expect_value(t, pour_target(s.props), -1)
}

@(test)
nothing_leaves_a_vessel_that_is_only_slightly_tipped :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	pour_setup(s, .Water, .None, 300, 0)
	events: [MAX_EVENTS]Mix_Result
	found: [dynamic]Mix_Result
	defer delete(found)
	for _ in 0 ..< 4 {
		pour_frame(s, &events, &found)
	}
	testing.expect(t, s.props.items[0].tilt > 0.05 && s.props.items[0].tilt < 0.5)
	testing.expect_value(t, s.props.items[0].ml, 300)
	testing.expect_value(t, s.st.sim.count, 0)
}

@(test)
the_stream_goes_into_the_vessel_under_the_crosshair :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	pour_setup(s, .Water, .None, 300, 0)
	events: [MAX_EVENTS]Mix_Result
	found: [dynamic]Mix_Result
	defer delete(found)
	for _ in 0 ..< 360 {
		pour_frame(s, &events, &found)
	}
	testing.expect_value(t, s.props.items[0].ml, 0) // poured out
	testing.expect_value(t, s.props.items[0].compound, 0)
	target := s.props.items[1]
	testing.expectf(t, target.ml > 240 && target.ml <= 300.5, "the target holds %v ml", target.ml)
	testing.expect_value(t, target.compound, u16(chem.Id.Water))
	testing.expect_value(t, len(found), 0) // water into nothing is no reaction
}

@(test)
a_calm_pour_reacts_once_for_the_whole_pour :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	pour_setup(s, .Fizz_Acid, .Soda_Base, 300, 200)
	events: [MAX_EVENTS]Mix_Result
	found: [dynamic]Mix_Result
	defer delete(found)
	for _ in 0 ..< 360 {
		pour_frame(s, &events, &found)
	}
	testing.expect_value(t, len(found), 1)
	if len(found) == 1 {
		testing.expect_value(t, found[0].kind, Mix_Kind.Mixed)
		testing.expect_value(t, found[0].product, u16(chem.Id.Neutral_Foam))
	}
	target := s.props.items[1]
	testing.expect_value(t, target.compound, u16(chem.Id.Neutral_Foam))
	testing.expectf(t, target.ml > 400, "the foam is %v ml", target.ml)
}

@(test)
pouring_the_oxidizer_into_the_oil_blasts_and_breaks_the_vessel :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	pour_setup(s, .Spark_Blue, .Ember_Oil, 300, 200)
	events: [MAX_EVENTS]Mix_Result
	found: [dynamic]Mix_Result
	defer delete(found)
	for _ in 0 ..< 360 {
		pour_frame(s, &events, &found)
	}
	testing.expect_value(t, len(found), 1)
	if len(found) == 1 {
		testing.expect_value(t, found[0].kind, Mix_Kind.Blast)
		testing.expectf(t, found[0].damage > 40 && found[0].damage < 100, "the blast did %v", found[0].damage)
	}
	testing.expect_value(t, s.props.count, 1) // the target broke
	testing.expect_value(t, s.props.session.target, -1)
}

@(test)
a_drop_joins_a_vessel_and_only_the_first_starts_a_reaction :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	eye := Vec3{0, 1.6, 1.2}
	props_init(props)
	props_add(props, l, .Beaker, 0, 0.35, u16(chem.Id.Fizz_Acid), 100)
	r := apply_droplet(props, 0, u16(chem.Id.Soda_Base), 3.375, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Mixed)
	testing.expect_value(t, props.items[0].compound, u16(chem.Id.Neutral_Foam))
	testing.expect_value(t, props.items[0].ml, 103.375)
	again := apply_droplet(props, 0, u16(chem.Id.Soda_Base), 3.375, eye)
	testing.expect_value(t, again.kind, Mix_Kind.Nothing)
	testing.expect_value(t, props.items[0].ml, 106.75)
	testing.expect_value(t, props.items[0].compound, u16(chem.Id.Neutral_Foam))
	props.session.timer = 0 // the pour is over, so the next drop is a new meeting
	later := apply_droplet(props, 0, u16(chem.Id.Soda_Base), 3.375, eye)
	testing.expect_value(t, later.kind, Mix_Kind.Mixed)
	testing.expect_value(t, later.a, u16(chem.Id.Neutral_Foam))
}

@(test)
a_drop_into_a_full_vessel_is_lost_and_a_spatter_loses_some_liquid :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	eye := Vec3{0, 1.6, 1.2}
	props_init(props)
	props_add(props, l, .Beaker, 0, 0.35, u16(chem.Id.Water), 1e6)
	testing.expect_value(t, apply_droplet(props, 0, u16(chem.Id.Ember_Oil), 3.375, eye).kind, Mix_Kind.Nothing)
	testing.expect_value(t, props.items[0].compound, u16(chem.Id.Water))

	props_init(props)
	props_add(props, l, .Beaker, 0, 0.35, u16(chem.Id.Soda_Base), 100)
	r := apply_droplet(props, 0, u16(chem.Id.Spark_Blue), 3.375, eye)
	testing.expect_value(t, r.kind, Mix_Kind.Spatter)
	testing.expect(t, abs(props.items[0].ml - 103.375 * (1 - chem.SPATTER_LOSS)) < 0.001)
	testing.expect(t, r.damage > 0 && r.damage < 10)
}

// ---- the bottle wall ----

@(test)
a_vessel_under_a_nozzle_is_found_only_when_it_is_in_the_right_place :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	st: Station
	station_init(&st)
	props_init(props)
	props_add(props, l, .Beaker, 11.5, 0.0, 0, 0)
	props.held = 0
	nozzle := lab.dispenser_nozzle(3)
	place :: proc(props: ^Props, x, y, z: f32) {
		props.items[0].pos = {x, y, z}
	}
	under := nozzle.y - 0.2 - kind_dims(.Beaker).height
	place(props, nozzle.x, under, nozzle.z)
	testing.expect_value(t, dispenser_under(&st, props), 3)
	place(props, nozzle.x, under, nozzle.z + 0.3)
	testing.expect_value(t, dispenser_under(&st, props), -1) // off to the side
	place(props, nozzle.x, nozzle.y + 0.1, nozzle.z)
	testing.expect_value(t, dispenser_under(&st, props), -1) // above the tip
	place(props, nozzle.x, nozzle.y - 1.0, nozzle.z)
	testing.expect_value(t, dispenser_under(&st, props), -1) // far below
	place(props, nozzle.x, under, nozzle.z)
	props.items[0].tilt = 0.8
	testing.expect_value(t, dispenser_under(&st, props), -1) // tipped over
	props.items[0].tilt = 0
	props.items[0].compound, props.items[0].ml = u16(chem.Id.Water), capacity_ml(.Beaker)
	testing.expect_value(t, dispenser_under(&st, props), -1) // already full
	props.items[0].compound, props.items[0].ml = 0, 0
	props.held = -1
	testing.expect_value(t, dispenser_under(&st, props), -1) // nothing held
}

@(test)
a_tap_fills_the_vessel_under_it_with_its_own_liquid :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	st: Station
	station_init(&st)
	props_init(s.props)
	props_add(s.props, s.l, .Beaker, 11.5, 0, 0, 0)
	s.props.held = 0
	nozzle := lab.dispenser_nozzle(2)
	s.props.items[0].pos = {nozzle.x, nozzle.y - 0.2 - kind_dims(.Beaker).height, nozzle.z}
	events: [MAX_EVENTS]Mix_Result
	for _ in 0 ..< 150 { // two and a half seconds
		station_flow(&st, s.st, s.l, 2, 1.0 / 60)
		stream_step(s.st, 21)
		stream_capture(s.st, s.props, {0, 1.6, 0}, &events)
	}
	v := s.props.items[0]
	testing.expect_value(t, v.compound, u16(chem.Id.Soda_Base)) // the third tap
	testing.expectf(t, v.ml > 200 && v.ml < 300, "the vessel holds %v ml", v.ml)
}

@(test)
a_locked_tap_gives_nothing :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	st: Station
	station_init(&st)
	st.items[4].unlocked = false
	for _ in 0 ..< 30 {
		testing.expect(t, !station_flow(&st, s.st, s.l, 4, 1.0 / 60))
	}
	testing.expect_value(t, s.st.sim.count, 0)
	testing.expect(t, station_flow(&st, s.st, s.l, 5, 1.0 / 60))
}

@(test)
the_bottles_are_the_color_of_their_liquid :: proc(t: ^testing.T) {
	colors := station_colors()
	for i in 0 ..< lab.DISPENSER_COUNT {
		c := chem.compound_color(u16(i + 1))
		testing.expect(t, abs(f32(colors[i].r) / 255 - c.r) < 0.01)
		testing.expect(t, abs(f32(colors[i].b) / 255 - c.b) < 0.01)
	}
}

// ---- the stream of drops ----

@(test)
a_drop_lands_wipes_away_and_the_box_sits_on_the_surface_under_it :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	testing.expect(t, stream_spawn(s.st, s.l, {0, 1.4, 0}, {0, 0, 0}, u16(chem.Id.Water)))
	testing.expect(t, abs(s.st.origin.y - (lab.COUNTER_HEIGHT - 2.9 * STREAM_DX)) < 1e-4)
	testing.expect(t, !s.st.air_floor)
	for _ in 0 ..< 600 {
		stream_step(s.st, 21)
	}
	testing.expect_value(t, s.st.sim.count, 0)
}

@(test)
a_drop_outside_the_box_or_in_a_full_stream_is_refused :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	testing.expect(t, stream_spawn(s.st, s.l, {0, 1.4, 0}, {}, 1))
	testing.expect(t, !stream_spawn(s.st, s.l, {5, 1.4, 0}, {}, 1)) // far from the box
	testing.expect(t, !stream_spawn(s.st, s.l, {0, 0.2, 0}, {}, 1)) // below its floor
	for i in 1 ..< MAX_STREAM {
		testing.expect(t, stream_spawn(s.st, s.l, {f32(i % 7) * 0.05 - 0.15, 1.4 + f32(i / 7) * 0.04, 0}, {}, 1))
	}
	testing.expect(t, !stream_spawn(s.st, s.l, {0, 1.4, 0.2}, {}, 1))
}

@(test)
a_pour_from_high_over_the_floor_has_its_box_in_the_air_and_drops_fall_out :: proc(t: ^testing.T) {
	s := pour_scene()
	defer free_pour_scene(s)
	testing.expect(t, stream_spawn(s.st, s.l, {-8, 2.2, 3}, {0, 0, 0}, 1))
	testing.expect(t, s.st.air_floor)
	for _ in 0 ..< 300 {
		stream_step(s.st, 21)
	}
	testing.expect_value(t, s.st.sim.count, 0)
}
