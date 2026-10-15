// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "main.odin"
// ============================================================================

package main

import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import "softbody"

// Desktop window size. Android ignores it and uses the full screen.
WINDOW_W :: 1280
WINDOW_H :: 720
GRAB_RADIUS :: 40.0
PHYSICS_DT :: f32(1.0 / 120.0) // soft-body runs at twice the sim tick for stability

main :: proc() {
	max_frames := 0 // 0 means run until the window closes
	screenshot := ""
	args: []string
	if len(os.args) > 1 {
		args = os.args[1:]
	}
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "--selftest":
			os.exit(selftest())
		case "--frames":
			if i + 1 < len(args) {
				i += 1
				max_frames, _ = strconv.parse_int(args[i])
			}
		case "--screenshot":
			if i + 1 < len(args) {
				i += 1
				screenshot = args[i]
			}
		}
	}
	run_lab(max_frames, screenshot)
}

// Crafting-lab prototype: a jiggling balloon you can grab and drag with the mouse.
// With max_frames > 0 it exits after that many frames, saving a screenshot to
// `screenshot` first when a path is given. CI uses this to prove rendering works.
run_lab :: proc(max_frames: int, screenshot: string) {
	when ODIN_PLATFORM_SUBTARGET != .Android {
		rl.SetConfigFlags({.MSAA_4X_HINT})
	}
	rl.InitWindow(WINDOW_W, WINDOW_H, "Terminal Viscosity")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// Lay everything out from the real screen size, so the same code fits a
	// 1280 by 720 desktop window and a phone screen.
	screen_w := rl.GetScreenWidth()
	screen_h := rl.GetScreenHeight()

	fx := load_heat_shader()
	defer unload_heat_shader(&fx)
	scene := rl.LoadRenderTexture(screen_w, screen_h)
	defer rl.UnloadRenderTexture(scene)

	ring: softbody.Ring
	softbody.ring_init(
		&ring,
		{f32(screen_w) / 2, f32(screen_h) * 0.3},
		f32(min(screen_w, screen_h)) * 0.153,
		32,
	)
	ring.floor_y = f32(screen_h) * 0.889

	grab := -1
	accumulator: f32
	frame_count := 0

	for !rl.WindowShouldClose() {
		frame := min(rl.GetFrameTime(), 0.1)
		mouse_v := softbody.Vec2(platform_mouse_position())

		if rl.IsMouseButtonPressed(.LEFT) {
			grab = softbody.ring_nearest(&ring, mouse_v, GRAB_RADIUS)
		}
		if rl.IsMouseButtonReleased(.LEFT) {
			grab = -1
		}

		accumulator += frame
		for accumulator >= PHYSICS_DT {
			softbody.ring_step(&ring, PHYSICS_DT, grab, mouse_v)
			accumulator -= PHYSICS_DT
		}

		rl.BeginTextureMode(scene)
		rl.ClearBackground({18, 22, 30, 255})
		draw_floor(ring.floor_y, screen_w, screen_h)
		draw_balloon(&ring)
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_scene(&fx, scene)
		rl.DrawText("drag the balloon with the mouse", 20, 20, 20, rl.RAYWHITE)
		rl.DrawFPS(20, 48)
		rl.EndDrawing()

		frame_count += 1
		if max_frames > 0 && frame_count >= max_frames {
			if screenshot != "" {
				path := strings.clone_to_cstring(screenshot)
				defer delete(path)
				rl.TakeScreenshot(path)
			}
			break
		}
	}
}

draw_floor :: proc(y: f32, screen_w, screen_h: i32) {
	rl.DrawRectangle(0, i32(y), screen_w, screen_h - i32(y), {30, 36, 48, 255})
	rl.DrawLine(0, i32(y), screen_w, i32(y), {80, 90, 110, 255})
}

// Fills the ring as a triangle fan, then outlines it. raylib culls clockwise
// triangles, and the ring runs clockwise on screen, so each triangle lists the
// next node before the current one.
draw_balloon :: proc(ring: ^softbody.Ring) {
	c := softbody.ring_center(ring)
	center := rl.Vector2{c.x, c.y}
	fill := rl.Color{120, 200, 255, 200}
	for i in 0 ..< ring.count {
		a := ring.pos[i]
		b := ring.pos[(i + 1) % ring.count]
		rl.DrawTriangle(center, {b.x, b.y}, {a.x, a.y}, fill)
	}
	for i in 0 ..< ring.count {
		a := ring.pos[i]
		b := ring.pos[(i + 1) % ring.count]
		rl.DrawLineEx({a.x, a.y}, {b.x, b.y}, 3, rl.WHITE)
	}
}
