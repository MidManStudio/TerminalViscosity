// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "chem.odin"
// ============================================================================

// Package chem is what the lab says about a chemical to the player and to the effects: its
// name and its colour, from the compound pages, and how violent a reaction is (hazard.odin). The
// compounds themselves, and what happens when they meet, are in package chemistry. A
// compound is the u16 number it has there. No raylib.
package chem

import "../chemistry"

// The name of a compound for the player, such as "Ethanol", and "" for none.
compound_name :: proc(id: u16) -> string {
	return chemistry.name_of(chemistry.Id(id))
}

// The same for a function that wants a C string.
compound_cname :: proc(id: u16) -> cstring {
	return chemistry.cname_of(chemistry.Id(id))
}

// The colour of a compound as red, green and blue from 0 to 1, white for none.
compound_color :: proc(id: u16) -> [3]f32 {
	return chemistry.color_of(chemistry.Id(id))
}
