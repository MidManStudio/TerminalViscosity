// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "placed.odin"
// ============================================================================

package lab

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

// The stations that can be picked up and put down again, and where they stand. A station is a hot plate, an ice
// bath, a scale, the incinerator, the fume hood, the balloon filler or the reaction oven. It stands on a counter, at any place on it where there is room, turned a quarter at a time, and
// everything that depends on it, the heat of the plate, the cold of the bath, the weighing of the scale and the
// height of its plate, reads where it stands and not a place that is fixed. Units are metres.

MAX_PLACED :: 12 // the most stations that stand in the lab at once
PLACE_GRID :: f32(0.05) // a station is put on a grid of this size
PLACE_EPS :: f32(1e-4) // how much two edges may differ and still touch

Station_Kind :: enum u8 {
	None,
	Hot_Plate,
	Ice_Bath,
	Scale,
	Incinerator,
	Hood,
	Filler,
	Oven,
}

// One station standing: what it is, where the middle of it is, and how many quarter turns it has been turned from
// the way it is made, which has the display of the scale toward +z.
Placement :: struct {
	kind:    Station_Kind,
	x, z:    f32,
	quarter: u8,
}

// The stations that stand in the lab. The first `count` of `items` are in use, and the others are always zero.
Placed :: struct {
	items: [MAX_PLACED]Placement,
	count: int,
}

// Why a station cannot be put down where it is: it is not wholly on a counter, it is in the way of a fixture of the
// lab, or it is in the way of another station.
Place_Problem :: enum u8 {
	None,
	Off_Counter,
	Blocked_By_Fixture,
	Blocked_By_Station,
}

// The stations as the lab starts: the hot plate, the ice bath and the scale on the north counter, and the incinerator
// on the south counter, the fume hood on the north counter, the balloon filler on the south counter and the reaction
// oven on the north counter, where they have always been. The scale stands at z -7.625 so that its plate is the old `SCALE_PLATE`.
default_placed :: proc() -> Placed {
	p: Placed
	p.items[0] = {.Hot_Plate, -3.5, -7.63, 0}
	p.items[1] = {.Ice_Bath, -2.4, -7.63, 0}
	p.items[2] = {.Scale, 0.0, -7.625, 0}
	p.items[3] = {.Incinerator, 10.5, 7.63, 0}
	p.items[4] = {.Hood, -6.0, -7.63, 0}
	p.items[5] = FILLER_START
	p.items[6] = OVEN_START
	p.count = 7
	return p
}

// Adds a station. False, with nothing changed, if it is no station or there is no room for another.
placed_add :: proc(p: ^Placed, pl: Placement) -> bool {
	if pl.kind == .None || p.count >= MAX_PLACED {
		return false
	}
	p.items[p.count] = pl
	p.count += 1
	return true
}

// Takes station `i` away and gives it back. The ones after it move up one place, and the place that was the last is
// cleared. An `i` that is not a station gives a station of no kind and changes nothing.
placed_remove :: proc(p: ^Placed, i: int) -> Placement {
	if i < 0 || i >= p.count {
		return {}
	}
	gone := p.items[i]
	for k in i ..< p.count - 1 {
		p.items[k] = p.items[k + 1]
	}
	p.items[p.count - 1] = {}
	p.count -= 1
	return gone
}

// ---- Footprints, as the station is made, round its middle ----

// What a vessel's middle has to be inside to stand on a station of this kind: for a scale it is the plate, and for
// the others the whole top.
station_plate :: proc(kind: Station_Kind) -> Rect {
	switch kind {
	case .Hot_Plate:
		return {-0.3, -0.25, 0.3, 0.25}
	case .Ice_Bath:
		return {-0.4, -0.25, 0.4, 0.25}
	case .Scale:
		return {-0.2, -0.175, 0.2, 0.175}
	case .Hood:
		return {-0.8, -0.35, 0.8, 0.35} // the floor inside it
	case .Incinerator, .Filler, .Oven, .None: // no vessel stands on these
	}
	return {}
}

