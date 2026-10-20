// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mdix_dyn.odin"
// ============================================================================

// Package store is the game's local database: it reads and writes DixScript
// data through DixScript's C library. It has no raylib dependency, so it is
// tested without a window.
package store

import "core:dynlib"
import "core:fmt"
import "core:strings"

// The DixScript C functions the game calls. They are found by name when the
// library is opened, so a missing or wrong library is a message on screen and
// not a crash at start-up.
Mdix :: struct {
	library:            dynlib.Library,
	loaded:             bool,
	error:              [200]u8,
	error_len:          int,
	version:            proc "c" () -> cstring,
	last_error:         proc "c" () -> cstring,
	load_str:           proc "c" (source: cstring) -> rawptr,
	free_db:            proc "c" (db: rawptr),
	exists:             proc "c" (db: rawptr, path: cstring) -> bool,
	get_int:            proc "c" (db: rawptr, path: cstring) -> i32,
	get_string:         proc "c" (db: rawptr, path: cstring) -> cstring,
	free_string:        proc "c" (text: cstring),
	builder_new:        proc "c" () -> rawptr,
	builder_free:       proc "c" (builder: rawptr),
	builder_set_int:    proc "c" (builder: rawptr, path: cstring, value: i32) -> bool,
	builder_set_string: proc "c" (builder: rawptr, path: cstring, value: cstring) -> bool,
	builder_to_string:  proc "c" (builder: rawptr) -> cstring,
}

Symbol :: struct {
	name: string,
	slot: ^rawptr,
}

// Loads the library at `path` and looks up every function above. On failure it
// returns false and mdix_error says why, including the loader's own message.
mdix_open :: proc(m: ^Mdix, path: string) -> bool {
	m^ = {}
	library, ok := dynlib.load_library(path, false, context.allocator)
	if !ok {
		mdix_fail(m, "cannot load %s: %s", path, dynlib.last_error())
		return false
	}
	m.library = library
	symbols := [?]Symbol {
		{"mdix_version", cast(^rawptr)&m.version},
		{"mdix_get_last_error", cast(^rawptr)&m.last_error},
		{"mdix_load_str", cast(^rawptr)&m.load_str},
		{"mdix_free", cast(^rawptr)&m.free_db},
		{"mdix_exists", cast(^rawptr)&m.exists},
		{"mdix_get_int", cast(^rawptr)&m.get_int},
		{"mdix_get_string", cast(^rawptr)&m.get_string},
		{"mdix_free_string", cast(^rawptr)&m.free_string},
		{"mdix_builder_new", cast(^rawptr)&m.builder_new},
		{"mdix_builder_free", cast(^rawptr)&m.builder_free},
		{"mdix_builder_set_int", cast(^rawptr)&m.builder_set_int},
		{"mdix_builder_set_string", cast(^rawptr)&m.builder_set_string},
		{"mdix_builder_to_string", cast(^rawptr)&m.builder_to_string},
	}
	for symbol in symbols {
		address, found := dynlib.symbol_address(library, symbol.name, context.allocator)
		if !found {
			mdix_fail(m, "%s has no function %s", path, symbol.name)
			return false
		}
		symbol.slot^ = address
	}
	m.loaded = true
	return true
}

mdix_fail :: proc(m: ^Mdix, format: string, args: ..any) {
	text := fmt.bprintf(m.error[:], format, ..args)
	m.error_len = len(text)
}

// Why the last open or call failed.
mdix_error :: proc(m: ^Mdix) -> string {
	return string(m.error[:m.error_len])
}

// The library's own message for its most recent failure.
mdix_library_error :: proc(m: ^Mdix) -> string {
	message := m.last_error()
	if message == nil {
		return "no message"
	}
	return string(message)
}

// Reads an integer, or reports that the key is missing.
db_get_int :: proc(m: ^Mdix, db: rawptr, path: cstring) -> (value: int, ok: bool) {
	if !m.exists(db, path) {
		return 0, false
	}
	return int(m.get_int(db, path)), true
}

// Reads a string into memory owned by the caller, or reports that the key is missing.
db_get_string :: proc(m: ^Mdix, db: rawptr, path: cstring, allocator := context.allocator) -> (value: string, ok: bool) {
	if !m.exists(db, path) {
		return "", false
	}
	text := m.get_string(db, path)
	if text == nil {
		return "", false
	}
	value = strings.clone(string(text), allocator)
	m.free_string(text)
	return value, true
}
