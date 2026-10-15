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
