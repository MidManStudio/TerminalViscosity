// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "android_entry.odin"
// ============================================================================

#+build linux:android
package main

import "base:runtime"
import rl "vendor:raylib"

// On Android, raylib's own `android_main` calls a C function named `main`.
// android/entry.c provides that `main` and calls this procedure. The Odin
// runtime's start-up is not run in this build mode, so the context is built
// by hand and nothing here may rely on package-level initializers or os.args.
@(export, link_name = "tv_odin_main")
tv_odin_main :: proc "c" () {
	context = runtime.default_context()
	main()
}

// The shim lives in android/entry.c and is resolved by the final link. Odin's
// 32-bit ARM backend returns an 8-byte struct of floats in registers while the
// NDK's ABI returns it through a hidden pointer, so raylib's GetMousePosition
// must be called from C. Pointers are passed instead.
foreign import shim "system:c"

@(default_calling_convention = "c")
foreign shim {
	tv_android_mouse_position :: proc(out_x, out_y: ^f32) ---
	tv_android_touch_position :: proc(index: i32, out_x, out_y: ^f32) ---
}

platform_mouse_position :: proc() -> [2]f32 {
	x, y: f32
	tv_android_mouse_position(&x, &y)
	return {x, y}
}

// Every finger on the screen. The count and the ids are plain integers, so
// raylib is called directly for them. The id stays the same for as long as a
// finger is down, while its index changes when another finger lifts.
platform_pointers :: proc(out: ^Pointers) {
	out.count = 0
	count := min(int(rl.GetTouchPointCount()), MAX_POINTERS)
	for i in 0 ..< count {
		x, y: f32
		tv_android_touch_position(i32(i), &x, &y)
		out.items[out.count] = {id = int(rl.GetTouchPointId(i32(i))), pos = {x, y}}
		out.count += 1
	}
}