// What a station takes up on the counter, rim, body and display included: no other station and no fixture may be
// inside it. It is the same all round, so that turning the station does not change which side the room is on.
station_body :: proc(kind: Station_Kind) -> Rect {
	switch kind {
	case .Hot_Plate:
		return {-0.3, -0.25, 0.3, 0.25}
	case .Ice_Bath:
		return {-0.43, -0.28, 0.43, 0.28}
	case .Scale:
		return {-0.26, -0.25, 0.26, 0.25}
	case .Incinerator:
		return {-0.32, -0.23, 0.32, 0.23}
	case .Hood:
		return {-0.85, -0.35, 0.85, 0.35} // the sides stand outside the floor
	case .Filler:
		return {-0.25, -0.26, 0.4, 0.25} // the base plate, the pole, the arm and the gauge, with room for the balloon
	case .Oven:
		return {-0.8, -0.31, 1.14, 0.32} // the box, and the spout over its tray off the right end
	case .None:
	}
	return {}
}

// How high a station stands over the counter.
station_height :: proc(kind: Station_Kind) -> f32 {
	switch kind {
	case .Hot_Plate:
		return 0.07
	case .Ice_Bath:
		return 0.09
	case .Scale:
		return 0.22
	case .Incinerator:
		return 0.62
	case .Hood:
		return HOOD_TOP - COUNTER_HEIGHT
	case .Filler:
		return 0.64
	case .Oven:
		return 0.6
	case .None:
	}
	return 0
}

// How high the highest part of a station reaches, in metres over the floor: what has to clear the things that hang over
// the counters. The incinerator reaches the top of its chimney and the hood the top of its roof, which are over the
// part that `station_height` gives, and that part is only what the crosshair is aimed at.
station_top :: proc(kind: Station_Kind) -> f32 {
	switch kind {
	case .Incinerator:
		return INCINERATOR_VENT.y + 0.04
	case .Hood:
		return HOOD_TOP + 0.08
	case .Filler:
		return 1.75
	case .Oven:
		return 1.7
	case .Hot_Plate, .Ice_Bath, .Scale:
		return COUNTER_HEIGHT + station_height(kind)
	case .None:
	}
	return COUNTER_HEIGHT
}

// A rectangle turned about the origin by `quarter` quarter turns. It is still a rectangle with its sides along the
// axes: a quarter turn swaps its width and its depth.
turn_rect :: proc(r: Rect, quarter: u8) -> Rect {
	x0, z0 := turn_xz(r.min_x, r.min_z, quarter)
	x1, z1 := turn_xz(r.max_x, r.max_z, quarter)
	return {min(x0, x1), min(z0, z1), max(x0, x1), max(z0, z1)}
}

shift_rect :: proc(r: Rect, x, z: f32) -> Rect {
	return {r.min_x + x, r.min_z + z, r.max_x + x, r.max_z + z}
}

// Where the plate of a station is in the lab, and where its body is.
world_plate :: proc(pl: Placement) -> Rect {
	return shift_rect(turn_rect(station_plate(pl.kind), pl.quarter), pl.x, pl.z)
}

world_body :: proc(pl: Placement) -> Rect {
	return shift_rect(turn_rect(station_body(pl.kind), pl.quarter), pl.x, pl.z)
}

// Whether a station of this kind has a plate that a vessel can stand on. The incinerator has none.
station_has_plate :: proc(kind: Station_Kind) -> bool {
	return kind == .Hot_Plate || kind == .Ice_Bath || kind == .Scale || kind == .Hood
}

// A point given round the middle of a station as it is made, with the display of the scale toward +z, is where it is
// in the lab once the station stands at `pl`: turned the quarters it is turned, and moved to where it stands.
station_point :: proc(pl: Placement, local: Vec3) -> Vec3 {
	ox, oz := station_origin(pl.kind)
	x, z := turn_xz(local.x - ox, local.z - oz, pl.quarter)
	return {x + pl.x, local.y, z + pl.z}
}

// The place a station is made at, which the numbers of its geometry are given round: the middle of the station for
// the ones that were made to be moved, and the place where the lab starts it for the filler and the oven, whose
// constants were written as places in the lab. A placement turns the station about this point and puts it where the
// placement says, so that a station at the place it starts is where the constants say.
station_origin :: proc(kind: Station_Kind) -> (x, z: f32) {
	switch kind {
	case .Filler:
		return FILLER_START.x, FILLER_START.z
	case .Oven:
		return OVEN_START.x, OVEN_START.z
	case .Hot_Plate, .Ice_Bath, .Scale, .Incinerator, .Hood, .None:
	}
	return 0, 0
}

