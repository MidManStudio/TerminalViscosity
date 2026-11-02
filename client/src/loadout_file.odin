// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout_file.odin"
// ============================================================================

package main

import "carry"
import "core:fmt"

LOADOUT_FILE :: "tv_loadout.txt"

// Makes the store for drawings if there is none yet, and reads the balloons the player
// saved last time into the loadout. A missing file is the first run and is not a problem,
// and a file that is damaged gives back what could be read. It cannot stop the game.
loadout_load :: proc(game: ^Game) {
	if game.art == nil {
		game.art = new(carry.Art_Store)
	}
	io := raylib_files()
	text, found := io.read(io.data, LOADOUT_FILE, context.allocator)
	if !found {
		return
	}
	defer delete(text)
	n := carry.loadout_deserialize(text, &game.loadout, game.art)
	fmt.eprintfln("loadout: %d balloons read from %v", n, LOADOUT_FILE)
}

// Writes the balloons of the player to the file, so they are there next time. It is
// called when a balloon is moved, when a drawing is finished, and when the lab is left,
// and a failure to write is a line of text and nothing more.
loadout_save :: proc(game: ^Game) {
	if game.art == nil {
		return
	}
	text := carry.loadout_serialize(&game.loadout, game.art)
	defer delete(text)
	io := raylib_files()
	if !io.write(io.data, LOADOUT_FILE, text) {
		fmt.eprintfln("loadout: could not write %v", LOADOUT_FILE)
	}
}
