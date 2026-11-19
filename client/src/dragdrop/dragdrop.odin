// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "dragdrop.odin"
// ============================================================================

package dragdrop

// What is being dragged. The controller never looks inside it: the one who begins a drag says what it means, and the
// targets read it.
Payload :: struct {
	a, b: i32,
}

Phase :: enum u8 {
	Idle,
	Dragging,
}

// Somewhere a drag can end. `can_accept` says whether this place takes what is being dragged, so that a view can show
// which places do while the drag goes on. A target with no `can_accept` takes anything.
Target :: struct {
	id:         int,
	data:       rawptr,
	can_accept: proc(data: rawptr, payload: Payload) -> bool,
}

// The state of one drag at a time: whether there is one, what it carries, and which target it is over.
Controller :: struct {
	phase:    Phase,
	payload:  Payload,
	hover:    int, // the id of the target it is over, or -1
	hover_ok: bool, // and whether that target takes it
}

controller_init :: proc(c: ^Controller) {
	c^ = {}
	c.hover = -1
}

is_dragging :: proc(c: ^Controller) -> bool {
	return c.phase == .Dragging
}

// Starts a drag with `payload`. False if one is going already.
begin :: proc(c: ^Controller, payload: Payload) -> bool {
	if c.phase == .Dragging {
		return false
	}
	c.phase, c.payload, c.hover, c.hover_ok = .Dragging, payload, -1, false
	return true
}

// Says which target the drag is over now, or nil for none. Nothing changes when no drag is going.
set_hover :: proc(c: ^Controller, target: ^Target) {
	if c.phase != .Dragging {
		return
	}
	if target == nil {
		c.hover, c.hover_ok = -1, false
		return
	}
	c.hover = target.id
	c.hover_ok = target.can_accept == nil || target.can_accept(target.data, c.payload)
}

// Ends the drag where it is. `dropped` is true if it was over a target that takes it, and `target` is which; the
// owner makes the move. Otherwise nothing is dropped, which is a cancel. Either way the controller is idle again.
end :: proc(c: ^Controller) -> (payload: Payload, target: int, dropped: bool) {
	if c.phase != .Dragging {
		return {}, -1, false
	}
	payload, target, dropped = c.payload, c.hover, c.hover >= 0 && c.hover_ok
	controller_init(c)
	return
}

// Ends the drag with nothing dropped.
cancel :: proc(c: ^Controller) {
	controller_init(c)
}
