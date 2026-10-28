// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "oven.odin"
// ============================================================================

package carry

import "../chem"
import "../lab"

PORT_CAPACITY :: f32(500) // ml one port holds
TANK_CAPACITY :: f32(2000) // what the four ports make together, so the tank always fits a run
OVEN_RUN_TIME :: f32(6) // seconds a run takes at normal speed
OVEN_CAPTURE_PAD :: f32(0.015) // how far outside a funnel a falling drop still goes in
OVEN_SPOUT_FLOW :: f32(110) // ml a second out of the spout, at normal speed
REFUSED_GAP :: f32(1.5) // seconds between two tellings that a port refused a liquid

// One port of the oven: one liquid, and how much.
Port :: struct {
	compound: u16,
	ml:       f32,
}

Oven_State :: enum u8 {
	Idle, // the ports take liquid
	Running, // closed, and mixing
}

// The reaction oven: four ports that each hold one liquid kept apart from the
// others, and a tank. A run mixes the four, in order, the way a vessel would, but
// inside the machine: a volatile reaction gives its product and hurts no one. The
// product waits in the tank, which a held vessel is filled from at the spout.
Oven :: struct {
	ports:      [lab.MIXER_PORTS]Port,
	tank:       Port,
	state:      Oven_State,
	timer:      f32, // seconds left of the run
	length:     f32, // seconds the run takes, for how far along it is
	flow_acc:   f32, // liquid let out of the spout and not yet made into drops
	refused:    f32, // seconds until a refusal may be told again
	aimed:      bool, // the crosshair is on the oven, and nothing nearer
	aimed_t:    f32,
	aimed_port: int, // the port nearest where the crosshair is, or -1
}

Oven_Event_Kind :: enum {
	Nothing,
	Refused, // a drop was turned away because the port holds another liquid
	Finished, // a run ended
}

// What the player is to be told. For a refusal `compound` is what the port holds,
// and for a run `compound` is the product, `ml` how much, and `volatility` how
// violent the worst reaction in it was, for the look of the end of the run.
Oven_Event :: struct {
	kind:       Oven_Event_Kind,
	port:       int,
	compound:   u16,
	ml:         f32,
	volatility: f32,
}

oven_init :: proc(o: ^Oven) {
	o^ = {
		aimed_port = -1,
	}
}

// How many of the ports hold something.
oven_loaded :: proc(o: ^Oven) -> int {
	n := 0
	for p in o.ports {
		if p.ml > 0 {
			n += 1
		}
	}
	return n
}

// Whether a run could start: the oven is idle, something is in a port, and the
// tank is empty.
oven_can_run :: proc(o: ^Oven) -> bool {
	return o.state == .Idle && o.tank.ml <= 0 && oven_loaded(o) > 0
}

// Starts a run that takes `OVEN_RUN_TIME / speed` seconds. False if it cannot start.
oven_start :: proc(o: ^Oven, speed: f32) -> bool {
	if !oven_can_run(o) {
		return false
	}
	o.state = .Running
	o.length = OVEN_RUN_TIME / max(speed, 1)
	o.timer = o.length
	return true
}

// How far along a run is, from 0 to 1.
oven_progress :: proc(o: ^Oven) -> f32 {
	if o.state != .Running {
		return 0
	}
	return clamp(1 - o.timer / max(o.length, 1e-3), 0, 1)
}

// What the ports make: the first liquid, then each next one mixed into it by the
// reaction matrix, in the order of the ports, with the liquid of a port that holds
// the same thing as the mix so far simply added. Nothing is lost, the oven is shut.
// Also gives the worst volatility of any step.
oven_fold :: proc(o: ^Oven) -> (compound: u16, ml: f32, volatility: f32) {
	for p in o.ports {
		if p.ml <= 0 {
			continue
		}
		switch {
		case compound == 0:
			compound, ml = p.compound, p.ml
		case compound == p.compound:
			ml += p.ml
		case:
			outcome := chem.react(compound, p.compound)
			volatility = max(volatility, outcome.volatility)
			compound = outcome.product
			ml += p.ml
		}
	}
	return
}

// Ticks the oven. When a run ends the ports are emptied into the tank as the
// product, and the event says so.
oven_update :: proc(o: ^Oven, dt: f32) -> Oven_Event {
	o.refused = max(o.refused - dt, 0)
	if o.state != .Running {
		return {}
	}
	o.timer -= dt
	if o.timer > 0 {
		return {}
	}
	compound, ml, volatility := oven_fold(o)
	for &p in o.ports {
		p = {}
	}
	o.tank = {compound, ml}
	o.state = .Idle
	o.timer, o.length = 0, 0
	return {kind = .Finished, compound = compound, ml = ml, volatility = volatility}
}

