// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stock.odin"
// ============================================================================

package carry

import "../chemistry"
import "../inventory"
import "../lab"
import "core:strings"

BAG_SIZE :: 12 // slots in the bag

// What the player has to put in the lab: the bag, and the wall, which has a mount for each tap. A dispenser mounted on
// the wall gives its tap, and one in the bag does not. A station is in the bag or it stands on a counter, and where it
// stands is in `Props.placed`, not here.
Stock :: struct {
	bag:    inventory.Container,
	wall:   inventory.Container,
	hotbar: inventory.Container, // the bar along the bottom of the screen: stations that can be dragged out and put down
}

HOTBAR_SIZE :: 6 // the slots of the bar

// The wall as the lab starts: a dispenser of each of the chemicals the lab starts with except water, from the
// first mount on, and the other mounts empty. It takes only things that can be mounted.
wall_default :: proc(wall: ^inventory.Container) {
	inventory.container_init(wall, lab.DISPENSER_COUNT, {.Mountable})
	for i in 0 ..< min(STOCK_COUNT - WALL_FIRST + 1, lab.DISPENSER_COUNT) {
		inventory.put(wall, i, {.Dispenser, u16(i + WALL_FIRST)}, 1)
	}
}

stock_init :: proc(s: ^Stock) {
	inventory.container_init(&s.bag, BAG_SIZE)
	inventory.container_init(&s.hotbar, HOTBAR_SIZE, {.Benchable})
	wall_default(&s.wall)
}

// Sets the taps of the bottle wall from what is mounted on it: a dispenser with a compound in it gives that
// compound, and any other mount, empty or with a dispenser that has nothing in it, gives nothing. The faucet of the
// sink is not on the wall and is left as it is.
station_sync :: proc(st: ^Station, wall: ^inventory.Container) {
	for i in 0 ..< lab.DISPENSER_COUNT {
		st.items[i] = {}
		if i < wall.size {
			s := wall.slots[i]
			if s.count > 0 && s.item.kind == .Dispenser && chemistry.compound_of(chemistry.Id(s.item.arg)) != nil {
				st.items[i] = {compound = s.item.arg, unlocked = true}
			}
		}
	}
}

// The color of the bottle at each mount of the wall, from the liquid in its dispenser, and which mounts have a
// dispenser at all. A dispenser with nothing in it has a grey bottle.
wall_look :: proc(wall: ^inventory.Container) -> (colors: [lab.DISPENSER_COUNT][4]u8, present: [lab.DISPENSER_COUNT]bool) {
	for i in 0 ..< lab.DISPENSER_COUNT {
		colors[i] = {70, 74, 80, 255}
		if i < wall.size {
			s := wall.slots[i]
			if s.count > 0 && s.item.kind == .Dispenser {
				present[i] = true
				if c := chemistry.compound_of(chemistry.Id(s.item.arg)); c != nil {
					colors[i] = {c.color.r, c.color.g, c.color.b, 255}
				}
			}
		}
	}
	return
}

// What a station is as an item, and the other way round. A station of no kind is no item.
station_item :: proc(kind: lab.Station_Kind) -> inventory.Item {
	switch kind {
	case .Hot_Plate:
		return {.Hot_Plate, 0}
	case .Ice_Bath:
		return {.Ice_Bath, 0}
	case .Scale:
		return {.Scale, 0}
	case .Incinerator:
		return {.Incinerator, 0}
	case .Hood:
		return {.Hood, 0}
	case .Filler:
		return {.Filler, 0}
	case .Oven:
		return {.Oven, 0}
	case .None:
	}
	return {}
}

item_station :: proc(item: inventory.Item) -> lab.Station_Kind {
	#partial switch item.kind {
	case .Hot_Plate:
		return .Hot_Plate
	case .Ice_Bath:
		return .Ice_Bath
	case .Scale:
		return .Scale
	case .Incinerator:
		return .Incinerator
	case .Hood:
		return .Hood
	case .Filler:
		return .Filler
	case .Oven:
		return .Oven
	}
	return .None
}

// What a station is called, for the words under the crosshair and on the buttons.
station_name :: proc(kind: lab.Station_Kind) -> string {
	switch kind {
	case .Hot_Plate:
		return "hot plate"
	case .Ice_Bath:
		return "ice bath"
	case .Scale:
		return "scale"
	case .Incinerator:
		return "incinerator"
	case .Hood:
		return "fume hood"
	case .Filler:
		return "balloon filler"
	case .Oven:
		return "reaction oven"
	case .None:
	}
	return ""
}

