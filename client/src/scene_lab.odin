// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene_lab.odin"
// ============================================================================

package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import bl "balloon"

PHYSICS_DT :: f32(1.0 / 60.0)
// A slow frame runs at most this many physics steps, then drops the rest of
// the time, so a slow phone gets slow motion instead of a spiral of ever longer frames.
MAX_TICKS_PER_FRAME :: 3
FLOOR_Y :: f32(0)
ROOM_HALF :: f32(7)
DROP_HEIGHT :: f32(2.6)
HOLD_HEIGHT :: f32(4.4)
LIQUID_TINT :: Vec3{0.25, 0.62, 1.0}
LIGHT_DIR :: Vec3{0.35, 0.80, 0.48} // toward the light, roughly unit length
BACKGROUND :: rl.Color{18, 22, 30, 255}
FLOOR_COLOR :: rl.Color{30, 36, 48, 255}
// Start of the scripted demo, in frames.
DEMO_GRAB_FRAME :: 90
DEMO_LIFT_FRAMES :: 45
DEMO_SWING_FRAME :: 170

// The crafting lab: a 3D water balloon you can grab and drag. Dragging the
// tip lifts the balloon by it and it hangs as a teardrop. Dragging empty space
// turns the camera.
Lab :: struct {
	balloon:     bl.Balloon,
	view:        Balloon_View,
	cam:         Camera_Rig,
	accumulator: f32,
	holding:     bool,
	hold_vertex: int,
	hold_depth:  f32, // distance along the view direction that the held vertex is dragged at
	orbiting:    bool,
	last_pointer: [2]f32,
	hold_target: Vec3,
	demo_origin: Vec3, // where the tip was when the demo grabbed it
	sim_ms:      f32, // smoothed time one frame spends in the physics
}

lab_load :: proc(game: ^Game) -> rawptr {
	lab := new(Lab)
	bl.init(&lab.balloon, bl.default_config())
	lab.balloon.floor_y = FLOOR_Y
	lab.balloon.half_extent = ROOM_HALF
	bl.reset(&lab.balloon, {0, DROP_HEIGHT, 0})
	shader, ok := load_balloon_shader()
	view_init(&lab.view, &lab.balloon, shader, ok)
	lab.cam = camera_default()
	// Tighter clip planes than raylib's default give the depth buffer far
	// more precision, which matters on a phone with a 16-bit one.
	rlgl.SetClipPlanes(0.5, 80)
	return lab
}

lab_unload :: proc(game: ^Game, state: rawptr) {
	lab := cast(^Lab)state
	rlgl.SetClipPlanes(0.05, 4000)
	view_unload(&lab.view)
	free(lab)
}

lab_update :: proc(game: ^Game, state: rawptr, dt: f32) {
	lab := cast(^Lab)state
	w, h := f32(game.screen_w), f32(game.screen_h)
	frame := camera_frame(&lab.cam, w, h)

	if game.demo != .None {
		lab_demo(lab, game)
	} else {
		lab_input(lab, &frame, w, h)
	}
	if lab.holding {
		bl.pin(&lab.balloon, lab.hold_vertex, lab.hold_target)
	} else {
		bl.unpin(&lab.balloon)
	}

	t0 := rl.GetTime()
	lab.accumulator += dt
	ticks := 0
	for lab.accumulator >= PHYSICS_DT && ticks < MAX_TICKS_PER_FRAME {
		bl.step(&lab.balloon, PHYSICS_DT)
		lab.accumulator -= PHYSICS_DT
		ticks += 1
	}
	if ticks == MAX_TICKS_PER_FRAME {
		lab.accumulator = 0
	}
	bl.update_normals(&lab.balloon)
	view_update(&lab.view, &lab.balloon)
	spent := f32(rl.GetTime() - t0) * 1000
	lab.sim_ms += (spent - lab.sim_ms) * 0.1
}

// Pointer handling: press on the balloon to grab it, press elsewhere to turn
// the camera. A single pointer is enough, so it works the same with a finger.
lab_input :: proc(lab: ^Lab, frame: ^Camera_Frame, w, h: f32) {
	pointer := platform_mouse_position()
	if rl.IsMouseButtonPressed(.LEFT) {
		lab.last_pointer = pointer
		if vertex := lab_pick(lab, frame, pointer); vertex >= 0 {
			lab.holding = true
			lab.hold_vertex = vertex
			lab.hold_depth = bl.dot3(lab.balloon.pos[vertex] - frame.eye, frame.forward)
		} else {
			lab.orbiting = true
		}
	}
	if !rl.IsMouseButtonDown(.LEFT) {
		lab.holding = false
		lab.orbiting = false
	}
	if lab.holding {
		dir := frame_ray(frame, pointer.x, pointer.y)
		reach := lab.hold_depth / bl.dot3(dir, frame.forward)
		target := frame.eye + dir * reach
		// Keep the hand above the floor and inside the room.
		target.x = clamp(target.x, -ROOM_HALF, ROOM_HALF)
		target.z = clamp(target.z, -ROOM_HALF, ROOM_HALF)
		target.y = clamp(target.y, FLOOR_Y + 0.2, 9)
		lab.hold_target = target
	}
	if lab.orbiting {
		camera_orbit(&lab.cam, pointer.x - lab.last_pointer.x, pointer.y - lab.last_pointer.y)
		lab.last_pointer = pointer
	}
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		camera_zoom(&lab.cam, wheel)
	}
}

