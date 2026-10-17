// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "main.odin"
// ============================================================================

package main

import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// Desktop window size. Android ignores it and uses the full screen.
WINDOW_W :: 1280
WINDOW_H :: 720

Options :: struct {
	max_frames: int, // 0 means run until the window closes
	screenshot: string,
	width:      i32,
	height:     i32,
	fixed_step: bool, // every frame advances the game by exactly 1/60 s
	demo:       Demo_Mode,
}

main :: proc() {
	opts := Options {
		width  = WINDOW_W,
		height = WINDOW_H,
	}
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
				opts.max_frames, _ = strconv.parse_int(args[i])
			}
		case "--screenshot":
			if i + 1 < len(args) {
				i += 1
				opts.screenshot = args[i]
			}
		case "--size":
			// Window size as WIDTHxHEIGHT, handy for trying a phone's wide screen on a desktop.
			if i + 1 < len(args) {
				i += 1
				parts := strings.split(args[i], "x", context.temp_allocator)
				if len(parts) == 2 {
					w, _ := strconv.parse_int(parts[0])
					h, _ := strconv.parse_int(parts[1])
					if w > 0 && h > 0 {
						opts.width, opts.height = i32(w), i32(h)
					}
				}
			}
		case "--fixed-step":
			opts.fixed_step = true
		case "--demo":
			if i + 1 < len(args) {
				i += 1
				switch args[i] {
				case "hang":
					opts.demo = .Hang
				case "swing":
					opts.demo = .Swing
				}
			}
		}
	}
	run(opts)
}

// Opens the window and runs the scenes. With max_frames > 0 it exits after
// that many frames, saving a screenshot first when a path is given. CI uses
// this to prove rendering works.
run :: proc(opts: Options) {
	when ODIN_PLATFORM_SUBTARGET != .Android {
		rl.SetConfigFlags({.MSAA_4X_HINT})
	}
	rl.InitWindow(opts.width, opts.height, "Terminal Viscosity")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// Lay everything out from the real screen size, so the same code fits a
	// desktop window and a phone screen.
	game := Game {
		screen_w = rl.GetScreenWidth(),
		screen_h = rl.GetScreenHeight(),
		demo     = opts.demo,
	}
	game.fx = load_heat_shader()
	defer unload_heat_shader(&game.fx)
	game.target = rl.LoadRenderTexture(game.screen_w, game.screen_h)
	defer rl.UnloadRenderTexture(game.target)

	game_enter(&game, .Balloon_Lab)
	defer game_leave(&game)

	for !rl.WindowShouldClose() {
		dt := PHYSICS_DT if opts.fixed_step else min(rl.GetFrameTime(), 0.1)
		scene := scene_procs(game.scene)
		scene.update(&game, game.state, dt)

		rl.BeginTextureMode(game.target)
		scene.draw(&game, game.state)
		rl.EndTextureMode()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		draw_scene(&game.fx, game.target)
		scene.draw_ui(&game, game.state)
		rl.EndDrawing()

		game.frame += 1
		game_finish_switch(&game)
		if opts.max_frames > 0 && game.frame >= opts.max_frames {
			if opts.screenshot != "" {
				path := strings.clone_to_cstring(opts.screenshot)
				defer delete(path)
				rl.TakeScreenshot(path)
			}
			break
		}
	}
}
