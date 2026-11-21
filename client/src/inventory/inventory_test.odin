// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "inventory_test.odin"
// ============================================================================

package inventory

import "core:strings"
import "core:testing"

wall :: proc() -> Container {
	c: Container
	container_init(&c, 4, {.Mountable})
	return c
}

bag :: proc() -> Container {
	c: Container
	container_init(&c, 3)
	return c
}

ethanol :: Item{.Dispenser, 3}
acid :: Item{.Dispenser, 4}

@(test)
a_container_has_the_size_it_is_given_up_to_the_most :: proc(t: ^testing.T) {
	c: Container
	container_init(&c, 5)
	testing.expect_value(t, c.size, 5)
	container_init(&c, 99)
	testing.expect_value(t, c.size, MAX_SLOTS)
	container_init(&c, -2)
	testing.expect_value(t, c.size, 0)
}

@(test)
only_items_with_all_the_tags_a_container_asks_for_go_in_it :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	testing.expect(t, accepts(&w, ethanol), "a dispenser is mountable")
	testing.expect(t, accepts(&b, ethanol), "and the bag takes anything")
	testing.expect(t, !accepts(&w, Item{.None, 0}), "nothing is not an item")
	strict: Container
	container_init(&strict, 2, {.Mountable})
	// An item with no tags would not go in: there is none yet, so test the rule with the tags of the dispenser.
	testing.expect(t, def_of(.Dispenser).tags >= {.Mountable}, "a dispenser has the tag")
	testing.expect_value(t, def_of(.None).max_stack, u16(0))
}

@(test)
add_puts_items_in_empty_slots_and_stops_when_full :: proc(t: ^testing.T) {
	b := bag()
	testing.expect_value(t, add(&b, ethanol, 2), 2)
	testing.expect_value(t, count_of(&b, ethanol), 2)
	testing.expect_value(t, add(&b, acid, 5), 1) // only one slot is left, and a dispenser does not stack
	testing.expect_value(t, count_of(&b, acid), 1)
	testing.expect_value(t, add(&b, ethanol, 1), 0)
	testing.expect_value(t, free_room(&b, ethanol), 0)
}

@(test)
add_tops_up_a_stack_before_it_uses_an_empty_slot :: proc(t: ^testing.T) {
	// The dispenser does not stack, so this is checked by the order the slots fill in.
	b := bag()
	b.slots[1] = {ethanol, 1}
	testing.expect_value(t, add(&b, acid, 1), 1)
	testing.expect_value(t, b.slots[0].item, acid) // the first empty slot, not after the filled one
	testing.expect_value(t, b.slots[1].item, ethanol)
}

@(test)
add_does_nothing_for_a_locked_container_a_bad_item_or_a_bad_count :: proc(t: ^testing.T) {
	b := bag()
	b.locked = true
	testing.expect_value(t, add(&b, ethanol, 1), 0)
	b.locked = false
	testing.expect_value(t, add(&b, Item{.None, 0}, 1), 0)
	testing.expect_value(t, add(&b, ethanol, 0), 0)
	testing.expect_value(t, add(&b, ethanol, -3), 0)
	testing.expect_value(t, b.version, u32(0))
}

@(test)
the_version_goes_up_with_every_change_and_not_without_one :: proc(t: ^testing.T) {
	b := bag()
	add(&b, ethanol, 1)
	testing.expect_value(t, b.version, u32(1))
	add(&b, ethanol, 0)
	testing.expect_value(t, b.version, u32(1))
	remove(&b, ethanol, 1)
	testing.expect_value(t, b.version, u32(2))
	remove(&b, ethanol, 1) // none left
	testing.expect_value(t, b.version, u32(2))
	put(&b, 0, ethanol, 1)
	testing.expect_value(t, b.version, u32(3))
	take(&b, 0, 1)
	testing.expect_value(t, b.version, u32(4))
}

