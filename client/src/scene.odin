// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene.odin"
// ============================================================================

package main

import rl "vendor:raylib"

// Every screen of the game is a scene, as in Unity: it loads its own
// resources, updates and draws each frame, and unloads when the game moves on.
Scene_Id :: enum {
	Balloon_Lab,
}

// Scripted pointer input for headless runs, so CI and screenshots can show the
// balloon held by its tip without anyone dragging it.
Demo_Mode :: enum {
	None,
	Hang, // lift the balloon by its tip and hold it
	Swing, // lift it, then sway it side to side
}

// State shared by every scene.
Game :: struct {
	screen_w:   i32,
	screen_h:   i32,
	fx:         HeatShader,
	target:     rl.RenderTexture2D, // scenes draw their 3D view here
	scene:      Scene_Id,
	state:      rawptr, // owned by the current scene
	next:       Scene_Id,
	switching:  bool,
	frame:      int,
	demo:       Demo_Mode,
}

// The five calls a scene answers. `draw` renders into game.target, which the
// heat-distortion pass then puts on screen, and `draw_ui` draws straight onto
// the screen after that, so text is never distorted.
Scene :: struct {
	load:    proc(game: ^Game) -> rawptr,
	update:  proc(game: ^Game, state: rawptr, dt: f32),
	draw:    proc(game: ^Game, state: rawptr),
	draw_ui: proc(game: ^Game, state: rawptr),
	unload:  proc(game: ^Game, state: rawptr),
}

scene_procs :: proc(id: Scene_Id) -> Scene {
	switch id {
	case .Balloon_Lab:
		return {load = lab_load, update = lab_update, draw = lab_draw, draw_ui = lab_draw_ui, unload = lab_unload}
	}
	return {}
}

// Starts a scene right away. Used for the first one.
game_enter :: proc(game: ^Game, id: Scene_Id) {
	game.scene = id
	game.state = scene_procs(id).load(game)
	game.switching = false
}

// Asks to move to another scene. It happens at the end of the frame, so a
// scene never unloads itself in the middle of its own update.
game_switch :: proc(game: ^Game, id: Scene_Id) {
	game.next = id
	game.switching = true
}

game_finish_switch :: proc(game: ^Game) {
	if !game.switching {
		return
	}
	scene_procs(game.scene).unload(game, game.state)
	game_enter(game, game.next)
}

game_leave :: proc(game: ^Game) {
	scene_procs(game.scene).unload(game, game.state)
	game.state = nil
}
