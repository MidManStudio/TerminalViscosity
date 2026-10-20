// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "store_test.odin"
// ============================================================================

package store

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"

// Files held in memory, standing in for the device's storage.
Memory_Files :: struct {
	names: [8]string,
	texts: [8]string,
	count: int,
}

memory_read :: proc(data: rawptr, name: string, allocator: runtime.Allocator) -> (text: string, ok: bool) {
	files := cast(^Memory_Files)data
	for i in 0 ..< files.count {
		if files.names[i] == name {
			return strings.clone(files.texts[i], allocator), true
		}
	}
	return "", false
}

memory_write :: proc(data: rawptr, name: string, text: string) -> bool {
	files := cast(^Memory_Files)data
	for i in 0 ..< files.count {
		if files.names[i] == name {
			delete(files.texts[i])
			files.texts[i] = strings.clone(text)
			return true
		}
	}
	if files.count == len(files.names) {
		return false
	}
	files.names[files.count] = strings.clone(name)
	files.texts[files.count] = strings.clone(text)
	files.count += 1
	return true
}

memory_io :: proc(files: ^Memory_Files) -> File_IO {
	return {data = files, read = memory_read, write = memory_write}
}

memory_free :: proc(files: ^Memory_Files) {
	for i in 0 ..< files.count {
		delete(files.names[i])
		delete(files.texts[i])
	}
}

memory_text :: proc(files: ^Memory_Files, name: string) -> string {
	for i in 0 ..< files.count {
		if files.names[i] == name {
			return files.texts[i]
		}
	}
	return ""
}

// The libraries under test come from the environment, so these tests skip
// themselves on a machine that has not built or downloaded them.
library_from_env :: proc(variable: string) -> (path: string, found: bool) {
	return os.lookup_env(variable, context.allocator)
}

@(test)
a_missing_library_is_a_message_and_not_a_crash :: proc(t: ^testing.T) {
	files: Memory_Files
	defer memory_free(&files)
	s: Store
	run_check(&s, memory_io(&files), "/no/such/place/libmdix_ffi.so")
	testing.expect_value(t, s.check.status, Status.Failed)
	testing.expect(t, strings.contains(check_text(&s.check), "mdix not loaded"))
	testing.expect(t, strings.contains(check_text(&s.check), "libmdix_ffi.so"))
	// A failure the code handled is not a crash, so the next launch tries again.
	testing.expect_value(t, memory_text(&files, STEP_FILE), "retry")
}

@(test)
a_launch_that_stopped_inside_the_library_skips_it_once :: proc(t: ^testing.T) {
	files: Memory_Files
	defer memory_free(&files)
	memory_write(&files, STEP_FILE, "parse")
	s: Store
	run_check(&s, memory_io(&files), "/no/such/place/libmdix_ffi.so")
	testing.expect_value(t, s.check.status, Status.Skipped)
	testing.expect(t, strings.contains(check_text(&s.check), "'parse'"))
	testing.expect(t, !s.mdix.loaded)
	// The next launch goes ahead, here as far as the missing library.
	testing.expect_value(t, memory_text(&files, STEP_FILE), "retry")
	run_check(&s, memory_io(&files), "/no/such/place/libmdix_ffi.so")
	testing.expect_value(t, s.check.status, Status.Failed)
}

@(test)
a_finished_or_handled_launch_is_not_treated_as_a_crash :: proc(t: ^testing.T) {
	for step in ([]string{"done", "retry", ""}) {
		files: Memory_Files
		defer memory_free(&files)
		memory_write(&files, STEP_FILE, step)
		s: Store
		run_check(&s, memory_io(&files), "/no/such/place/libmdix_ffi.so")
		testing.expectf(t, s.check.status == .Failed, "step '%v' was treated as a crash", step)
	}
}

@(test)
the_check_passes_and_counts_launches_with_the_stand_in_library :: proc(t: ^testing.T) {
	path, found := library_from_env("TV_MDIX_FAKE_LIB")
	if !found {
		testing.expect(t, true, "TV_MDIX_FAKE_LIB is not set, skipped")
		return
	}
	defer delete(path)
	files: Memory_Files
	defer memory_free(&files)
	for launch in 1 ..= 3 {
		s: Store
		run_check(&s, memory_io(&files), path)
		testing.expectf(t, s.check.status == .Ok, "launch %v: %v", launch, check_text(&s.check))
		testing.expect_value(t, s.check.launches, launch)
	}
	testing.expect_value(t, memory_text(&files, STEP_FILE), "done")
	testing.expect(t, strings.contains(memory_text(&files, PROFILE_FILE), "launches"))
}

@(test)
an_unreadable_profile_starts_over :: proc(t: ^testing.T) {
	path, found := library_from_env("TV_MDIX_FAKE_LIB")
	if !found {
		testing.expect(t, true, "TV_MDIX_FAKE_LIB is not set, skipped")
		return
	}
	defer delete(path)
	files: Memory_Files
	defer memory_free(&files)
	memory_write(&files, PROFILE_FILE, "this is (( not a profile")
	s: Store
	run_check(&s, memory_io(&files), path)
	testing.expectf(t, s.check.status == .Ok, "%v", check_text(&s.check))
	testing.expect_value(t, s.check.launches, 1)
	testing.expect(t, strings.contains(check_text(&s.check), "started over"))
}

@(test)
the_real_library_passes_the_same_check :: proc(t: ^testing.T) {
	path, found := library_from_env("TV_MDIX_LIB")
	if !found {
		testing.expect(t, true, "TV_MDIX_LIB is not set, skipped")
		return
	}
	defer delete(path)
	files: Memory_Files
	defer memory_free(&files)
	for launch in 1 ..= 2 {
		s: Store
		run_check(&s, memory_io(&files), path)
		testing.expectf(t, s.check.status == .Ok, "launch %v: %v", launch, check_text(&s.check))
		testing.expect_value(t, s.check.launches, launch)
	}
}
