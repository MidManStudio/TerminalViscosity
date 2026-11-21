// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "inventory.odin"
// ============================================================================

package inventory

import "core:fmt"
import "core:strconv"
import "core:strings"

MAX_SLOTS :: 16
STOCK_FILE_HEADER :: "tvstock 1"

Item_Kind :: enum u8 {
	None      = 0,
	Dispenser = 1,
	Hot_Plate = 2, // the stations of the bench
	Ice_Bath  = 3,
	Scale     = 4,
}

// What an item is. A container takes only the items that have all the tags it asks for.
Tag :: enum u8 {
	Mountable, // can be mounted on a wall
	Benchable, // can stand on the bench
}

Tags :: bit_set[Tag;u8]

// One kind of thing. `arg` is what makes two of the same kind different: for a dispenser it is the number of the
// compound that it is filled with, 0 for none, and for a station it is 0. Items stack only when kind and arg are both the same.
Item :: struct {
	kind: Item_Kind,
	arg:  u16,
}

Slot :: struct {
	item:  Item,
	count: u16,
}

Item_Def :: struct {
	max_stack: u16, // the most that go in one slot; 0 for something that is not an item
	tags:      Tags,
}

def_of :: proc(kind: Item_Kind) -> Item_Def {
	#partial switch kind {
	case .Dispenser:
		return {1, {.Mountable}}
	case .Hot_Plate, .Ice_Bath, .Scale:
		return {1, {.Benchable}}
	}
	return {0, {}}
}

// A row of slots that hold items. `requires` is the tags an item has to have to go in. A locked container lets
// nothing in, out or about. `version` goes up with every change, so that what depends on the contents knows to
// look again.
Container :: struct {
	slots:    [MAX_SLOTS]Slot,
	size:     int,
	requires: Tags,
	locked:   bool,
	version:  u32,
}

container_init :: proc(c: ^Container, size: int, requires: Tags = {}) {
	c^ = {}
	c.size = clamp(size, 0, MAX_SLOTS)
	c.requires = requires
}

// Whether the container takes this kind of item at all.
accepts :: proc(c: ^Container, item: Item) -> bool {
	d := def_of(item.kind)
	return item.kind != .None && d.max_stack > 0 && c.requires <= d.tags
}

// How many more of `item` slot `i` takes: the whole of a stack for an empty slot, what is left of one that holds
// the same, and none for a slot that holds something else.
room_in :: proc(c: ^Container, i: int, item: Item) -> int {
	s := c.slots[i]
	max := int(def_of(item.kind).max_stack)
	if s.count == 0 {
		return max
	}
	if s.item == item {
		return max - int(s.count)
	}
	return 0
}

// How many of `item` the container could still take.
free_room :: proc(c: ^Container, item: Item) -> int {
	if c.locked || !accepts(c, item) {
		return 0
	}
	n := 0
	for i in 0 ..< c.size {
		n += room_in(c, i, item)
	}
	return n
}

count_of :: proc(c: ^Container, item: Item) -> int {
	n := 0
	for i in 0 ..< c.size {
		if c.slots[i].count > 0 && c.slots[i].item == item {
			n += int(c.slots[i].count)
		}
	}
	return n
}

// Puts as many as fit, up to `count`, first on top of stacks of the same item and then in empty slots, and returns
// how many went in.
add :: proc(c: ^Container, item: Item, count: int) -> int {
	if c.locked || !accepts(c, item) || count <= 0 {
		return 0
	}
	left := count
	for pass in 0 ..< 2 {
		for i in 0 ..< c.size {
			if left == 0 {
				break
			}
			filled := c.slots[i].count > 0
			if filled != (pass == 0) {
				continue
			}
			take := min(left, room_in(c, i, item))
			if take > 0 {
				c.slots[i].item = item
				c.slots[i].count += u16(take)
				left -= take
			}
		}
	}
	if left < count {
		c.version += 1
	}
	return count - left
}

// Takes `count` of `item` out, from the first slots, or none of them when there are not so many: all or nothing.
remove :: proc(c: ^Container, item: Item, count: int) -> bool {
	if c.locked || count <= 0 || count_of(c, item) < count {
		return false
	}
	left := count
	for i in 0 ..< c.size {
		if left == 0 {
			break
		}
		if c.slots[i].count > 0 && c.slots[i].item == item {
			take := min(left, int(c.slots[i].count))
			c.slots[i].count -= u16(take)
			if c.slots[i].count == 0 {
				c.slots[i] = {}
			}
			left -= take
		}
	}
	c.version += 1
	return true
}

// Takes `count` out of slot `i`, whatever is in it. False if the slot has fewer, or the container is locked.
take :: proc(c: ^Container, i, count: int) -> (item: Item, ok: bool) {
	if c.locked || i < 0 || i >= c.size || count <= 0 || int(c.slots[i].count) < count {
		return {}, false
	}
	item = c.slots[i].item
	c.slots[i].count -= u16(count)
	if c.slots[i].count == 0 {
		c.slots[i] = {}
	}
	c.version += 1
	return item, true
}

