// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout_save.odin"
// ============================================================================

package carry

import "../chemistry"
import "core:fmt"
import "core:strconv"
import "core:strings"

LOADOUT_FILE_HEADER :: "tvloadout 2"

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

// The ingredients of a mixture as text: `number:millilitres:purity` for each, comma between,
// with no spaces. An ingredient that rounds to no millilitres is left out.
ingredients_text :: proc(m: ^chemistry.Mixture, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	first := true
	for i in 0 ..< m.count {
		it := m.items[i]
		ml := int(it.ml + 0.5)
		if ml < 1 {
			continue
		}
		if !first {
			strings.write_string(&b, ",")
		}
		first = false
		fmt.sbprintf(&b, "%d:%d:%d", int(it.compound), ml, int(clamp(it.purity, 0, 1) * 100 + 0.5))
	}
	return strings.to_string(b)
}

// Reads what `ingredients_text` wrote into a mixture at room temperature. False for anything
// that is not a list of one to eight compounds that exist, with whole millilitres, a purity
// from 0 to 100, and no more liquid altogether than a balloon holds.
ingredients_parse :: proc(text: string) -> (m: chemistry.Mixture, ok: bool) {
	m.heat_c = ROOM_C
	total := 0
	parts := strings.split(text, ",", context.temp_allocator)
	if len(parts) < 1 {
		return {}, false
	}
	for part in parts {
		fields := strings.split(part, ":", context.temp_allocator)
		if len(fields) != 3 {
			return {}, false
		}
		id, ok1 := strconv.parse_int(fields[0])
		ml, ok2 := strconv.parse_int(fields[1])
		purity, ok3 := strconv.parse_int(fields[2])
		if !ok1 || !ok2 || !ok3 || id < 1 || id > chemistry.COMPOUND_COUNT || ml < 1 || purity < 0 || purity > 100 {
			return {}, false
		}
		total += ml
		if total > int(BALLOON_REST_ML) {
			return {}, false
		}
		if !chemistry.add_ingredient(&m, chemistry.Id(id), f32(ml), f32(purity) / 100, false) {
			return {}, false
		}
	}
	return m, true
}

// Turns the balloons of the player into text that can be written to a file and read back:
// a header line, and a line for each place that holds a balloon, with the place, what is
// in it, and the drawing as the hexadecimal of its encoding. What is in it is a list with no
// spaces, `number:millilitres:purity` for each compound with the purity as a whole percent,
// separated by commas, and the amounts are rounded to whole millilitres. The temperature
// is not kept, because it does not last. Heat that a liquid had is lost, as it would be
// in a minute anyway, and so is the unsafe meter. Plain text, because that is what the file
// functions of the client can write on every platform. A file of the first version, whose
// compounds were other compounds, is not read.
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
		fmt.sbprintf(&b, "item %v %v %v\n", place_name(i), ingredients_text(&item.mix), art)
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
		if len(fields) != 4 || fields[0] != "item" {
			continue
		}
		slot := -1
		for i in 0 ..< 2 + LOADOUT_SLOTS {
			if place_name(i) == fields[1] {
				slot = i
			}
		}
		mix, parsed := ingredients_parse(fields[2])
		if slot == -1 || !parsed {
			continue
		}
		item := Item {
			used = true,
			mix  = mix,
		}
		if fields[3] != "-" {
			if bytes, ok := hex_decode(fields[3], context.temp_allocator); ok {
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