// The vertex under a pointer: the nearest one on the screen that faces the
// camera, within a finger's width. The tip counts as twice as close, so it is
// easy to catch even though it is small.
lab_pick :: proc(lab: ^Lab, frame: ^Camera_Frame, pointer: [2]f32) -> int {
	reach := max(48, frame.h * 0.075)
	best := -1
	best_d := reach
	b := &lab.balloon
	for i in 0 ..< b.vert_count {
		if i != bl.TIP && bl.dot3(b.normal[i], frame.eye - b.pos[i]) <= 0 {
			continue
		}
		x, y, ok := frame_project(frame, b.pos[i])
		if !ok {
			continue
		}
		d := math.sqrt((x - pointer.x) * (x - pointer.x) + (y - pointer.y) * (y - pointer.y))
		if i == bl.TIP {
			d *= 0.5
		}
		if d < best_d {
			best = i
			best_d = d
		}
	}
	return best
}

// Scripted input: grab the tip, lift it to the hold height, and optionally sway.
lab_demo :: proc(lab: ^Lab, game: ^Game) {
	if game.frame < DEMO_GRAB_FRAME {
		return
	}
	if !lab.holding {
		lab.holding = true
		lab.hold_vertex = bl.TIP
		lab.demo_origin = lab.balloon.pos[bl.TIP]
	}
	t := clamp(f32(game.frame - DEMO_GRAB_FRAME) / DEMO_LIFT_FRAMES, 0, 1)
	s := t * t * (3 - 2 * t)
	lab.hold_target = lab.demo_origin + (Vec3{0, HOLD_HEIGHT, 0} - lab.demo_origin) * s
	if game.demo == .Swing && game.frame > DEMO_SWING_FRAME {
		lab.hold_target.x = 2.2 * math.sin(f32(game.frame - DEMO_SWING_FRAME) * 0.07)
	}
}

lab_draw :: proc(game: ^Game, state: rawptr) {
	lab := cast(^Lab)state
	rl.ClearBackground(BACKGROUND)
	rl.BeginMode3D(camera_to_raylib(&lab.cam))
	draw_floor()
	draw_blob_shadow(&lab.balloon)
	view_draw(&lab.view, camera_eye(&lab.cam), bl.normalize3(LIGHT_DIR), LIQUID_TINT)
	rl.EndMode3D()
}

lab_draw_ui :: proc(game: ^Game, state: rawptr) {
	lab := cast(^Lab)state
	size := max(i32(18), game.screen_h / 32)
	rl.DrawText("drag the tip to lift the balloon, drag the background to look around", 20, 20, size, rl.RAYWHITE)
	rl.DrawFPS(20, 20 + size + 8)
	buf: [48]u8
	text := fmt.bprintf(buf[:47], "physics %.2f ms", lab.sim_ms)
	buf[len(text)] = 0
	rl.DrawText(cstring(&buf[0]), 20, 20 + 2 * size + 16, size, {120, 200, 255, 255})
}

// A large floor with a faint grid so depth and height are easy to read. The
// floor sits just under y = 0, where the balloon rests.
draw_floor :: proc() {
	// Plain rlgl vertices rather than rl.DrawPlane, which takes structs of floats by value.
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(FLOOR_COLOR.r, FLOOR_COLOR.g, FLOOR_COLOR.b, FLOOR_COLOR.a)
	rlgl.Vertex3f(-80, -0.02, -80)
	rlgl.Vertex3f(-80, -0.02, 80)
	rlgl.Vertex3f(80, -0.02, 80)
	rlgl.Vertex3f(80, -0.02, -80)
	rlgl.End()
	rlgl.EnableBackfaceCulling()
	rlgl.Begin(rlgl.LINES)
	rlgl.Color4ub(48, 58, 78, 255)
	for i in -24 ..= 24 {
		x := f32(i)
		rlgl.Vertex3f(x, -0.015, -24)
		rlgl.Vertex3f(x, -0.015, 24)
		rlgl.Vertex3f(-24, -0.015, x)
		rlgl.Vertex3f(24, -0.015, x)
	}
	rlgl.End()
}

// A soft dark disc under the balloon. It grows and fades as the balloon rises.
// It is drawn without depth testing, right after the floor, so it can sit
// exactly on the floor without flickering against it.
draw_blob_shadow :: proc(b: ^bl.Balloon) {
	rlgl.DrawRenderBatchActive()
	lo, hi := bl.bounds(b)
	c := bl.center(b)
	height := max(lo.y - FLOOR_Y, 0)
	radius := max(hi.x - lo.x, hi.z - lo.z) * 0.5 * (1.1 + height * 0.12)
	alpha := 150 / (1 + height * 0.9)
	rlgl.DisableDepthTest()
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)
	segments := 28
	for i in 0 ..< segments {
		a0 := f32(i) / f32(segments) * math.TAU
		a1 := f32(i + 1) / f32(segments) * math.TAU
		rlgl.Color4ub(0, 0, 0, u8(alpha))
		rlgl.Vertex3f(c.x, -0.01, c.z)
		rlgl.Color4ub(0, 0, 0, 0)
		rlgl.Vertex3f(c.x + math.cos(a0) * radius, -0.01, c.z + math.sin(a0) * radius)
		rlgl.Vertex3f(c.x + math.cos(a1) * radius, -0.01, c.z + math.sin(a1) * radius)
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthTest()
}