@(test)
remove_takes_all_or_nothing :: proc(t: ^testing.T) {
	b := bag()
	add(&b, ethanol, 1)
	add(&b, ethanol, 1)
	testing.expect(t, !remove(&b, ethanol, 3), "there are only two")
	testing.expect_value(t, count_of(&b, ethanol), 2)
	testing.expect(t, remove(&b, ethanol, 2), "two are there")
	testing.expect_value(t, count_of(&b, ethanol), 0)
	testing.expect(t, !remove(&b, ethanol, 0), "none is not a removal")
	b.locked = true
	add(&b, ethanol, 1)
	testing.expect(t, !remove(&b, ethanol, 1), "a locked container gives nothing")
}

@(test)
remove_takes_from_the_first_slots_and_leaves_the_others :: proc(t: ^testing.T) {
	b := bag()
	add(&b, ethanol, 1)
	add(&b, acid, 1)
	add(&b, ethanol, 1)
	testing.expect(t, remove(&b, ethanol, 1), "one ethanol")
	testing.expect_value(t, b.slots[0], Slot{})
	testing.expect_value(t, b.slots[1].item, acid)
	testing.expect_value(t, b.slots[2].item, ethanol)
}

@(test)
take_and_put_work_on_one_slot :: proc(t: ^testing.T) {
	w := wall()
	testing.expect(t, put(&w, 2, ethanol, 1), "into an empty slot")
	testing.expect(t, !put(&w, 2, acid, 1), "not into a full one")
	testing.expect(t, !put(&w, 4, acid, 1), "not past the end")
	testing.expect(t, !put(&w, -1, acid, 1), "nor before the start")
	testing.expect(t, !put(&w, 0, ethanol, 2), "not more than a stack")
	testing.expect(t, !put(&w, 0, Item{.None, 0}, 1), "not nothing")
	item, ok := take(&w, 2, 1)
	testing.expect(t, ok && item == ethanol, "the ethanol comes out")
	testing.expect_value(t, w.slots[2], Slot{})
	_, ok = take(&w, 2, 1)
	testing.expect(t, !ok, "nothing is left")
	_, ok = take(&w, 9, 1)
	testing.expect(t, !ok, "no such slot")
	put(&w, 1, ethanol, 1)
	w.locked = true
	_, ok = take(&w, 1, 1)
	testing.expect(t, !ok, "locked")
	testing.expect(t, !put(&w, 0, acid, 1), "and nothing goes in")
}

@(test)
a_stack_moves_to_an_empty_place_in_another_container :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	put(&w, 0, ethanol, 1)
	testing.expect(t, can_move(&w, 0, &b, 2), "it can")
	testing.expect(t, move(&w, 0, &b, 2), "and does")
	testing.expect_value(t, w.slots[0], Slot{})
	testing.expect_value(t, b.slots[2], Slot{ethanol, 1})
	testing.expect(t, move(&b, 2, &w, 3), "and back, to another slot")
	testing.expect_value(t, w.slots[3], Slot{ethanol, 1})
}

@(test)
a_stack_does_not_swap_with_another_item_or_go_where_it_is_not_taken_or_from_nothing :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	put(&w, 0, ethanol, 1)
	put(&b, 0, acid, 1)
	testing.expect(t, !can_move(&w, 0, &b, 0), "the place holds another item")
	testing.expect(t, !move(&w, 0, &b, 0), "so it does not move")
	testing.expect_value(t, w.slots[0], Slot{ethanol, 1})
	testing.expect_value(t, b.slots[0], Slot{acid, 1})
	testing.expect(t, !can_move(&w, 1, &b, 1), "an empty slot has nothing to move")
	testing.expect(t, !can_move(&w, 0, &b, 3), "no such place")
	testing.expect(t, !can_move(&w, 4, &b, 1), "no such slot")
	testing.expect(t, !can_move(&w, -1, &b, 1), "nor before the start")
	testing.expect(t, !can_move(&w, 0, &b, -1), "nor a place before the start")
	b.locked = true
	testing.expect(t, !can_move(&w, 0, &b, 1), "the target is locked")
	b.locked = false
	w.locked = true
	testing.expect(t, !can_move(&w, 0, &b, 1), "the source is locked")
}