// Whether the crosshair is on the oven, within reach, and nearer than any vessel
// it also points at, and which port is nearest where it points.
oven_aim :: proc(o: ^Oven, props: ^Props, v: View) -> bool {
	dir := -v.back
	t, hit := ray_box(v.eye, dir, lab.MIXER_AIM_LOW, lab.MIXER_AIM_HIGH)
	o.aimed_t = t
	o.aimed = hit && t <= REACH && (props.aimed == -1 || t < props.aimed_t)
	o.aimed_port = -1
	if o.aimed {
		// Which port the crosshair points at is where its line is over the funnels,
		// not where it first meets the box, so follow it back to their depth.
		x := v.eye.x + dir.x * t
		if abs(dir.z) > 1e-3 {
			x = v.eye.x + dir.x * ((lab.mixer_port(0).z - v.eye.z) / dir.z)
		}
		i := int((x - lab.MIXER.min_x) / lab.MIXER_PORT_SPACING)
		o.aimed_port = clamp(i, 0, lab.MIXER_PORTS - 1)
	}
	return o.aimed
}

// The pour button is ready for the oven: a vessel is held, the crosshair is on the
// oven and close enough, the ports are open, and no vessel is the better target.
oven_pour_ready :: proc(o: ^Oven, props: ^Props) -> bool {
	return props.held != -1 && o.aimed && o.aimed_t <= POUR_REACH && o.state == .Idle && pour_target(props) == -1
}

// The run button is ready: nothing is held, the crosshair is on the oven, and a run
// could start.
oven_run_ready :: proc(o: ^Oven, props: ^Props) -> bool {
	return props.held == -1 && o.aimed && oven_can_run(o)
}

// The point a pour is aimed at when the target is the oven: just over the rim of the
// funnel of the port nearest the crosshair.
oven_mouth :: proc(o: ^Oven) -> Vec3 {
	return lab.mixer_port(max(o.aimed_port, 0)) + Vec3{0, 0.03, 0}
}

// Lets the ports take the drops that have fallen into their funnels. A port takes
// one liquid at a time: a drop of another is turned away, and the event says which
// port and what it holds, at most once in a while. A full port loses the drop. While
// a run is going the oven is shut and takes nothing. Returns how many events.
oven_capture :: proc(st: ^Stream, o: ^Oven, events: ^[MAX_EVENTS]Oven_Event) -> int {
	n := 0
	if o.state != .Idle {
		return 0
	}
	reach := lab.MIXER_PORT_RADIUS + OVEN_CAPTURE_PAD
	for i := st.sim.count - 1; i >= 0; i -= 1 {
		w := stream_position(st, i)
		for k in 0 ..< lab.MIXER_PORTS {
			mouth := lab.mixer_port(k)
			dx, dz := w.x - mouth.x, w.z - mouth.z
			if dx * dx + dz * dz > reach * reach {
				continue
			}
			if w.y < lab.MIXER_TOP - 0.02 || w.y > lab.MIXER_TOP + lab.MIXER_CAPTURE_ABOVE {
				continue
			}
			port := &o.ports[k]
			switch {
			case port.ml <= 0 || port.compound == st.compound[i]:
				port.compound = st.compound[i]
				port.ml += min(st.ml[i], PORT_CAPACITY - port.ml)
			case o.refused <= 0 && n < MAX_EVENTS:
				events[n] = {
					kind     = .Refused,
					port     = k,
					compound = port.compound,
				}
				n += 1
				o.refused = REFUSED_GAP
			}
			stream_remove(st, i)
			break
		}
	}
	return n
}

// Whether the held vessel is near enough to the spout to be filled from it, by the
// same rule as a tap: upright, with room, within half a metre sideways, and not too
// far over or under the tip, and there is product in the tank.
oven_spout_under :: proc(o: ^Oven, props: ^Props) -> bool {
	if props.held == -1 || o.tank.ml <= 0 {
		return false
	}
	pr := props.items[props.held]
	if pr.tilt > 0.2 || pr.ml >= capacity_ml(pr.kind) - 0.5 {
		return false
	}
	n := lab.MIXER_SPOUT
	dx, dz := pr.pos.x - n.x, pr.pos.z - n.z
	if dx * dx + dz * dz > TAP_ASSIST * TAP_ASSIST {
		return false
	}
	gap := n.y - (pr.pos.y + kind_dims(pr.kind).height)
	return gap >= NOZZLE_NEAR && gap <= NOZZLE_FAR
}

// Lets the spout run for `dt` seconds, `speed` times faster than normal, aimed at
// `mouth`. A faster spout lets out drops that carry more. The tank is emptied as the
// liquid leaves, and the last of it goes as a smaller drop. False if the tank is empty.
oven_flow :: proc(o: ^Oven, st: ^Stream, l: ^lab.Layout, dt: f32, mouth: Vec3, speed: f32) -> bool {
	if o.tank.ml <= 0 {
		return false
	}
	drop := DROP_ML * speed
	o.flow_acc = min(o.flow_acc + OVEN_SPOUT_FLOW * speed * dt, 2 * drop)
	nozzle := lab.MIXER_SPOUT
	vel := arc_to(nozzle, mouth)
	for n in 0 ..< 2 {
		amount := min(drop, o.tank.ml)
		if amount <= 0 || o.flow_acc < amount - 1e-4 {
			break
		}
		age := dt * 0.5 * f32(1 - n)
		if !stream_spawn_ml(st, l, nozzle + vel * age, vel, o.tank.compound, amount) {
			break
		}
		o.flow_acc -= amount
		o.tank.ml -= amount
	}
	if o.tank.ml <= 0.01 {
		o.tank = {}
		o.flow_acc = 0
	}
	return true
}
