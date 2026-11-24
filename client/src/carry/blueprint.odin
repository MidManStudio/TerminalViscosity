// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "blueprint.odin"
// ============================================================================

package carry

import "../inventory"
import "../lab"

// A station that is being carried, as a see-through copy of itself that follows the crosshair and is put down where
// it can stand. It is made by picking up a station that stands on a counter, or by choosing one in the bag. While it
// is carried the station is in neither place, so it cannot be in two. Every frame it is aimed at the counter under the
// crosshair, fitted to it, and checked, so that the screen can show it red when it cannot be put down and why.

BLUEPRINT_FLOAT :: f32(1.0) // how far in front of the player the copy floats when the crosshair is on no counter
BLUEPRINT_FAR :: f32(6) // how far along the crosshair the counter plane is looked for

Blueprint_Problem :: enum u8 {
	None,
	Out_Of_Reach, // the crosshair is on a counter that is too far to put it on, or on no counter plane at all
	Off_Counter, // not wholly on a counter
	Blocked_By_Fixture,
	Blocked_By_Station,
	Blocked_By_Vessel,
	Too_Many, // as many stations stand as the lab can have
}

// Where the station came from, so that it can go back.
Blueprint_Origin :: enum u8 {
	None,
	Placed, // from a counter
	Bag, // from a slot of the bag
}

Blueprint :: struct {
	active:  bool,
	kind:    lab.Station_Kind,
	quarter: u8, // the quarter turns it has now
	x, z:    f32, // the middle of the copy, on the counter plane
	ok:      bool, // it can be put down where it is
	problem: Blueprint_Problem, // why it cannot, when it cannot
	origin:  Blueprint_Origin,
	from:    lab.Placement, // where it stood, for a station that came from a counter
	slot:    int, // the slot of the bag that it came out of, for one that came from there
}

// What came of putting a carried station back.
Cancel_Result :: enum u8 {
	Nothing, // nothing was carried
	Put_Back, // it stands where it was picked up
	In_Bag, // it is in the bag
	No_Room, // it could go nowhere: it is still carried
}

// Starts carrying station `index` of those that stand: it leaves the counter and becomes the copy, at the place and
// turn it had. False, with nothing changed, if there is no such station, one is already carried, or the hands are full.
blueprint_pick_up :: proc(bp: ^Blueprint, props: ^Props, index: int) -> bool {
	if bp.active || props.held != -1 || index < 0 || index >= props.placed.count {
		return false
	}
	pl := lab.placed_remove(&props.placed, index)
	bp^ = {
		active  = true,
		kind    = pl.kind,
		quarter = pl.quarter,
		x       = pl.x,
		z       = pl.z,
		origin  = .Placed,
		from    = pl,
		slot    = -1,
	}
	return true
}

// Starts carrying the station in slot `slot` of the bag: it leaves the bag and becomes the copy, not turned. False,
// with nothing changed, if the slot holds no station, one is already carried, or the hands are full.
blueprint_take_from_bag :: proc(bp: ^Blueprint, props: ^Props, bag: ^inventory.Container, slot: int) -> bool {
	if bp.active || props.held != -1 || slot < 0 || slot >= bag.size {
		return false
	}
	kind := item_station(bag.slots[slot].item)
	if kind == .None {
		return false
	}
	if _, ok := inventory.take(bag, slot, 1); !ok {
		return false
	}
	bp^ = {
		active = true,
		kind   = kind,
		origin = .Bag,
		slot   = slot,
	}
	return true
}

// Turns the copy a quarter.
blueprint_rotate :: proc(bp: ^Blueprint) {
	if bp.active {
		bp.quarter = (bp.quarter + 1) % 4
	}
}

// Whether a vessel is in the way of a station of this kind put down here: its middle is within the footprint and a
// radius of the vessel to spare, and it is on the counter or higher, not on the floor. A vessel in the hands is not.
vessel_in_way :: proc(props: ^Props, kind: lab.Station_Kind, x, z: f32, quarter: u8) -> bool {
	body := lab.shift_rect(lab.turn_rect(lab.station_body(kind), quarter), x, z)
	for i in 0 ..< props.count {
		if i == props.held {
			continue
		}
		pr := props.items[i]
		r := kind_dims(pr.kind).radius
		wide := lab.Rect{body.min_x - r, body.min_z - r, body.max_x + r, body.max_z + r}
		if lab.in_rect(wide, pr.pos.x, pr.pos.z) && pr.pos.y >= lab.COUNTER_HEIGHT - 0.01 {
			return true
		}
	}
	return false
}