@(test)
a_stack_put_back_where_it_is_counts_as_a_move_and_changes_nothing :: proc(t: ^testing.T) {
	w := wall()
	put(&w, 1, ethanol, 1)
	version := w.version
	testing.expect(t, can_move(&w, 1, &w, 1), "it can")
	testing.expect(t, move(&w, 1, &w, 1), "and does, in a way")
	testing.expect_value(t, w.slots[1], Slot{ethanol, 1})
	testing.expect_value(t, w.version, version)
	testing.expect(t, !can_move(&w, 0, &w, 0), "an empty one has nothing to put back")
}

@(test)
moving_within_one_container_goes_to_the_new_slot :: proc(t: ^testing.T) {
	w := wall()
	put(&w, 0, ethanol, 1)
	testing.expect(t, move(&w, 0, &w, 3), "to another slot of the same wall")
	testing.expect_value(t, w.slots[0], Slot{})
	testing.expect_value(t, w.slots[3], Slot{ethanol, 1})
}

@(test)
transfer_moves_all_or_leaves_both_as_they_were :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	add(&w, ethanol, 1)
	add(&w, acid, 1)
	testing.expect(t, transfer(&w, &b, ethanol, 1), "one ethanol to the bag")
	testing.expect_value(t, count_of(&w, ethanol), 0)
	testing.expect_value(t, count_of(&b, ethanol), 1)
	// The bag has room for two more, and a transfer of three has to leave both as they were.
	testing.expect(t, !transfer(&b, &w, ethanol, 2), "there is only one")
	testing.expect_value(t, count_of(&b, ethanol), 1)
	add(&b, acid, 2) // the bag is full now
	before_w, before_b := w, b
	testing.expect(t, !transfer(&w, &b, acid, 1), "the bag has no room")
	testing.expect_value(t, w, before_w)
	testing.expect_value(t, b, before_b)
}

@(test)
what_a_container_does_not_take_does_not_transfer :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	add(&b, ethanol, 1)
	testing.expect(t, transfer(&b, &w, ethanol, 1), "a dispenser is mountable")
	testing.expect(t, !transfer(&b, &w, Item{.None, 0}, 1), "nothing is not")
}

@(test)
containers_come_back_from_text_as_they_were :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	put(&w, 0, ethanol, 1)
	put(&w, 3, acid, 1)
	put(&b, 1, Item{.Dispenser, 0}, 1)
	names := [2]string{"wall", "bag"}
	cs := [2]^Container{&w, &b}
	text := serialize(names[:], cs[:])
	defer delete(text)
	testing.expect(t, strings.has_prefix(text, STOCK_FILE_HEADER), "it has the header")
	w2, b2 := wall(), bag()
	put(&w2, 1, acid, 1) // something that the file does not have, which is cleared
	cs2 := [2]^Container{&w2, &b2}
	testing.expect_value(t, deserialize(text, names[:], cs2[:]), 3)
	testing.expect_value(t, w2.slots, w.slots)
	testing.expect_value(t, b2.slots, b.slots)
	testing.expect_value(t, w2.size, 4)
}

@(test)
a_container_that_the_text_does_not_name_is_left_as_it_is :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	put(&w, 0, ethanol, 1)
	put(&b, 0, acid, 1)
	names := [1]string{"wall"}
	cs := [1]^Container{&w}
	text := serialize(names[:], cs[:])
	defer delete(text)
	b2 := bag()
	put(&b2, 2, acid, 1)
	names2 := [2]string{"wall", "bag"}
	w2 := wall()
	cs2 := [2]^Container{&w2, &b2}
	testing.expect_value(t, deserialize(text, names2[:], cs2[:]), 1)
	testing.expect_value(t, b2.slots[2], Slot{acid, 1})
}

