// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "station.odin"
// ============================================================================

package carry

import "../chem"
import "../lab"

DISPENSER_FLOW :: f32(110) // ml a second out of a nozzle
NOZZLE_SLACK :: f32(0.07) // how far off center a vessel may be under a nozzle, beyond its radius
NOZZLE_NEAR :: f32(0) // the top of the vessel must be at least this far under the tip
NOZZLE_FAR :: f32(0.55) // and at most this far

// One tap of the bottle wall. `unlocked` is the hook for progression: a locked
// tap gives nothing, and for now every tap is unlocked.
Dispenser :: struct {
	compound: u16,
	unlocked: bool,
}

// The bottle wall: a tap for each stock liquid, in the order of the ids.
Station :: struct {
	items:    [lab.DISPENSER_COUNT]Dispenser,
	flow_acc: f32, // liquid let out and not yet made into drops, in ml
}

station_init :: proc(st: ^Station) {
	st^ = {}
	for i in 0 ..< lab.DISPENSER_COUNT {
		st.items[i] = {compound = u16(i + 1), unlocked = true}
	}
}

// The color of the bottle above each tap, from the liquid it holds.
station_colors :: proc() -> [lab.DISPENSER_COUNT][4]u8 {
	colors: [lab.DISPENSER_COUNT][4]u8
	table := chem.COMPOUNDS
	for i in 0 ..< lab.DISPENSER_COUNT {
		c := table[i].color
		colors[i] = {c.r, c.g, c.b, 255}
	}
	return colors
}

// The tap the held vessel is under, or -1: roughly centered under the nozzle, its
// top below the tip, upright, and with room in it.
dispenser_under :: proc(st: ^Station, props: ^Props) -> int {
	if props.held == -1 {
		return -1
	}
	pr := props.items[props.held]
	if pr.tilt > 0.2 || pr.ml >= capacity_ml(pr.kind) - 0.5 {
		return -1
	}
	d := kind_dims(pr.kind)
	best := -1
	best_dist := f32(1e9)
	for i in 0 ..< lab.DISPENSER_COUNT {
		n := lab.dispenser_nozzle(i)
		dx, dz := pr.pos.x - n.x, pr.pos.z - n.z
		reach := d.radius + NOZZLE_SLACK
		dist := dx * dx + dz * dz
		if dist > reach * reach {
			continue
		}
		gap := n.y - (pr.pos.y + d.height)
		if gap < NOZZLE_NEAR || gap > NOZZLE_FAR {
			continue
		}
		if dist < best_dist {
			best, best_dist = i, dist
		}
	}
	return best
}

// Lets tap `i` run for `dt` seconds. False if it is locked.
station_flow :: proc(st: ^Station, stream: ^Stream, l: ^lab.Layout, i: int, dt: f32) -> bool {
	if !st.items[i].unlocked {
		return false
	}
	st.flow_acc = min(st.flow_acc + DISPENSER_FLOW * dt, 2 * DROP_ML)
	nozzle := lab.dispenser_nozzle(i)
	vel := Vec3{0, -0.5, 0}
	count := int(st.flow_acc / DROP_ML)
	for j in 0 ..< count {
		age := dt * f32(count - 1 - j) / f32(count) // spread along the way, as for a pour
		if !stream_spawn(stream, l, nozzle + vel * age, vel, st.items[i].compound) {
			break
		}
		st.flow_acc -= DROP_ML
	}
	return true
}
