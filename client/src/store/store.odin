// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "store.odin"
// ============================================================================

package store

import "base:runtime"
import "core:fmt"
import "core:strings"

// Where the local profile lives, and the file that records how far the last
// self-check got.
PROFILE_FILE :: "tv_profile.mdix"
STEP_FILE :: "tv_mdix_step.txt"

// A small DixScript document the self-check parses to prove the parser works.
SELF_TEST_SOURCE :: cstring(`@DATA( port = 8080, host = "localhost", ssl = true )`)

// How the store reads and writes named files. The game passes raylib's file
// functions, which know where an Android app may write. Tests pass memory.
File_IO :: struct {
	data:  rawptr,
	read:  proc(data: rawptr, name: string, allocator: runtime.Allocator) -> (text: string, ok: bool),
	write: proc(data: rawptr, name: string, text: string) -> bool,
}

Status :: enum {
	Not_Run,
	Ok,
	Skipped, // the last launch stopped inside the library, so it is not called this time
	Failed,
}

// The result of the start-up self-check, in words that fit on one line of the screen.
Check :: struct {
	status:   Status,
	launches: int, // how many times the game has started, from the profile file
	text:     [220]u8,
	text_len: int,
}

Store :: struct {
	mdix:  Mdix,
	check: Check,
}

check_text :: proc(c: ^Check) -> string {
	return string(c.text[:c.text_len])
}

check_say :: proc(c: ^Check, format: string, args: ..any) {
	text := fmt.bprintf(c.text[:], format, ..args)
	c.text_len = len(text)
}

// Writes down which step is about to run. If the library takes the whole app
// down, this file is how the next launch learns where.
crumb :: proc(io: File_IO, step: string) {
	io.write(io.data, STEP_FILE, step)
}

check_fail :: proc(s: ^Store, io: File_IO, format: string, args: ..any) {
	s.check.status = .Failed
	check_say(&s.check, format, ..args)
	crumb(io, "retry")
}

// Loads the DixScript library and proves it works inside the running game: it
// parses a document, reads values from it, builds a profile, saves it, reads
// it back, and counts this launch. Nothing here can stop the game from
// starting. A failure becomes a message, and a crash inside the library is
// noticed on the next launch, which then skips the library once.
run_check :: proc(s: ^Store, io: File_IO, library_path: string) {
	c := &s.check
	c^ = {}

	if previous, found := io.read(io.data, STEP_FILE, context.allocator); found {
		defer delete(previous)
		step := strings.trim_space(previous)
		if step != "" && step != "done" && step != "retry" {
			io.write(io.data, STEP_FILE, "retry")
			c.status = .Skipped
			check_say(c, "mdix skipped this launch: the last one stopped at step '%s', so it tries again next launch", step)
			return
		}
	}

	m := &s.mdix
	crumb(io, "open")
	if !mdix_open(m, library_path) {
		check_fail(s, io, "mdix not loaded: %s", mdix_error(m))
		return
	}

	crumb(io, "version")
	version_c := m.version()
	if version_c == nil {
		check_fail(s, io, "mdix gave no version")
		return
	}
	version := strings.clone(string(version_c), context.allocator)
	defer delete(version)

	crumb(io, "parse")
	db := m.load_str(SELF_TEST_SOURCE)
	if db == nil {
		check_fail(s, io, "mdix %s could not parse a test document: %s", version, mdix_library_error(m))
		return
	}
	port, port_ok := db_get_int(m, db, "port")
	host, host_ok := db_get_string(m, db, "host")
	defer delete(host)
	missing_ok := !m.exists(db, "no_such_key")
	m.free_db(db)
	if !port_ok || port != 8080 || !host_ok || host != "localhost" || !missing_ok {
		check_fail(s, io, "mdix %s read wrong values from a test document", version)
		return
	}

	crumb(io, "profile")
	launches := 0
	note := ""
	if text, found := io.read(io.data, PROFILE_FILE, context.allocator); found {
		defer delete(text)
		source := strings.clone_to_cstring(text, context.allocator)
		defer delete(source)
		profile := m.load_str(source)
		if profile != nil {
			if value, has := db_get_int(m, profile, "launches"); has {
				launches = value
			}
			m.free_db(profile)
		} else {
			note = ", the old profile was unreadable so it started over"
		}
	}
	launches += 1

	crumb(io, "builder")
	builder := m.builder_new()
	if builder == nil {
		check_fail(s, io, "mdix %s could not start a profile: %s", version, mdix_library_error(m))
		return
	}
	version_cstr := strings.clone_to_cstring(version, context.allocator)
	defer delete(version_cstr)
	m.builder_set_int(builder, "launches", i32(launches))
	m.builder_set_string(builder, "mdix_version", version_cstr)
	written_c := m.builder_to_string(builder)
	if written_c == nil {
		m.builder_free(builder)
		check_fail(s, io, "mdix %s could not write a profile: %s", version, mdix_library_error(m))
		return
	}
	written := strings.clone(string(written_c), context.allocator)
	defer delete(written)
	m.free_string(written_c)
	m.builder_free(builder)

	crumb(io, "save")
	if !io.write(io.data, PROFILE_FILE, written) {
		check_fail(s, io, "mdix %s built a profile but it could not be saved", version)
		return
	}

	crumb(io, "reload")
	reloaded, reloaded_ok := io.read(io.data, PROFILE_FILE, context.allocator)
	if !reloaded_ok {
		check_fail(s, io, "mdix %s saved a profile but it could not be read back", version)
		return
	}
	defer delete(reloaded)
	reloaded_source := strings.clone_to_cstring(reloaded, context.allocator)
	defer delete(reloaded_source)
	again := m.load_str(reloaded_source)
	if again == nil {
		check_fail(s, io, "mdix %s could not read back its own profile: %s", version, mdix_library_error(m))
		return
	}
	count, count_ok := db_get_int(m, again, "launches")
	m.free_db(again)
	if !count_ok || count != launches {
		check_fail(s, io, "mdix %s read back launches %d, expected %d", version, count, launches)
		return
	}

	crumb(io, "done")
	c.status = .Ok
	c.launches = launches
	check_say(c, "mdix %s ok: parse, save and reload passed, launch %d%s", version, launches, note)
}
