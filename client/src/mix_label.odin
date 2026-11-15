// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mix_label.odin"
// ============================================================================

package main

import "chemistry"
import "core:strconv"

// What a mixture is called in a line of text, written into `out` with nothing allocated, so it can be
// used every frame: "empty", the name of the one compound, or the name of the compound there is most of
// followed by how many others there are, such as "Water +2". The text is a view of `out`.
mix_label :: proc(m: ^chemistry.Mixture, out: []u8) -> string {
	if m.count == 0 {
		return "empty"
	}
	n := 0
	put :: proc(out: []u8, n: ^int, text: string) {
		for c in transmute([]u8)text {
			if n^ < len(out) {
				out[n^] = c
				n^ += 1
			}
		}
	}
	put(out, &n, chemistry.name_of(chemistry.dominant(m)))
	if m.count > 1 {
		put(out, &n, " +")
		digits: [8]u8
		put(out, &n, strconv.write_int(digits[:], i64(m.count - 1), 10))
	}
	return string(out[:n])
}
