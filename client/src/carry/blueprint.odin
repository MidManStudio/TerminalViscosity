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
	Too_Big, // the crosshair is on a counter that the station does not fit at this turn
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
	Hotbar, // from a slot of the bar along the bottom of the screen
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
	slot:    int, // the slot of the bag or of the bar that it came out of, for one that came from there
}

// What came of putting a carried station back.
Cancel_Result :: enum u8 {
	Nothing, // nothing was carried
	Put_Back, // it stands where it was picked up
	In_Bag, // it is in the bag
	In_Bar, // it is in the bar
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

// Starts carrying the station in slot `slot` of a container, the bag or the bar, which `origin` says: it leaves the
// container and becomes the copy, not turned. False, with nothing changed, if the slot holds no station, one is already
// carried, or the hands are full.
blueprint_take_from :: proc(bp: ^Blueprint, props: ^Props, c: ^inventory.Container, slot: int, origin: Blueprint_Origin) -> bool {
	if bp.active || props.held != -1 || slot < 0 || slot >= c.size {
		return false
	}
	kind := item_station(c.slots[slot].item)
	if kind == .None {
		return false
	}
	if _, ok := inventory.take(c, slot, 1); !ok {
		return false
	}
	bp^ = {
		active = true,
		kind   = kind,
		origin = origin,
		slot   = slot,
	}
	return true
}

// The same for the bag.
blueprint_take_from_bag :: proc(bp: ^Blueprint, props: ^Props, bag: ^inventory.Container, slot: int) -> bool {
	return blueprint_take_from(bp, props, bag, slot, .Bag)
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
	blueprint_aim_ray(bp, props, v.eye, -v.back)
}

// The same along any ray from the eye, such as the one through a finger on the screen.
blueprint_aim_ray :: proc(bp: ^Blueprint, props: ^Props, eye, direction: Vec3) {
	if !bp.active {
		return
	}
	dir := direction
	t := f32(-1)
	if dir.y < -1e-4 {
		t = (lab.COUNTER_HEIGHT - eye.y) / dir.y
	}
	if t <= 0 {
		flat := Vec3{dir.x, 0, dir.z}
		n := sqrt_f32(dot(flat, flat))
		if n < 1e-4 {
			flat, n = {0, 0, -1}, 1
		}
		bp.x = lab.snap_place(eye.x + flat.x / n * BLUEPRINT_FLOAT)
		bp.z = lab.snap_place(eye.z + flat.z / n * BLUEPRINT_FLOAT)
		bp.problem, bp.ok = .Out_Of_Reach, false
		return
	}
	t = min(t, BLUEPRINT_FAR)
	hit_x, hit_z := eye.x + dir.x * t, eye.z + dir.z * t
	bp.x, bp.z, _ = lab.fit_to_zone(bp.kind, bp.quarter, hit_x, hit_z)
	bp.problem = station_problem(props, bp.kind, bp.x, bp.z, bp.quarter)
	if bp.problem == .Off_Counter && lab.zone_at(hit_x, hit_z) != -1 {
		bp.problem = .Too_Big // the crosshair is on a counter and the station is still off it, so it does not fit it this way round
	}
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

// Puts the copy back: where it stood, if it came from a counter and that place is still free, in its slot of the bar if
// it came from there and that is free, and otherwise in the bag, in the slot it came from if that is free, and then in
// the bar, which may be left out. If there is no room anywhere, the copy is still carried and the player puts it down
// somewhere.
blueprint_cancel :: proc(bp: ^Blueprint, props: ^Props, bag: ^inventory.Container, hotbar: ^inventory.Container = nil) -> Cancel_Result {
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
	if hotbar != nil && bp.origin == .Hotbar && inventory.put(hotbar, bp.slot, item, 1) {
		bp^ = {}
		return .In_Bar
	}
	if (bp.origin == .Bag && inventory.put(bag, bp.slot, item, 1)) || inventory.add(bag, item, 1) == 1 {
		bp^ = {}
		return .In_Bag
	}
	if hotbar != nil && inventory.add(hotbar, item, 1) == 1 {
		bp^ = {}
		return .In_Bar
	}
	return .No_Room
}

// Puts the copy into the bar: in slot `slot` if that is free, in the first free slot of the bar if not, and in the bag if
// the bar is full. If there is no room anywhere, the copy is still carried.
blueprint_stow :: proc(bp: ^Blueprint, bag, hotbar: ^inventory.Container, slot: int) -> Cancel_Result {
	if !bp.active {
		return .Nothing
	}
	item := station_item(bp.kind)
	if inventory.put(hotbar, slot, item, 1) || inventory.add(hotbar, item, 1) == 1 {
		bp^ = {}
		return .In_Bar
	}
	if inventory.add(bag, item, 1) == 1 {
		bp^ = {}
		return .In_Bag
	}
	return .No_Room
}

// The direction of the ray through a point of the screen, for a view that is `tan_half` wide to a side of the middle
// of the screen in the vertical direction, and `aspect` times as wide as high. (nx, ny) is the point from -1 to 1
// across and up the screen, with the middle at (0, 0).
view_ray :: proc(v: View, nx, ny, tan_half, aspect: f32) -> Vec3 {
	d := -v.back + v.right * (nx * tan_half * aspect) + v.up * (ny * tan_half)
	return d / sqrt_f32(dot(d, d))
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
	case .Too_Big:
		return "too big for this counter: try turning it"
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
