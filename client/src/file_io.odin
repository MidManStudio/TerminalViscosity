// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "file_io.odin"
// ============================================================================

package main

import "base:runtime"
import "core:strings"
import rl "vendor:raylib"
import "store"

// Named files through raylib. On Android raylib writes a name into the app's
// private storage and reads it back from there, after looking in the APK's
// assets first. On a desktop the name is relative to the working directory.

raylib_read :: proc(data: rawptr, name: string, allocator: runtime.Allocator) -> (text: string, ok: bool) {
	cname := strings.clone_to_cstring(name, context.allocator)
	defer delete(cname)
	loaded := rl.LoadFileText(cname)
	if loaded == nil {
		return "", false
	}
	defer rl.UnloadFileText(loaded)
	return strings.clone(string(cstring(loaded)), allocator), true
}

raylib_write :: proc(data: rawptr, name: string, text: string) -> bool {
	cname := strings.clone_to_cstring(name, context.allocator)
	defer delete(cname)
	ctext := strings.clone_to_cstring(text, context.allocator)
	defer delete(ctext)
	return rl.SaveFileText(cname, cast([^]byte)ctext)
}

raylib_files :: proc() -> store.File_IO {
	return {read = raylib_read, write = raylib_write}
}

// Where the DixScript library is. On Android it is loaded by name, from the
// folder of native libraries that the APK installs. On a desktop it sits next to the executable.
mdix_library_path :: proc() -> string {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		return "libmdix_ffi.so"
	} else when ODIN_OS == .Windows {
		return strings.concatenate({string(rl.GetApplicationDirectory()), "mdix_ffi.dll"}, context.temp_allocator)
	} else when ODIN_OS == .Darwin {
		return strings.concatenate({string(rl.GetApplicationDirectory()), "libmdix_ffi.dylib"}, context.temp_allocator)
	} else {
		return strings.concatenate({string(rl.GetApplicationDirectory()), "libmdix_ffi.so"}, context.temp_allocator)
	}
}