// Whether a station of this kind, turned this far, can be put down at (x, z), and if not why: no room for another, not
// on a counter, a fixture or a station in the way, or a vessel in the way.
station_problem :: proc(props: ^Props, kind: lab.Station_Kind, x, z: f32, quarter: u8) -> Blueprint_Problem {
	if props.placed.count >= lab.MAX_PLACED {
		return .Too_Many
	}
	switch lab.can_place(&props.placed, kind, x, z, quarter) {
	case .None:
	case .Off_Counter:
		return .Off_Counter
	case .Blocked_By_Fixture:
		return .Blocked_By_Fixture
	case .Blocked_By_Station:
		return .Blocked_By_Station
	}
	if vessel_in_way(props, kind, x, z, quarter) {
		return .Blocked_By_Vessel
	}
	return .None
}

// Moves the copy to where the crosshair is and checks it. The crosshair is followed to the plane of the counter tops;
// where it meets the plane is where the middle of the station goes, fitted to the counter that is there. A crosshair
// that is level or up meets no plane, and then the copy floats in front of the player. Too far to reach is a problem
// of its own and comes before the others.
blueprint_aim :: proc(bp: ^Blueprint, props: ^Props, v: View) {
	if !bp.active {
		return
	}
	dir := -v.back
	t := f32(-1)
	if dir.y < -1e-4 {
		t = (lab.COUNTER_HEIGHT - v.eye.y) / dir.y
	}
	if t <= 0 {
		flat := Vec3{dir.x, 0, dir.z}
		n := sqrt_f32(dot(flat, flat))
		if n < 1e-4 {
			flat, n = {0, 0, -1}, 1
		}
		bp.x = lab.snap_place(v.eye.x + flat.x / n * BLUEPRINT_FLOAT)
		bp.z = lab.snap_place(v.eye.z + flat.z / n * BLUEPRINT_FLOAT)
		bp.problem, bp.ok = .Out_Of_Reach, false
		return
	}
	t = min(t, BLUEPRINT_FAR)
	bp.x, bp.z, _ = lab.fit_to_zone(bp.kind, bp.quarter, v.eye.x + dir.x * t, v.eye.z + dir.z * t)
	bp.problem = station_problem(props, bp.kind, bp.x, bp.z, bp.quarter)
	if t > REACH {
		bp.problem = .Out_Of_Reach
	}
	bp.ok = bp.problem == .None
}

// Puts the copy down where it is, as a station that stands. False, with nothing changed, if it cannot stand there.
blueprint_place :: proc(bp: ^Blueprint, props: ^Props) -> bool {
	if !bp.active || bp.kind == .None || !bp.ok || station_problem(props, bp.kind, bp.x, bp.z, bp.quarter) != .None {
		return false
	}
	if !lab.placed_add(&props.placed, {bp.kind, bp.x, bp.z, bp.quarter}) {
		return false
	}
	bp^ = {}
	return true
}

// Puts the copy back: where it stood, if it came from a counter and that place is still free, and otherwise in the
// bag, in the slot it came from if that is free. If the bag has no room either, the copy is still carried and the
// player puts it down somewhere.
blueprint_cancel :: proc(bp: ^Blueprint, props: ^Props, bag: ^inventory.Container) -> Cancel_Result {
	if !bp.active {
		return .Nothing
	}
	if bp.origin == .Placed && station_problem(props, bp.from.kind, bp.from.x, bp.from.z, bp.from.quarter) == .None {
		if lab.placed_add(&props.placed, bp.from) {
			bp^ = {}
			return .Put_Back
		}
	}
	item := station_item(bp.kind)
	if (bp.origin == .Bag && inventory.put(bag, bp.slot, item, 1)) || inventory.add(bag, item, 1) == 1 {
		bp^ = {}
		return .In_Bag
	}
	return .No_Room
}

// What the line under the crosshair says about the copy.
blueprint_words :: proc(problem: Blueprint_Problem) -> string {
	switch problem {
	case .None:
		return "put it down here"
	case .Out_Of_Reach:
		return "too far: go closer"
	case .Off_Counter:
		return "it has to go on a counter"
	case .Blocked_By_Fixture:
		return "something fixed is in the way"
	case .Blocked_By_Station:
		return "another station is in the way"
	case .Blocked_By_Vessel:
		return "a vessel is in the way"
	case .Too_Many:
		return "no room for another station"
	}
	return ""
}
