// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stock_file.odin"
// ============================================================================

package main

import "carry"
import "core:fmt"
import "inventory"

STOCK_FILE :: "tv_stock.txt"

// Reads what the bag and the wall held last time. A missing file is the first run and is not a problem, and a
// file that is damaged gives back what could be read, with the rest as the lab starts. It cannot stop the game.
stock_load :: proc(s: ^carry.Stock) {
	io := raylib_files()
	text, found := io.read(io.data, STOCK_FILE, context.allocator)
	if !found {
		return
	}
	defer delete(text)
	names := [3]string{"bag", "wall", "bench"}
	containers := [3]^inventory.Container{&s.bag, &s.wall, &s.bench}
	n := inventory.deserialize(text, names[:], containers[:])
	fmt.eprintfln("stock: %d stacks read from %v", n, STOCK_FILE)
}

// Writes the bag and the wall, so they are as they were next time. It is called when a stack is moved and when
// the lab is left, and a failure to write is a line of text and nothing more.
stock_save :: proc(s: ^carry.Stock) {
	names := [3]string{"bag", "wall", "bench"}
	containers := [3]^inventory.Container{&s.bag, &s.wall, &s.bench}
	text := inventory.serialize(names[:], containers[:])
	defer delete(text)
	io := raylib_files()
	if !io.write(io.data, STOCK_FILE, text) {
		fmt.eprintfln("stock: could not write %v", STOCK_FILE)
	}
}
