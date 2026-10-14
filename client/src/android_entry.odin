// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "android_entry.odin"
// ============================================================================

#+build linux:android
package main

import "base:runtime"

// On Android, raylib's own `android_main` calls a C function named `main`.
// android/entry.c provides that `main` and calls this procedure. The Odin
// runtime's start-up is not run in this build mode, so the context is built
// by hand and nothing here may rely on package-level initializers or os.args.
@(export, link_name = "tv_odin_main")
tv_odin_main :: proc "c" () {
	context = runtime.default_context()
	main()
}