// The other way: a point of the lab, as it is for a station standing at `pl`, given as it would be for the station
// as it is made. What a station does with the world is worked out in that frame.
station_to_start :: proc(pl: Placement, world: Vec3) -> Vec3 {
	ox, oz := station_origin(pl.kind)
	x, z := turn_xz(world.x - pl.x, world.z - pl.z, (4 - pl.quarter % 4) % 4)
	return {x + ox, world.y, z + oz}
}

// A direction turned the same way: the turn and no move.
station_dir_to_start :: proc(pl: Placement, dir: Vec3) -> Vec3 {
	x, z := turn_xz(dir.x, dir.z, (4 - pl.quarter % 4) % 4)
	return {x, dir.y, z}
}

// The size of a flat thing that faces the way the station was made, as it is for a station turned `quarter` quarters:
// a quarter turn swaps its width and its depth.
station_size :: proc(pl: Placement, size: Vec3) -> Vec3 {
	if pl.quarter % 2 == 1 {
		return {size.z, size.y, size.x}
	}
	return size
}

// The first station of this kind that stands, and whether there is one.
placed_find :: proc(p: ^Placed, kind: Station_Kind) -> (pl: Placement, found: bool) {
	for i in 0 ..< p.count {
		if p.items[i].kind == kind {
			return p.items[i], true
		}
	}
	return {}, false
}

// How many stations of this kind stand.
placed_count_of :: proc(p: ^Placed, kind: Station_Kind) -> int {
	n := 0
	for i in 0 ..< p.count {
		if p.items[i].kind == kind {
			n += 1
		}
	}
	return n
}

// Whether the point (x, z) is on the plate of a station of this kind, wherever one stands.
on_station :: proc(p: ^Placed, kind: Station_Kind, x, z: f32) -> bool {
	for i in 0 ..< p.count {
		if p.items[i].kind == kind && station_has_plate(kind) && in_rect(world_plate(p.items[i]), x, z) {
			return true
		}
	}
	return false
}

// The box that the crosshair is tested against for a station: its body, and as high as the station is.
station_aim_box :: proc(pl: Placement) -> (low, high: Vec3) {
	b := world_body(pl)
	return {b.min_x, COUNTER_HEIGHT, b.min_z}, {b.max_x, COUNTER_HEIGHT + station_height(pl.kind), b.max_z}
}

// ---- Where a station may stand ----

PLACE_ZONES :: 4

// The counters that stations stand on: along the north, south and west walls, and the island. The counter of the
// bottle wall is not one, because vessels stand there under the taps.
place_zones :: proc() -> [PLACE_ZONES]Rect {
	a := counter_areas()
	return {a[COUNTER_NORTH], a[COUNTER_SOUTH], a[COUNTER_WEST], a[COUNTER_ISLAND]}
}

KEEPOUT_COUNT :: 3 + VIAL_RACK_COUNT

// The floor that the fixtures of the lab take up on the counters, with a hand's width to spare: the sink and its soap,
// the paint station with its palette, tablet and
// brushes, the loadout rack and the vial racks. What is on a wall and over the heads of the stations,
// the first aid cabinet and the shelves, takes up no counter and is not here. A station may not be put inside any of
// these.
fixture_keepouts :: proc() -> [KEEPOUT_COUNT]Rect {
	k: [KEEPOUT_COUNT]Rect
	k[0] = {-12, SINK_BASIN.min_z - 0.1, SINK_BASIN.max_x + 0.1, SOAP_AT.z + 0.1}
	k[1] = {-11.98, TABLET_CENTER.z - TABLET_W * 0.5 - 0.1, -11.28, PAINT_CLAMP.z + 1.05 + 0.15}
	k[2] = {SLOT_FIRST_X - 0.35, 7.28, SLOT_FIRST_X + SLOT_SPACING * f32(LOADOUT_SLOTS - 1) + 0.35, 7.98}
	racks := VIAL_RACKS
	for r, i in racks {
		k[3 + i] = {r.x - 0.25, r.z - 0.15, r.x + 0.25, r.z + 0.15}
	}
	return k
}

// Whether `inner` is wholly inside `outer`, edges touching included.
rect_inside :: proc(outer, inner: Rect) -> bool {
	return inner.min_x >= outer.min_x - PLACE_EPS && inner.max_x <= outer.max_x + PLACE_EPS && inner.min_z >= outer.min_z - PLACE_EPS && inner.max_z <= outer.max_z + PLACE_EPS
}