// Puts `count` of `item` in slot `i`, which has to be empty, or hold the same with room.
put :: proc(c: ^Container, i: int, item: Item, count: int) -> bool {
	if c.locked || i < 0 || i >= c.size || count <= 0 || !accepts(c, item) || room_in(c, i, item) < count {
		return false
	}
	c.slots[i].item = item
	c.slots[i].count += u16(count)
	c.version += 1
	return true
}

// Whether the stack in slot `i` of `from` could be moved to slot `j` of `to`: both open, something to move, the
// other container takes it, and the place empty or holding the same with room. A stack put back where it is
// counts.
can_move :: proc(from: ^Container, i: int, to: ^Container, j: int) -> bool {
	if i < 0 || i >= from.size || j < 0 || j >= to.size || from.locked || to.locked {
		return false
	}
	s := from.slots[i]
	if s.count == 0 {
		return false
	}
	if from == to && i == j {
		return true
	}
	return accepts(to, s.item) && room_in(to, j, s.item) > 0
}

// Moves the stack in slot `i` of `from` to slot `j` of `to`: all of it into an empty place, or as much as fits on
// top of the same item. Never swaps with a different item. True if anything moved, or the stack was put back.
move :: proc(from: ^Container, i: int, to: ^Container, j: int) -> bool {
	if !can_move(from, i, to, j) {
		return false
	}
	if from == to && i == j {
		return true
	}
	s := from.slots[i]
	n := min(int(s.count), room_in(to, j, s.item))
	from.slots[i].count -= u16(n)
	if from.slots[i].count == 0 {
		from.slots[i] = {}
	}
	to.slots[j].item = s.item
	to.slots[j].count += u16(n)
	from.version += 1
	to.version += 1
	return true
}

// Moves `count` of `item` from one container to another, wherever they are, all or nothing: if the other has not
// the room, both are as they were.
transfer :: proc(from, to: ^Container, item: Item, count: int) -> bool {
	before_from, before_to := from^, to^
	if !remove(from, item, count) {
		return false
	}
	if add(to, item, count) < count {
		from^, to^ = before_from, before_to
		return false
	}
	return true
}

// Writes containers as text, by name: a line for each container with its size, and a line for each slot that
// holds something, `slot index kind arg count`. Plain text, because that is what the file functions of the client
// write on every platform.
serialize :: proc(names: []string, containers: []^Container, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, STOCK_FILE_HEADER)
	strings.write_string(&b, "\n")
	for c, k in containers {
		fmt.sbprintf(&b, "container %v %v\n", names[k], c.size)
		for i in 0 ..< c.size {
			s := c.slots[i]
			if s.count > 0 {
				fmt.sbprintf(&b, "slot %v %v %v %v\n", i, int(s.item.kind), s.item.arg, s.count)
			}
		}
	}
	return strings.to_string(b)
}

// Reads text made by `serialize` back into the containers it names. A container named in the text is emptied
// first, so what is in the file is what it holds; one that is not named is left as it is. A line of the wrong shape,
// a slot that does not exist, an item that is not one, one that the container does not take, a count that is not
// a stack, and a slot that is not empty are skipped, and one bad line never fails the rest. A text without the
// header is not read at all. Returns how many stacks came back.
deserialize :: proc(text: string, names: []string, containers: []^Container) -> (count: int) {
	text := text
	first, _ := strings.split_lines_iterator(&text)
	if strings.trim_space(first) != STOCK_FILE_HEADER {
		return 0
	}
	current: ^Container
	for line in strings.split_lines_iterator(&text) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) == 3 && fields[0] == "container" {
			current = nil
			for n, k in names {
				if n == fields[1] {
					current = containers[k]
					keep := current.size
					current.slots = {}
					current.size = keep
					current.version += 1
				}
			}
			continue
		}
		if current == nil || len(fields) != 5 || fields[0] != "slot" {
			continue
		}
		slot, ok1 := strconv.parse_int(fields[1])
		kind, ok2 := strconv.parse_int(fields[2])
		arg, ok3 := strconv.parse_int(fields[3])
		n, ok4 := strconv.parse_int(fields[4])
		if !(ok1 && ok2 && ok3 && ok4) || kind < 1 || kind > int(max(Item_Kind)) || arg < 0 || arg > 65535 {
			continue
		}
		item := Item{Item_Kind(kind), u16(arg)}
		if slot < 0 || slot >= current.size || !accepts(current, item) || n < 1 || n > int(def_of(item.kind).max_stack) || current.slots[slot].count > 0 {
			continue
		}
		current.slots[slot] = {item, u16(n)}
		count += 1
	}
	return
}

// Moves the stack in slot `i` of `from` to the first slot of `to` that takes it: on top of the same item if there
// is room, and otherwise into an empty one. All of it, or nothing, and false if `to` has no place for it.
move_to :: proc(from: ^Container, i: int, to: ^Container) -> bool {
	if i < 0 || i >= from.size || from.slots[i].count == 0 {
		return false
	}
	for pass in 0 ..< 2 {
		for j in 0 ..< to.size {
			filled := to.slots[j].count > 0
			if filled != (pass == 0) {
				continue
			}
			if can_move(from, i, to, j) && int(from.slots[i].count) <= room_in(to, j, from.slots[i].item) {
				return move(from, i, to, j)
			}
		}
	}
	return false
}
