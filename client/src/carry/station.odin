// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "station.odin"
// ============================================================================

package carry

import "../chem"
import "../lab"

DISPENSER_FLOW :: f32(110) // ml a second out of a nozzle
TAP_ASSIST :: f32(0.5) // how far sideways a held vessel may be from a nozzle, and the stream still finds its mouth
NOZZLE_NEAR :: f32(-0.35) // the top of the vessel may be this far over the tip, at most
NOZZLE_FAR :: f32(0.9) // and at most this far under it

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

// The tap the held vessel is near enough to be filled from, or -1. The vessel is
// upright and has room, within half a metre of the nozzle sideways, and not too far
// over or under the tip. The stream is aimed into its mouth, so it need not be
// exactly under the nozzle. When two taps are near, the nearer is the one.
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
		dist := dx * dx + dz * dz
		if dist > TAP_ASSIST * TAP_ASSIST {
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

// Where a stream from a nozzle is aimed when a vessel is held: just over its rim.
tap_mouth :: proc(props: ^Props) -> Vec3 {
	pr := props.items[props.held]
	return {pr.pos.x, pr.pos.y + kind_dims(pr.kind).height + 0.03, pr.pos.z}
}

// Lets tap `i` run for `dt` seconds, straight down. False if it is locked.
station_flow :: proc(st: ^Station, stream: ^Stream, l: ^lab.Layout, i: int, dt: f32) -> bool {
	return station_flow_to(st, stream, l, i, dt, {}, false, 1)
}

// The same, aimed at `mouth` when `has_mouth` is set, and `speed` times faster than
// normal. A faster tap lets out drops that carry more, not more drops.
station_flow_to :: proc(st: ^Station, stream: ^Stream, l: ^lab.Layout, i: int, dt: f32, mouth: Vec3, has_mouth: bool, speed: f32) -> bool {
	if !st.items[i].unlocked {
		return false
	}
	drop := DROP_ML * speed
	st.flow_acc = min(st.flow_acc + DISPENSER_FLOW * speed * dt, 2 * drop)
	nozzle := lab.dispenser_nozzle(i)
	vel := Vec3{0, -0.5, 0}
	if has_mouth {
		vel = arc_to(nozzle, mouth)
	}
	count := int(st.flow_acc / drop)
	for j in 0 ..< count {
		age := dt * f32(count - 1 - j) / f32(count) // spread along the way, as for a pour
		if !stream_spawn_ml(stream, l, nozzle + vel * age, vel, st.items[i].compound, drop) {
			break
		}
		st.flow_acc -= drop
	}
	return true
}
