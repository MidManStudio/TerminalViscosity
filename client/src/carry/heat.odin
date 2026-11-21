// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "heat.odin"
// ============================================================================

package carry

import "../lab"

HEAT_RATE_C :: f32(6) // degrees a second toward the temperature of a station: about 23 seconds from the room to the top of the hot plate
COOL_RATE_C :: f32(2) // degrees a second back toward the room
HOT_PLATE_C :: f32(160) // what the hot plate heats a vessel to: enough for every window of the pages that uses a hot bath
ICE_BATH_C :: f32(0) // and the ice bath cools it to
HOT_FULL_C :: f32(100) // the temperature that counts as fully hot in the words and the colours
COLD_FULL_C :: f32(0) // and the one that counts as fully cold
HEAT_NOTICE :: f32(0.25) // a liquid this far from the room, as a share of the way to full, is called warm or cool

// What a vessel is standing on: 1 for the hot plate, -1 for the ice bath, and 0 for
// anything else. It counts as standing on one when its middle is inside the
// footprint and it is resting near the counter top.
station_heat :: proc(pr: Prop, bench: ^lab.Bench = nil) -> f32 {
	if pr.pos.y > lab.STATION_RESTING {
		return 0
	}
	b := bench != nil ? bench^ : lab.default_bench()
	if lab.on_bench(&b, .Hot_Plate, pr.pos.x, pr.pos.z) {
		return 1
	}
	if lab.on_bench(&b, .Ice_Bath, pr.pos.x, pr.pos.z) {
		return -1
	}
	return 0
}

move_toward :: proc(value, target, step: f32) -> f32 {
	if value < target {
		return min(value + step, target)
	}
	return max(value - step, target)
}

// The temperature a vessel is heading for: a station's while it stands on one and is not held,
// and the room otherwise.
target_c :: proc(pr: Prop, held: bool, bench: ^lab.Bench = nil) -> f32 {
	if held {
		return ROOM_C
	}
	switch station_heat(pr, bench) {
	case 1:
		return HOT_PLATE_C
	case -1:
		return ICE_BATH_C
	}
	return ROOM_C
}

// Moves the temperature of the liquid in every vessel on by `dt` seconds. A vessel on
// the hot plate warms, one in the ice bath cools, and any other, held ones included,
// drifts back toward the room. A vessel with nothing in it has no temperature. A vessel
// that has moved to a new temperature may now react, because the pages have windows of
// temperature, and what it does is put in `events`, the way a drop that starts a reaction
// does. A vessel that blasts breaks. Returns how many events.
props_heat_update :: proc(props: ^Props, dt: f32, eye: Vec3, events: ^[MAX_EVENTS]Mix_Result) -> int {
	n := 0
	for i := props.count - 1; i >= 0; i -= 1 {
		pr := &props.items[i]
		if ml_of(&pr.mix) <= 0 {
			pr.mix = {}
			continue
		}
		target := target_c(pr^, i == props.held, &props.bench)
		rate := target == ROOM_C ? COOL_RATE_C : HEAT_RATE_C
		before := pr.mix.heat_c
		pr.mix.heat_c = move_toward(pr.mix.heat_c, target, rate * dt)
		if pr.mix.heat_c == before {
			continue
		}
		d := kind_dims(pr.kind)
		r := react(&pr.mix, {pr.pos.x, pr.pos.y + d.height * 0.5, pr.pos.z}, eye, station_of(pr^, &props.bench), 0, main_of(&pr.mix))
		if r.kind == .Nothing {
			continue
		}
		if n < MAX_EVENTS {
			events[n] = r
			n += 1
		}
		if r.kind == .Blast {
			props_remove(props, i)
		}
	}
	return n
}

// Lets the liquid in every tied balloon drift back toward the room, at the rate it does
// in a vessel: the one in the hand, the one in the paint station, and those on the hooks.
loadout_heat_update :: proc(lo: ^Loadout, dt: f32) {
	cool :: proc(item: ^Item, dt: f32) {
		if item.used && ml_of(&item.mix) > 0 {
			item.mix.heat_c = move_toward(item.mix.heat_c, ROOM_C, COOL_RATE_C * dt)
		}
	}
	cool(&lo.hand, dt)
	cool(&lo.paint, dt)
	for &s in lo.slots {
		cool(&s, dt)
	}
}

// How far from the room a temperature is, from -1 for fully cold through 0 to 1 for fully hot.
heat_unit :: proc(heat_c: f32) -> f32 {
	if heat_c >= ROOM_C {
		return min((heat_c - ROOM_C) / (HOT_FULL_C - ROOM_C), 1)
	}
	return max((heat_c - ROOM_C) / (ROOM_C - COLD_FULL_C), -1)
}

// A word for the temperature, for the line under the crosshair: nothing for about
// the room.
heat_word :: proc(heat_c: f32) -> string {
	heat := heat_unit(heat_c)
	switch {
	case heat >= 0.75:
		return "hot"
	case heat >= HEAT_NOTICE:
		return "warm"
	case heat <= -0.75:
		return "cold"
	case heat <= -HEAT_NOTICE:
		return "cool"
	}
	return ""
}