// Whether two rectangles share floor. Touching edges do not count.
rects_intersect :: proc(a, b: Rect) -> bool {
	return a.min_x < b.max_x - PLACE_EPS && b.min_x < a.max_x - PLACE_EPS && a.min_z < b.max_z - PLACE_EPS && b.min_z < a.max_z - PLACE_EPS
}

// Something that hangs over a counter: the floor under it, and how high its lowest part is over the floor. A station
// whose highest part reaches above `bottom` may not stand where `area` is, and a lower one may stand under it.
Overhead :: struct {
	area:   Rect,
	bottom: f32,
}

OVERHEAD_COUNT :: 2

// What hangs over the counters: the first aid cabinet on the north wall, and the shelves along the south wall with the
// bottles on them. The brackets of the shelves are the lowest part of them.
overhead_keepouts :: proc() -> [OVERHEAD_COUNT]Overhead {
	return {
		{{FIRST_AID_AIM_LOW.x, FIRST_AID_AIM_LOW.z, FIRST_AID_AIM_HIGH.x, FIRST_AID_AIM_HIGH.z}, FIRST_AID_AIM_LOW.y},
		{{SHELF_X0 - 0.25, SHELF_Z - SHELF_DEPTH * 0.5, SHELF_X1 + 0.25, SHELF_Z + SHELF_DEPTH * 0.5 + 0.1}, SHELF_HEIGHTS[0] - 0.2},
	}
}

// Whether a station of `kind`, turned `quarter` quarters, with its middle at (x, z), may be put down: wholly on one
// counter, clear of the fixtures, and clear of the stations that already stand. A vessel in the way is for the
// carrying code to say, because only it knows where the vessels are.
can_place :: proc(p: ^Placed, kind: Station_Kind, x, z: f32, quarter: u8) -> Place_Problem {
	if kind == .None {
		return .Off_Counter
	}
	body := shift_rect(turn_rect(station_body(kind), quarter), x, z)
	on_counter := false
	for zone in place_zones() {
		if rect_inside(zone, body) {
			on_counter = true
			break
		}
	}
	if !on_counter {
		return .Off_Counter
	}
	for keep in fixture_keepouts() {
		if rects_intersect(keep, body) {
			return .Blocked_By_Fixture
		}
	}
	top := station_top(kind)
	for over in overhead_keepouts() {
		if top > over.bottom && rects_intersect(over.area, body) {
			return .Blocked_By_Fixture
		}
	}
	for i in 0 ..< p.count {
		if rects_intersect(world_body(p.items[i]), body) {
			return .Blocked_By_Station
		}
	}
	return .None
}

// A position rounded to the grid, in whole millimetres so that it is the same after it is written and read back.
snap_place :: proc(v: f32) -> f32 {
	return f32(int(math.round(v / PLACE_GRID)) * 50) / 1000
}

// The nearest place of the grid at or over `v`, and the nearest at or under it.
grid_ceil :: proc(v: f32) -> f32 {
	return f32(int(math.ceil(v / PLACE_GRID - 0.001)) * 50) / 1000
}

grid_floor :: proc(v: f32) -> f32 {
	return f32(int(math.floor(v / PLACE_GRID + 0.001)) * 50) / 1000
}

// How far past the edge of a counter the crosshair may be and still count as on it: the top of a counter overhangs
// its floor a little.
COUNTER_REACH_PAST :: f32(0.04)

// The number of the counter, among `place_zones`, that the point (x, z) on the counter plane is on, with a little to
// spare past its edge, or -1 if it is on none.
zone_at :: proc(x, z: f32) -> int {
	zones := place_zones()
	for zone, i in zones {
		if x >= zone.min_x - COUNTER_REACH_PAST && x <= zone.max_x + COUNTER_REACH_PAST && z >= zone.min_z - COUNTER_REACH_PAST && z <= zone.max_z + COUNTER_REACH_PAST {
			return i
		}
	}
	return -1
}

