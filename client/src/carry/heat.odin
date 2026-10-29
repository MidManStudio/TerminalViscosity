// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "heat.odin"
// ============================================================================

package carry

import "../lab"

HEAT_RATE :: f32(0.2) // a second, toward the temperature of the station: five seconds from the room to full
COOL_RATE :: f32(0.03) // a second, back toward the room: about half a minute from full
HEAT_NOTICE :: f32(0.25) // a liquid this far from the room is called warm or cool

// What a vessel is standing on: 1 for the hot plate, -1 for the ice bath, and 0 for
// anything else. It counts as standing on one when its middle is inside the
// footprint and it is resting near the counter top.
station_heat :: proc(pr: Prop) -> f32 {
	if pr.pos.y > lab.STATION_RESTING {
		return 0
	}
	if lab.in_rect(lab.HOT_PLATE, pr.pos.x, pr.pos.z) {
		return 1
	}
	if lab.in_rect(lab.ICE_BATH, pr.pos.x, pr.pos.z) {
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

// Moves the temperature of the liquid in every vessel on by `dt` seconds. A vessel on
// the hot plate warms, one in the ice bath cools, and any other, held ones included,
// drifts back toward the room. A vessel with nothing in it has no temperature.
props_heat_update :: proc(props: ^Props, dt: f32) {
	for i in 0 ..< props.count {
		pr := &props.items[i]
		if pr.ml <= 0 {
			pr.heat = 0
			continue
		}
		target := i == props.held ? f32(0) : station_heat(pr^)
		rate := target == 0 ? COOL_RATE : HEAT_RATE
		pr.heat = move_toward(pr.heat, target, rate * dt)
	}
}

// A word for the temperature, for the line under the crosshair: nothing for about
// the room.
heat_word :: proc(heat: f32) -> string {
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
