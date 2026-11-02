// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout_save.odin"
// ============================================================================

package carry

import "core:fmt"
import "core:strconv"
import "core:strings"

LOADOUT_FILE_HEADER :: "tvloadout 1"

// Names the places a balloon can be in the saved text: the hand, the paint station, and
// each hook.
place_name :: proc(i: int, allocator := context.temp_allocator) -> string {
	switch i {
	case 0:
		return "hand"
	case 1:
		return "paint"
	}
	return fmt.aprintf("slot%d", i - 2, allocator = allocator)
}

place_item :: proc(lo: ^Loadout, i: int) -> ^Item {
	switch i {
	case 0:
		return &lo.hand
	case 1:
		return &lo.paint
	}
	if i - 2 < LOADOUT_SLOTS {
		return &lo.slots[i - 2]
	}
	return nil
}

// Turns the balloons of the player into text that can be written to a file and read back:
// a header line, and a line for each place that holds a balloon, with the place, the
// liquid, how much, and the drawing as the hexadecimal of its encoding. The temperature
// is not kept, because it does not last. Heat that a liquid had is lost, as it would be
// in a minute anyway. Plain text, because that is what the file functions of the client
// can write on every platform.
loadout_serialize :: proc(lo: ^Loadout, store: ^Art_Store, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, LOADOUT_FILE_HEADER)
	strings.write_string(&b, "\n")
	for i in 0 ..< 2 + LOADOUT_SLOTS {
		item := place_item(lo, i)^
		if !item.used {
			continue
		}
		art := "-"
		if c := art_get(store, item.art); c != nil {
			art = hex_encode(art_encode(c, context.temp_allocator), context.temp_allocator)
		}
		fmt.sbprintf(&b, "item %v %d %d %v\n", place_name(i), item.compound, int(item.ml + 0.5), art)
	}
	return strings.to_string(b)
}

// Reads text made by `loadout_serialize` back into a loadout, and makes a drawing in the
// store for each balloon that had one. Anything it cannot read, a line of the wrong shape,
// a place that does not exist, a number out of range, a drawing that does not decode, is
// skipped, and a balloon whose drawing is bad comes back without one. A text without the
// header is not read at all. It never fails the whole read for one bad line. Returns how
// many balloons came back.
loadout_deserialize :: proc(text: string, lo: ^Loadout, store: ^Art_Store) -> (count: int) {
	text := text
	first, _ := strings.split_lines_iterator(&text)
	if strings.trim_space(first) != LOADOUT_FILE_HEADER {
		return 0
	}
	for line in strings.split_lines_iterator(&text) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) != 5 || fields[0] != "item" {
			continue
		}
		slot := -1
		for i in 0 ..< 2 + LOADOUT_SLOTS {
			if place_name(i) == fields[1] {
				slot = i
			}
		}
		compound, ok1 := strconv.parse_int(fields[2])
		ml, ok2 := strconv.parse_int(fields[3])
		if slot == -1 || !ok1 || !ok2 || compound < 1 || compound > 65535 || ml < 1 || ml > int(BALLOON_REST_ML) {
			continue
		}
		item := Item {
			used     = true,
			compound = u16(compound),
			ml       = f32(ml),
		}
		if fields[4] != "-" {
			if bytes, ok := hex_decode(fields[4], context.temp_allocator); ok {
				id := art_new(store)
				if id != 0 {
					if art_decode(bytes, art_get(store, id)) {
						item.art = id
					} else {
						art_free(store, id)
					}
				}
			}
		}
		place_item(lo, slot)^ = item
		count += 1
	}
	return
}