// Where the middle of a station goes when the crosshair is at (x, z) on the counter plane: the point rounded to the
// grid, and then moved in just far enough that the whole station is on the counter the point is on, so that a
// counter that is not much deeper than the station can be aimed at without care. `on_counter` is false when the
// point is on no counter, or the station does not fit the counter at all, and then the point is only rounded. Which of
// the two it is, `zone_at` says.
fit_to_zone :: proc(kind: Station_Kind, quarter: u8, x, z: f32) -> (fx, fz: f32, on_counter: bool) {
	fx, fz = snap_place(x), snap_place(z)
	index := zone_at(x, z)
	if index == -1 {
		return fx, fz, false
	}
	zone := place_zones()[index]
	body := turn_rect(station_body(kind), quarter)
	x_fits, z_fits: bool
	fx, x_fits = fit_axis(zone.min_x - body.min_x, zone.max_x - body.max_x, fx)
	fz, z_fits = fit_axis(zone.min_z - body.min_z, zone.max_z - body.max_z, fz)
	return fx, fz, x_fits && z_fits
}

// One axis of `fit_to_zone`: the middle of the body may be anywhere from `lo` to `hi` for the body to be inside the
// counter. The grid point nearest to `v` in that range is the answer. A body as deep as the counter has no room for
// the grid, and then the one place it fits is the answer, in whole millimetres. False when it does not fit at all.
fit_axis :: proc(lo, hi, v: f32) -> (f32, bool) {
	if lo > hi + PLACE_EPS {
		return v, false
	}
	grid_lo, grid_hi := grid_ceil(lo), grid_floor(hi)
	if grid_lo > grid_hi {
		return math.round((lo + hi) * 0.5 * 1000) / 1000, true
	}
	return clamp(v, grid_lo, grid_hi), true
}

// ---- Writing and reading ----

// The lines that say where the stations stand, to go after the containers in the file of the stock: `placedset` and
// how many, and for each a `placed` line with the kind as a number, the middle in millimetres, and the quarter turns.
// A file that has no `placedset` line says nothing about stations, which is how a file from before them looks.
placed_serialize :: proc(p: ^Placed, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "placedset %v\n", p.count)
	for i in 0 ..< p.count {
		pl := p.items[i]
		fmt.sbprintf(&b, "placed %v %v %v %v\n", int(pl.kind), int(math.round(pl.x * 1000)), int(math.round(pl.z * 1000)), int(pl.quarter))
	}
	return strings.to_string(b)
}

// Reads the lines `placed_serialize` wrote. `found` is whether there was a `placedset` line at all, and if there was
// not, nothing else is read. A `placed` line that cannot be read, or whose station cannot stand where it says given
// the ones before it, is not put in `p` and is counted in `rejected`, so that it can be put somewhere else and not lost.
placed_deserialize :: proc(text: string) -> (p: Placed, found: bool, rejected: [MAX_PLACED]Placement, rejected_count: int) {
	text := text
	for line in strings.split_lines_iterator(&text) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) == 2 && fields[0] == "placedset" {
			p, found, rejected, rejected_count = {}, true, {}, 0
			continue
		}
		if !found || len(fields) != 5 || fields[0] != "placed" {
			continue
		}
		kind, ok1 := strconv.parse_int(fields[1])
		x_mm, ok2 := strconv.parse_int(fields[2])
		z_mm, ok3 := strconv.parse_int(fields[3])
		quarter, ok4 := strconv.parse_int(fields[4])
		if !(ok1 && ok2 && ok3 && ok4) || kind < 1 || kind > int(max(Station_Kind)) || quarter < 0 || quarter > 3 || abs(x_mm) > 100000 || abs(z_mm) > 100000 {
			continue // nothing that is a station: there is nothing to keep
		}
		pl := Placement{Station_Kind(kind), f32(x_mm) / 1000, f32(z_mm) / 1000, u8(quarter)}
		if can_place(&p, pl.kind, pl.x, pl.z, pl.quarter) == .None && placed_add(&p, pl) {
			continue
		}
		if rejected_count < MAX_PLACED {
			rejected[rejected_count] = pl
			rejected_count += 1
		}
	}
	return
}

// ---- Building ----

