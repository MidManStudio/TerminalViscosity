// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stock.odin"
// ============================================================================

package carry

import "../chemistry"
import "../inventory"
import "../lab"

BAG_SIZE :: 12 // slots in the bag

// What the player has to put in the lab: the bag, the wall, which has a mount for each tap, and the bench, which has
// a spot for each station that can be moved. A dispenser mounted on the wall gives its tap, and one in the bag does
// not. A station on the bench is where its heat, cold or weighing is, and one in the bag is nowhere.
Stock :: struct {
	bag:   inventory.Container,
	wall:  inventory.Container,
	bench: inventory.Container,
}

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
	wall_default(&s.wall)
	bench_default(&s.bench)
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

// What a station of the bench is as an item, and the other way round. A kind of nothing is no item.
bench_item :: proc(kind: lab.Bench_Kind) -> inventory.Item {
	switch kind {
	case .Hot_Plate:
		return {.Hot_Plate, 0}
	case .Ice_Bath:
		return {.Ice_Bath, 0}
	case .Scale:
		return {.Scale, 0}
	case .None:
	}
	return {}
}

item_bench_kind :: proc(item: inventory.Item) -> lab.Bench_Kind {
	#partial switch item.kind {
	case .Hot_Plate:
		return .Hot_Plate
	case .Ice_Bath:
		return .Ice_Bath
	case .Scale:
		return .Scale
	}
	return .None
}

// The bench as the lab starts, as a container: the stations where `lab.default_bench` has them. It takes only
// things that can stand on a bench.
bench_default :: proc(bench: ^inventory.Container) {
	inventory.container_init(bench, lab.BENCH_SPOTS, {.Benchable})
	d := lab.default_bench()
	for i in 0 ..< lab.BENCH_SPOTS {
		if d.spots[i] != .None {
			inventory.put(bench, i, bench_item(d.spots[i]), 1)
		}
	}
}

// Which station stands at each spot of the bench, from what is in its container.
bench_of :: proc(bench: ^inventory.Container) -> (b: lab.Bench) {
	for i in 0 ..< min(bench.size, lab.BENCH_SPOTS) {
		if bench.slots[i].count > 0 {
			b.spots[i] = item_bench_kind(bench.slots[i].item)
		}
	}
	return
}

// The station that the crosshair is on, within reach, with nothing nearer, and which spot it stands at.
Pickup :: struct {
	spot:  int,
	aimed: bool,
}

pickup_aim :: proc(pk: ^Pickup, props: ^Props, v: View) -> bool {
	nearest := f32(0)
	pk.aimed = false
	for i in 0 ..< lab.BENCH_SPOTS {
		kind := props.bench.spots[i]
		if kind == .None {
			continue
		}
		low, high := lab.bench_aim_box(kind, i)
		if t, hit := ray_box(v.eye, -v.back, low, high); hit && t <= REACH && (!pk.aimed || t < nearest) {
			nearest, pk.spot, pk.aimed = t, i, true
		}
	}
	pk.aimed = pk.aimed && props.aimed == -1
	return pk.aimed
}

// Whether the pick up button would take the station now: it is aimed at, the hands are empty, and the bag has
// room for it.
pickup_ready :: proc(pk: ^Pickup, props: ^Props, bag: ^inventory.Container) -> bool {
	return pk.aimed && props.held == -1 && inventory.free_room(bag, bench_item(props.bench.spots[pk.spot])) > 0
}

// Takes the station at the aimed spot off the bench and into the bag. False, with nothing changed, if there is no
// station there or the bag has no room.
pickup_take :: proc(pk: ^Pickup, s: ^Stock) -> bool {
	if !pk.aimed || pk.spot < 0 || pk.spot >= s.bench.size || s.bench.slots[pk.spot].count == 0 {
		return false
	}
	return inventory.move_to(&s.bench, pk.spot, &s.bag)
}