@(test)
bad_lines_are_skipped_and_the_rest_is_read :: proc(t: ^testing.T) {
	w := wall()
	names := [1]string{"wall"}
	cs := [1]^Container{&w}
	text := "tvstock 1\ncontainer wall 4\nslot 0 1 3 1\nslot x 1 3 1\nslot 9 1 3 1\nslot 1 0 3 1\nslot 1 9 3 1\nslot 1 1 -1 1\nslot 1 1 70000 1\nslot 1 1 3 0\nslot 1 1 3 2\nslot 0 1 4 1\nslot 2 1\nrubbish\nslot 3 1 4 1\n"
	testing.expect_value(t, deserialize(text, names[:], cs[:]), 2)
	testing.expect_value(t, w.slots[0], Slot{ethanol, 1}) // the later line for slot 0 did not replace it
	testing.expect_value(t, w.slots[3], Slot{acid, 1})
	testing.expect_value(t, w.slots[1], Slot{})
	testing.expect_value(t, w.slots[2], Slot{})
}

@(test)
text_without_the_header_is_not_read :: proc(t: ^testing.T) {
	w := wall()
	names := [1]string{"wall"}
	cs := [1]^Container{&w}
	testing.expect_value(t, deserialize("container wall 4\nslot 0 1 3 1\n", names[:], cs[:]), 0)
	testing.expect_value(t, deserialize("", names[:], cs[:]), 0)
	testing.expect_value(t, deserialize("tvstock 2\ncontainer wall 4\nslot 0 1 3 1\n", names[:], cs[:]), 0)
	testing.expect_value(t, w.slots[0], Slot{})
}

@(test)
text_for_a_wall_that_takes_only_mountable_things_keeps_the_rule :: proc(t: ^testing.T) {
	w := wall()
	names := [1]string{"wall"}
	cs := [1]^Container{&w}
	text := "tvstock 1\ncontainer wall 4\nslot 0 1 3 1\nslot 1 1 5 1\n"
	testing.expect_value(t, deserialize(text, names[:], cs[:]), 2)
	// A slot past the size of this wall is skipped even if the text said the wall was larger.
	text2 := "tvstock 1\ncontainer wall 10\nslot 6 1 3 1\nslot 3 1 3 1\n"
	w2 := wall()
	cs2 := [1]^Container{&w2}
	testing.expect_value(t, deserialize(text2, names[:], cs2[:]), 1)
	testing.expect_value(t, w2.size, 4)
}

@(test)
identical_dispensers_each_take_a_slot_and_do_not_stack :: proc(t: ^testing.T) {
	b := bag()
	testing.expect_value(t, add(&b, ethanol, 3), 3)
	for i in 0 ..< 3 {
		testing.expect_value(t, b.slots[i], Slot{ethanol, 1})
	}
	testing.expect_value(t, add(&b, ethanol, 1), 0)
	testing.expect_value(t, free_room(&b, ethanol), 0)
	testing.expect_value(t, count_of(&b, ethanol), 3)
}

@(test)
adding_to_a_full_container_changes_nothing_and_not_the_version :: proc(t: ^testing.T) {
	b := bag()
	add(&b, ethanol, 3)
	version := b.version
	testing.expect_value(t, add(&b, acid, 1), 0)
	testing.expect_value(t, b.version, version)
}

@(test)
free_room_counts_empty_slots_and_nothing_for_a_locked_or_refusing_container :: proc(t: ^testing.T) {
	b := bag()
	testing.expect_value(t, free_room(&b, ethanol), 3)
	add(&b, acid, 1)
	testing.expect_value(t, free_room(&b, ethanol), 2)
	b.locked = true
	testing.expect_value(t, free_room(&b, ethanol), 0)
	b.locked = false
	testing.expect_value(t, free_room(&b, Item{.None, 0}), 0)
}

