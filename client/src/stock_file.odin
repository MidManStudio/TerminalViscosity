// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stock_file.odin"
// ============================================================================

package main

import "carry"
import "core:fmt"
import "inventory"
import "lab"

STOCK_FILE :: "tv_stock.txt"

// Reads what the bag and the wall held last time, and where the stations stood. A missing file is the first run and is
// not a problem, and a file that is damaged gives back what could be read, with the rest as the lab starts. It cannot
// stop the game. A file from before stations could stand anywhere has the bench they were on, and they are put at the
// places of its spots. A station in the file that cannot stand where it says goes into the bag if there is room, so that
// it is not lost.
stock_load :: proc(s: ^carry.Stock, placed: ^lab.Placed) {
	io := raylib_files()
	text, found := io.read(io.data, STOCK_FILE, context.allocator)
	if !found {
		return
	}
	defer delete(text)
	names := [3]string{"bag", "wall", "hotbar"}
	containers := [3]^inventory.Container{&s.bag, &s.wall, &s.hotbar}
	n := inventory.deserialize(text, names[:], containers[:])
	read, has_set, set_aside, set_aside_count := lab.placed_deserialize(text)
	if has_set {
		placed^ = read
		for i in 0 ..< set_aside_count {
			inventory.add(&s.bag, carry.station_item(set_aside[i].kind), 1)
		}
	} else {
		placed^, _ = carry.placed_from_bench_file(text)
	}
	fmt.eprintfln("stock: %d stacks and %d stations read from %v", n, placed.count, STOCK_FILE)
}

// Writes the bag and the wall and where the stations stand, so they are as they were next time. It is called when
// something is moved and when the lab is left, and a failure to write is a line of text and nothing more.
stock_save :: proc(s: ^carry.Stock, placed: ^lab.Placed) {
	names := [3]string{"bag", "wall", "hotbar"}
	containers := [3]^inventory.Container{&s.bag, &s.wall, &s.hotbar}
	stacks := inventory.serialize(names[:], containers[:])
	defer delete(stacks)
	stations := lab.placed_serialize(placed)
	defer delete(stations)
	text := fmt.aprintf("%v%v", stacks, stations)
	defer delete(text)
	io := raylib_files()
	if !io.write(io.data, STOCK_FILE, text) {
		fmt.eprintfln("stock: could not write %v", STOCK_FILE)
	}
}
