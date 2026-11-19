// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "dragdrop_test.odin"
// ============================================================================

package dragdrop

import "core:testing"

takes_even :: proc(data: rawptr, payload: Payload) -> bool {
	return payload.a % 2 == 0
}

takes_what_the_data_says :: proc(data: rawptr, payload: Payload) -> bool {
	return (cast(^bool)data)^
}

fresh :: proc() -> Controller {
	c: Controller
	controller_init(&c)
	return c
}

@(test)
a_controller_starts_idle_over_nothing :: proc(t: ^testing.T) {
	c := fresh()
	testing.expect(t, !is_dragging(&c), "idle")
	testing.expect_value(t, c.hover, -1)
	testing.expect(t, !c.hover_ok, "nothing is accepted")
}

@(test)
a_drag_begins_once_with_its_payload :: proc(t: ^testing.T) {
	c := fresh()
	testing.expect(t, begin(&c, {3, 7}), "begins")
	testing.expect(t, is_dragging(&c), "dragging")
	testing.expect_value(t, c.payload, Payload{3, 7})
	testing.expect(t, !begin(&c, {1, 1}), "a second one does not begin")
	testing.expect_value(t, c.payload, Payload{3, 7})
}

@(test)
the_hover_is_the_target_the_drag_is_over_and_whether_it_takes_the_payload :: proc(t: ^testing.T) {
	c := fresh()
	begin(&c, {4, 0})
	a := Target{id = 5, can_accept = takes_even}
	set_hover(&c, &a)
	testing.expect_value(t, c.hover, 5)
	testing.expect(t, c.hover_ok, "an even payload is taken")
	c.payload = {3, 0}
	set_hover(&c, &a)
	testing.expect(t, !c.hover_ok, "an odd one is not")
	set_hover(&c, nil)
	testing.expect_value(t, c.hover, -1)
	testing.expect(t, !c.hover_ok, "no target takes nothing")
}

@(test)
a_target_with_no_rule_takes_anything_and_gets_its_data :: proc(t: ^testing.T) {
	c := fresh()
	begin(&c, {1, 1})
	open := Target{id = 1}
	set_hover(&c, &open)
	testing.expect(t, c.hover_ok, "no rule, so it takes it")
	yes, no := true, false
	by_data := Target{id = 2, data = &yes, can_accept = takes_what_the_data_says}
	set_hover(&c, &by_data)
	testing.expect(t, c.hover_ok, "the data says yes")
	by_data.data = &no
	set_hover(&c, &by_data)
	testing.expect(t, !c.hover_ok, "the data says no")
}

@(test)
hovering_does_nothing_when_no_drag_is_going :: proc(t: ^testing.T) {
	c := fresh()
	a := Target{id = 3}
	set_hover(&c, &a)
	testing.expect_value(t, c.hover, -1)
	testing.expect(t, !c.hover_ok, "nothing")
}

@(test)
ending_over_a_target_that_takes_it_drops_and_leaves_the_controller_idle :: proc(t: ^testing.T) {
	c := fresh()
	begin(&c, {2, 9})
	a := Target{id = 6}
	set_hover(&c, &a)
	payload, target, dropped := end(&c)
	testing.expect(t, dropped, "dropped")
	testing.expect_value(t, target, 6)
	testing.expect_value(t, payload, Payload{2, 9})
	testing.expect(t, !is_dragging(&c), "idle again")
	testing.expect_value(t, c.hover, -1)
}

@(test)
ending_over_nothing_or_over_a_target_that_does_not_take_it_drops_nothing :: proc(t: ^testing.T) {
	c := fresh()
	begin(&c, {3, 0})
	_, target, dropped := end(&c)
	testing.expect(t, !dropped, "over nothing")
	testing.expect_value(t, target, -1)
	begin(&c, {3, 0})
	odd := Target{id = 4, can_accept = takes_even}
	set_hover(&c, &odd)
	_, target, dropped = end(&c)
	testing.expect(t, !dropped, "a target that does not take it")
	testing.expect_value(t, target, 4)
	testing.expect(t, !is_dragging(&c), "idle")
}

@(test)
ending_with_no_drag_gives_nothing :: proc(t: ^testing.T) {
	c := fresh()
	payload, target, dropped := end(&c)
	testing.expect(t, !dropped, "nothing dropped")
	testing.expect_value(t, target, -1)
	testing.expect_value(t, payload, Payload{})
}

@(test)
cancel_ends_a_drag_without_a_drop_and_a_new_one_can_begin :: proc(t: ^testing.T) {
	c := fresh()
	begin(&c, {1, 2})
	a := Target{id = 1}
	set_hover(&c, &a)
	cancel(&c)
	testing.expect(t, !is_dragging(&c), "cancelled")
	testing.expect_value(t, c.hover, -1)
	testing.expect(t, !c.hover_ok, "no hover")
	testing.expect(t, begin(&c, {5, 6}), "a new one begins")
	testing.expect_value(t, c.payload, Payload{5, 6})
}
