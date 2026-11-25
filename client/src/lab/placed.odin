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
// bath or a scale. It stands on a counter, at any place on it where there is room, turned a quarter at a time, and
// everything that depends on it, the heat of the plate, the cold of the bath, the weighing of the scale and the
// height of its plate, reads where it stands and not a place that is fixed. Units are metres.

MAX_PLACED :: 8 // the most stations that stand in the lab at once
PLACE_GRID :: f32(0.05) // a station is put on a grid of this size
PLACE_EPS :: f32(1e-4) // how much two edges may differ and still touch

Station_Kind :: enum u8 {
	None,
	Hot_Plate,
	Ice_Bath,
	Scale,
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

// The stations as the lab starts: the hot plate, the ice bath and the scale on the north counter, where they have
// always been. The scale stands at z -7.625 so that its plate is the old `SCALE_PLATE`.
default_placed :: proc() -> Placed {
	p: Placed
	p.items[0] = {.Hot_Plate, -3.5, -7.63, 0}
	p.items[1] = {.Ice_Bath, -2.4, -7.63, 0}
	p.items[2] = {.Scale, 0.0, -7.625, 0}
	p.count = 3
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
	case .None:
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
	case .None:
	}
	return 0
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

// Whether the point (x, z) is on the plate of a station of this kind, wherever one stands.
on_station :: proc(p: ^Placed, kind: Station_Kind, x, z: f32) -> bool {
	for i in 0 ..< p.count {
		if p.items[i].kind == kind && in_rect(world_plate(p.items[i]), x, z) {
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

KEEPOUT_COUNT :: 7 + VIAL_RACK_COUNT

// The floor that the fixtures of the lab take up on the counters, with a hand's width to spare: the sink and its soap,
// the fume hood, the oven with its spout and tray, the fill station, the paint station with its palette, tablet and
// brushes, the incinerator, the loadout rack and the vial racks. What is on a wall and over the heads of the stations,
// the first aid cabinet and the shelves, takes up no counter and is not here. A station may not be put inside any of
// these.
fixture_keepouts :: proc() -> [KEEPOUT_COUNT]Rect {
	k: [KEEPOUT_COUNT]Rect
	k[0] = {-12, SINK_BASIN.min_z - 0.1, SINK_BASIN.max_x + 0.1, SOAP_AT.z + 0.1}
	k[1] = {HOOD.min_x - 0.1, HOOD.min_z, HOOD.max_x + 0.1, HOOD.max_z}
	k[2] = {MIXER.min_x - 0.05, MIXER.min_z - 0.04, MIXER_SPOUT.x + MIXER_TRAY_RADIUS + 0.05, MIXER.max_z + 0.04}
	k[3] = {FILLER_CLAMP.x - 0.25, 7.28, GAUGE_ORIGIN.x + 0.2, 7.98}
	k[4] = {-11.98, TABLET_CENTER.z - TABLET_W * 0.5 - 0.1, -11.28, PAINT_CLAMP.z + 1.05 + 0.15}
	k[5] = {INCINERATOR.min_x - 0.1, 7.28, INCINERATOR.max_x + 0.1, 7.98}
	k[6] = {SLOT_FIRST_X - 0.35, 7.28, SLOT_FIRST_X + SLOT_SPACING * f32(LOADOUT_SLOTS - 1) + 0.35, 7.98}
	racks := VIAL_RACKS
	for r, i in racks {
		k[7 + i] = {r.x - 0.25, r.z - 0.15, r.x + 0.25, r.z + 0.15}
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
	lo_x, hi_x := grid_ceil(zone.min_x - body.min_x), grid_floor(zone.max_x - body.max_x)
	lo_z, hi_z := grid_ceil(zone.min_z - body.min_z), grid_floor(zone.max_z - body.max_z)
	if lo_x > hi_x || lo_z > hi_z {
		return fx, fz, false
	}
	return clamp(fx, lo_x, hi_x), clamp(fz, lo_z, hi_z), true
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
		l.xform = {true, pl.x, pl.z, pl.quarter}
		switch pl.kind {
		case .Hot_Plate:
			add_hot_plate(l, station_plate(.Hot_Plate))
		case .Ice_Bath:
			add_ice_bath(l, station_plate(.Ice_Bath))
		case .Scale:
			add_scale(l, station_plate(.Scale))
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
