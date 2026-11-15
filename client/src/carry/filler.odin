// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "filler.odin"
// ============================================================================

package carry

import "../chemistry"
import "../lab"

BALLOON_REST_ML :: f32(1000) // what a balloon holds at its rest shape, a fill of 1
BALLOON_POP_AT :: f32(1.35) // the fill at which a balloon bursts
BALLOON_POP_ML :: BALLOON_REST_ML * BALLOON_POP_AT
FILLER_RESPAWN :: f32(2) // seconds before a fresh balloon is clamped after one is lost
FILLER_CAPTURE_PAD :: f32(0.015) // how far outside the funnel a falling drop still goes in

// The balloon fill station: a balloon held by its neck under a funnel, filled by
// pouring into the funnel. It holds a mixture, as a vessel does, and
// bursts when overfilled. `generation` counts the balloons that have been
// clamped, so the part that draws the soft body knows when to start a new one.
Filler :: struct {
	present:    bool,
	mix:        chemistry.Mixture, // what is in the balloon, at a temperature in degrees, as for a vessel
	respawn:    f32, // seconds until the next balloon, while there is none
	generation: int,
	aimed:      bool, // the crosshair is on the station, and nothing nearer
	aimed_t:    f32,
}

// What a drop into the balloon did: the meeting of liquids, if it started one, and
// whether the balloon burst, either from the reaction or from being overfilled.
Fill_Result :: struct {
	mix:    Mix_Result,
	popped: bool, // an overfill, which only wets the floor
	lost:   u16, // the compound there was most of when the balloon was lost, for the color of the burst
}

filler_init :: proc(f: ^Filler) {
	f^ = {
		present    = true,
		generation = 1,
	}
}

// How full the balloon is, as a share of its rest volume: 1 is its natural size.
fill_ratio :: proc(f: ^Filler) -> f32 {
	return f.present ? ml_of(&f.mix) / BALLOON_REST_ML : 0
}

// How near a burst the balloon is, from 0 at a fill of 1 to 1 at the limit. It is
// what the gauge shows red and what makes the rubber go thin.
strain :: proc(f: ^Filler) -> f32 {
	return clamp((fill_ratio(f) - 1) / (BALLOON_POP_AT - 1), 0, 1)
}

// Loses the balloon: the liquid and the balloon are gone, and another is clamped
// after a short wait.
filler_burst :: proc(f: ^Filler) {
	f.present = false
	f.mix = {}
	f.respawn = FILLER_RESPAWN
}

// A drop of `compound` falls into the funnel. It joins the balloon or reacts with
// what is in it, by the same rule as a vessel. A violent reaction bursts the
// balloon, and so does filling it to the limit. A drop that falls with no balloon
// there is lost.
filler_take_drop :: proc(f: ^Filler, compound: u16, ml: f32, eye: Vec3, drop_heat_c := ROOM_C, purity := STOCK_PURITY) -> Fill_Result {
	if !f.present {
		return {}
	}
	r := mix_into(&f.mix, BALLOON_POP_ML + DROP_ML, lab.filler_center(), eye, .Any, compound, ml, purity, drop_heat_c)
	out := Fill_Result {
		mix = r,
	}
	switch {
	case r.kind == .Blast:
		out.lost = main_of(&f.mix)
		filler_burst(f)
	case ml_of(&f.mix) >= BALLOON_POP_ML:
		out.popped = true
		out.lost = main_of(&f.mix)
		filler_burst(f)
	}
	return out
}

// Ticks the temperature of the liquid and the wait for the next balloon.
filler_update :: proc(f: ^Filler, dt: f32) {
	// The liquid in the balloon drifts back toward the room, as in a vessel.
	if ml_of(&f.mix) > 0 {
		f.mix.heat_c = move_toward(f.mix.heat_c, ROOM_C, COOL_RATE_C * dt)
	} else {
		f.mix = {}
	}
	if !f.present {
		f.respawn -= dt
		if f.respawn <= 0 {
			f.present = true
			f.generation += 1
		}
	}
}

// Whether the crosshair is on the station, within reach, and nearer than any
// vessel it also points at.
filler_aim :: proc(f: ^Filler, props: ^Props, v: View) -> bool {
	t, hit := ray_box(v.eye, -v.back, lab.FILLER_AIM_LOW, lab.FILLER_AIM_HIGH)
	f.aimed_t = t
	f.aimed = hit && f.present && t <= REACH && (props.aimed == -1 || t < props.aimed_t)
	return f.aimed
}

// The pour button is ready for the station: something is held, the crosshair is on
// the station and close enough, and no vessel is the better target.
filler_pour_ready :: proc(f: ^Filler, props: ^Props) -> bool {
	return props.held != -1 && f.aimed && f.aimed_t <= POUR_REACH && pour_target(props) == -1
}

// The point a pour is aimed at when the target is the station: just above the rim
// of the funnel.
filler_mouth :: proc() -> Vec3 {
	return lab.FILLER_MOUTH + Vec3{0, 0.03, 0}
}

// Lets the balloon take the drops that have fallen into the funnel: a drop inside
// a column a little wider than the funnel, from just above the clamp to well over
// the rim. Whatever needs telling, a reaction or a burst, is put in `events`.
// Returns how many.
filler_capture :: proc(st: ^Stream, f: ^Filler, eye: Vec3, events: ^[MAX_EVENTS]Fill_Result) -> int {
	n := 0
	if !f.present {
		return 0
	}
	reach := lab.FILLER_FUNNEL_RADIUS + FILLER_CAPTURE_PAD
	for i := st.sim.count - 1; i >= 0; i -= 1 {
		w := stream_position(st, i)
		dx, dz := w.x - lab.FILLER_MOUTH.x, w.z - lab.FILLER_MOUTH.z
		if dx * dx + dz * dz > reach * reach {
			continue
		}
		if w.y < lab.FILLER_CAPTURE_LOW || w.y > lab.FILLER_CAPTURE_HIGH {
			continue
		}
		r := filler_take_drop(f, st.compound[i], st.ml[i], eye, st.heat[i], st.purity[i])
		stream_remove(st, i)
		if (r.mix.kind != .Nothing || r.popped) && n < MAX_EVENTS {
			events[n] = r
			n += 1
		}
		if !f.present {
			break
		}
	}
	return n
}

// What color a light of the gauge shows.
Gauge_Color :: enum {
	Off,
	Green, // under the balloon's natural size
	Amber, // stretched
	Red, // close to bursting
}

// The color of light `i` of the gauge, counting from the bottom, for a fill of
// `ratio`. The whole gauge runs from empty to the bursting limit, so the lights
// light one after another as the balloon fills. A light is green while the middle
// of its step is under a fill of 1, amber up to 1.2, and red above.
gauge_color :: proc(ratio: f32, i: int) -> Gauge_Color {
	step := BALLOON_POP_AT / f32(lab.GAUGE_LIGHTS)
	if ratio <= f32(i) * step {
		return .Off
	}
	middle := (f32(i) + 0.5) * step
	switch {
	case middle <= 1:
		return .Green
	case middle <= 1.2:
		return .Amber
	}
	return .Red
}
