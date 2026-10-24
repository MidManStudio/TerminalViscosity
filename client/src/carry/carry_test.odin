// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "carry_test.odin"
// ============================================================================

package carry

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

expected_vertices :: proc(k: Kind) -> int {
	bands := 7
	if k == .Beaker {
		bands = 5
	}
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
		check_shape(t, s, "vessel")
		testing.expect_value(t, s.vert_count, expected_vertices(k))
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
		vessel_shape(s, k)
		d := kind_dims(k)
		for i in 0 ..< s.vert_count {
			p := s.positions[i]
			reach := math.sqrt(p.x * p.x + p.z * p.z)
			testing.expectf(t, reach <= d.radius + 1e-4 && p.y >= -1e-4 && p.y <= d.height + 1e-4, "%v vertex %v is outside its size", k, i)
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
	testing.expect_value(t, props.count, 7)
	for i in 0 ..< props.count {
		pr := props.items[i]
		testing.expect_value(t, pr.pos.y, lab.COUNTER_HEIGHT)
		testing.expect(t, abs(pr.pos.x) < 5 && abs(pr.pos.z) < 0.7)
	}
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