// Adds the boxes of the stations, each where it stands and turned the way it is turned.
add_placed :: proc(l: ^Layout, p: Placed) {
	for i in 0 ..< p.count {
		pl := p.items[i]
		// The station is made at its origin, so that it is turned about that, and the move that goes with the turn is
		// where it stands less where its origin goes.
		ox, oz := station_origin(pl.kind)
		tx, tz := turn_xz(ox, oz, pl.quarter)
		l.xform = {true, pl.x - tx, pl.z - tz, pl.quarter}
		switch pl.kind {
		case .Hot_Plate:
			add_hot_plate(l, station_plate(.Hot_Plate))
		case .Ice_Bath:
			add_ice_bath(l, station_plate(.Ice_Bath))
		case .Scale:
			add_scale(l, station_plate(.Scale))
		case .Incinerator:
			add_incinerator(l)
		case .Hood:
			add_hood(l)
		case .Filler:
			add_filler(l)
		case .Oven:
			add_mixer(l)
		case .None:
		}
		l.xform = {}
	}
}

// The hot plate, built round the origin inside `h`: a dark plate and a glowing coil on it.
add_hot_plate :: proc(l: ^Layout, h: Rect) {
	cx, cz := (h.min_x + h.max_x) * 0.5, (h.min_z + h.max_z) * 0.5
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {h.max_x - h.min_x, 0.04, h.max_z - h.min_z}, {50, 54, 62, 255}, 0, 0.4)
	add_box(l, {cx, COUNTER_HEIGHT + 0.043, cz}, {h.max_x - h.min_x - 0.12, 0.012, h.max_z - h.min_z - 0.12}, {255, 96, 40, 255}, 1) // the coil, glowing
}

// The ice bath, built inside `b`: the pale floor of a tub, a rim round it, and lumps of ice.
add_ice_bath :: proc(l: ^Layout, b: Rect) {
	cx, cz := (b.min_x + b.max_x) * 0.5, (b.min_z + b.max_z) * 0.5
	w, d := b.max_x - b.min_x, b.max_z - b.min_z
	add_box(l, {cx, COUNTER_HEIGHT + 0.015, cz}, {w, 0.03, d}, {170, 214, 238, 255}, 0, 0.8) // the floor of the tub, pale blue
	rim := f32(0.07)
	add_box(l, {b.min_x - 0.015, COUNTER_HEIGHT + rim * 0.5, cz}, {0.03, rim, d + 0.06}, {120, 160, 190, 255}, 0, 0.6)
	add_box(l, {b.max_x + 0.015, COUNTER_HEIGHT + rim * 0.5, cz}, {0.03, rim, d + 0.06}, {120, 160, 190, 255}, 0, 0.6)
	add_box(l, {cx, COUNTER_HEIGHT + rim * 0.5, b.min_z - 0.015}, {w, rim, 0.03}, {120, 160, 190, 255}, 0, 0.6)
	add_box(l, {cx, COUNTER_HEIGHT + rim * 0.5, b.max_z + 0.015}, {w, rim, 0.03}, {120, 160, 190, 255}, 0, 0.6)
	// A few lumps of ice standing in it.
	add_box(l, {cx - 0.25, COUNTER_HEIGHT + 0.05, cz - 0.1}, {0.1, 0.04, 0.1}, {225, 240, 250, 255}, 0.3, 0.9)
	add_box(l, {cx + 0.28, COUNTER_HEIGHT + 0.05, cz + 0.12}, {0.09, 0.04, 0.12}, {225, 240, 250, 255}, 0.3, 0.9)
	add_box(l, {cx + 0.05, COUNTER_HEIGHT + 0.045, cz - 0.15}, {0.08, 0.03, 0.08}, {225, 240, 250, 255}, 0.3, 0.9)
}

// The scale, built round its plate `p`: a body, a steel plate, and a display on the front with its light.
add_scale :: proc(l: ^Layout, p: Rect) {
	cx, cz := (p.min_x + p.max_x) * 0.5, (p.min_z + p.max_z) * 0.5
	w, d := p.max_x - p.min_x, p.max_z - p.min_z
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {w + 0.1, 0.04, d + 0.1}, COLOR_METAL, 0, 0.5) // the body
	add_box(l, {cx, COUNTER_HEIGHT + SCALE_PLATE_TOP - 0.015, cz}, {w, 0.03, d}, COLOR_STEEL, 0, 0.9) // the plate
	add_box(l, {cx, COUNTER_HEIGHT + 0.025, p.max_z + 0.055}, {0.2, 0.035, 0.012}, {16, 20, 26, 255}, 0, 0.6) // the display, on the front
	add_box(l, {cx, COUNTER_HEIGHT + 0.025, p.max_z + 0.062}, {0.14, 0.012, 0.004}, COLOR_GLOW, 1) // and its light
}