// The stations of a file from before they could stand anywhere: the bench of six spots, in a container of that name,
// each at the middle of its spot on the north counter. Whether the file had a bench at all is not known to the
// container, so `text` is asked as well: no bench in it means the stations are as the lab starts, and a bench in it,
// empty or not, means exactly the stations that were on it. A station that the counters cannot take, which they all can,
// is dropped. Returns whether the file had a bench.
placed_from_bench_file :: proc(text: string) -> (p: lab.Placed, had_bench: bool) {
	had_bench = strings.contains(text, "container bench ")
	if !had_bench {
		return lab.default_placed(), false
	}
	bench: inventory.Container
	inventory.container_init(&bench, BENCH_SPOTS, {.Benchable})
	names := [1]string{"bench"}
	containers := [1]^inventory.Container{&bench}
	inventory.deserialize(text, names[:], containers[:])
	spot_x := [BENCH_SPOTS]f32{-4.5, -3.5, -2.4, -1.2, 0.0, 1.2} // where the six spots of the bench were along the counter
	for i in 0 ..< BENCH_SPOTS {
		kind := item_station(bench.slots[i].item)
		if kind == .None {
			continue
		}
		z := kind == .Scale ? f32(-7.625) : f32(-7.63)
		if lab.can_place(&p, kind, spot_x[i], z, 0) == .None {
			lab.placed_add(&p, {kind, spot_x[i], z, 0})
		}
	}
	return
}

BENCH_SPOTS :: 6 // the spots of the bench of the files this reads

// Brings back the stations of the lab as it starts that are nowhere: not standing in the lab and not in the bag, on
// the wall or in the bar. A file from before a station could be moved does not have it, and a station is never lost,
// so it comes back at the place it has when the lab starts, or into the bag if something stands there now. Gives how
// many came back, which is none for a file that is complete.
stock_restock :: proc(s: ^Stock, placed: ^lab.Placed) -> (brought: int) {
	start := lab.default_placed()
	for i in 0 ..< start.count {
		pl := start.items[i]
		item := station_item(pl.kind)
		held := inventory.count_of(&s.bag, item) + inventory.count_of(&s.wall, item) + inventory.count_of(&s.hotbar, item)
		if held > 0 || lab.placed_count_of(placed, pl.kind) > 0 {
			continue
		}
		if lab.can_place(placed, pl.kind, pl.x, pl.z, pl.quarter) == .None && lab.placed_add(placed, pl) {
			brought += 1
		} else if inventory.add(&s.bag, item, 1) == 1 || inventory.add(&s.hotbar, item, 1) == 1 {
			brought += 1
		}
	}
	return
}

// The station that the crosshair is on, within reach, with nothing nearer, and which one it is in `Props.placed`.
// `busy` is whether a vessel stands on it, which keeps it from being picked up.
Pickup :: struct {
	index: int,
	aimed: bool,
	busy:  bool,
}

// Whether vessel `pr` stands on the plate of the station: its middle is over it, and it rests on the counter or on
// the plate, not above.
prop_on_plate :: proc(pr: Prop, pl: lab.Placement) -> bool {
	return lab.station_has_plate(pl.kind) && lab.in_rect(lab.world_plate(pl), pr.pos.x, pr.pos.z) && pr.pos.y >= lab.COUNTER_HEIGHT - 0.01 && pr.pos.y <= lab.COUNTER_HEIGHT + lab.SCALE_PLATE_TOP + 0.01
}

// Whether any vessel that is not in the hands stands on the plate of the station.
station_busy :: proc(props: ^Props, pl: lab.Placement) -> bool {
	for i in 0 ..< props.count {
		if i != props.held && prop_on_plate(props.items[i], pl) {
			return true
		}
	}
	return false
}

pickup_aim :: proc(pk: ^Pickup, props: ^Props, v: View) -> bool {
	nearest := f32(0)
	pk^ = {}
	for i in 0 ..< props.placed.count {
		low, high := lab.station_aim_box(props.placed.items[i])
		if t, hit := ray_box(v.eye, -v.back, low, high); hit && t <= REACH && (!pk.aimed || t < nearest) {
			nearest, pk.index, pk.aimed = t, i, true
		}
	}
	pk.aimed = pk.aimed && props.aimed == -1
	pk.busy = pk.aimed && station_busy(props, props.placed.items[pk.index])
	return pk.aimed
}

// Whether the pick up button would take the station now: it is aimed at, the hands are empty, and no vessel stands on it.
pickup_ready :: proc(pk: ^Pickup, props: ^Props) -> bool {
	return pk.aimed && !pk.busy && props.held == -1
}
