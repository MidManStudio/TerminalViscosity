// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "platform_desktop.odin"
// ============================================================================

#+build !linux:android
package main

import rl "vendor:raylib"

// Desktop counterpart of the Android wrapper in android_entry.odin. On desktop
// raylib can be called directly.
platform_mouse_position :: proc() -> [2]f32 {
	p := rl.GetMousePosition()
	return {p.x, p.y}
}

// The mouse is one pointer while its left button is down.
platform_pointers :: proc(out: ^Pointers) {
	out.count = 0
	if rl.IsMouseButtonDown(.LEFT) {
		p := rl.GetMousePosition()
		out.items[0] = {id = 0, pos = {p.x, p.y}}
		out.count = 1
	}
}