@(test)
the_text_has_a_line_for_each_container_and_each_stack_and_none_for_an_empty_slot :: proc(t: ^testing.T) {
	w, b := wall(), bag()
	put(&w, 0, ethanol, 1)
	put(&b, 2, acid, 1)
	names := [2]string{"wall", "bag"}
	cs := [2]^Container{&w, &b}
	text := serialize(names[:], cs[:])
	defer delete(text)
	lines := strings.split_lines(text)
	defer delete(lines)
	slot_lines, container_lines := 0, 0
	for l in lines {
		if strings.has_prefix(l, "slot ") {
			slot_lines += 1
		}
		if strings.has_prefix(l, "container ") {
			container_lines += 1
		}
	}
	testing.expect_value(t, slot_lines, 2)
	testing.expect_value(t, container_lines, 2)
}

bench_row :: proc() -> Container {
	c: Container
	container_init(&c, 3, {.Benchable})
	return c
}

@(test)
stations_go_on_a_bench_and_not_on_a_wall_and_dispensers_the_other_way_round :: proc(t: ^testing.T) {
	w, row, b := wall(), bench_row(), bag()
	for kind in ([3]Item_Kind{.Hot_Plate, .Ice_Bath, .Scale}) {
		item := Item{kind, 0}
		testing.expect(t, accepts(&row, item), "the bench takes it")
		testing.expect(t, accepts(&b, item), "so does the bag")
		testing.expect(t, !accepts(&w, item), "the wall does not")
		testing.expect_value(t, def_of(kind).max_stack, u16(1))
	}
	testing.expect(t, !accepts(&row, ethanol), "the bench does not take a dispenser")
	testing.expect(t, accepts(&w, ethanol), "and the wall does")
}

@(test)
move_to_puts_a_stack_in_the_first_slot_that_takes_it :: proc(t: ^testing.T) {
	row, b := bench_row(), bag()
	put(&row, 1, Item{.Scale, 0}, 1)
	b.slots[0] = {ethanol, 1} // the first slot of the bag is taken
	testing.expect(t, move_to(&row, 1, &b), "to the bag")
	testing.expect_value(t, b.slots[1], Slot{{.Scale, 0}, 1})
	testing.expect_value(t, row.slots[1], Slot{})
	testing.expect(t, !move_to(&row, 1, &b), "an empty slot has nothing to move")
	testing.expect(t, !move_to(&row, -1, &b), "nor one that does not exist")
	testing.expect(t, !move_to(&row, 3, &b), "nor one past the end")
}

@(test)
move_to_does_nothing_when_nowhere_takes_the_stack :: proc(t: ^testing.T) {
	row, w := bench_row(), wall()
	put(&row, 0, Item{.Scale, 0}, 1)
	testing.expect(t, !move_to(&row, 0, &w), "the wall takes no station")
	testing.expect_value(t, row.slots[0], Slot{{.Scale, 0}, 1})
	b := bag()
	add(&b, ethanol, 3)
	testing.expect(t, !move_to(&row, 0, &b), "the bag is full")
	testing.expect_value(t, row.slots[0], Slot{{.Scale, 0}, 1})
	row.locked = true
	b2 := bag()
	testing.expect(t, !move_to(&row, 0, &b2), "the bench is locked")
}

@(test)
text_with_a_station_in_a_wall_is_skipped :: proc(t: ^testing.T) {
	w := wall()
	names := [1]string{"wall"}
	cs := [1]^Container{&w}
	text := "tvstock 1\ncontainer wall 4\nslot 0 2 0 1\nslot 1 1 3 1\n" // a hot plate, then a dispenser
	testing.expect_value(t, deserialize(text, names[:], cs[:]), 1)
	testing.expect_value(t, w.slots[0], Slot{})
	testing.expect_value(t, w.slots[1], Slot{ethanol, 1})
}
