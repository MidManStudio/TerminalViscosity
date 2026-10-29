// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "loadout.odin"
// ============================================================================

package carry

import "../lab"

LOADOUT_SLOTS :: lab.LOADOUT_SLOTS // how many balloons a loadout holds. It is not decided, so it is set in one place, the lab.

// A tied balloon: what is in it, and the drawing on it. It is the data a balloon
// needs to be sent to the server and shown to the other players. A balloon in the
// lab has one liquid, so it is one chamber of a recipe.
Item :: struct {
	used:     bool,
	compound: u16,
	ml:       f32,
	heat:     f32,
	art:      u16, // 0 while there is no drawing. The paint station is there, the drawing is not.
}

// What the server needs of a balloon in the loadout. `volume_ml` and `compound`
// are the one chamber of the recipe, and `art` says which drawing goes with it.
Preset :: struct {
	compound:  u16,
	volume_ml: u16,
	art:       u16,
}

// The place the crosshair is on that a balloon can be put or taken.
Spot :: enum u8 {
	None,
	Fill, // the clamp of the fill station
	Paint, // the paint station
	Slot, // a hook of the loadout rack
}

// The one action the grab button does at a spot, with a balloon or without.
Balloon_Action :: enum u8 {
	None,
	Tie_Take, // tie off the balloon at the fill station and take it
	Clamp, // clamp the balloon in the hand into the paint station
	Take_Paint, // take the balloon out of the paint station
	Store, // hang the balloon in the hand on a hook
	Take_Slot, // take the balloon off a hook
}

// The balloons the player has: one in the hand, one in the paint station, and the
// hooks of the loadout, which is what is kept between matches.
Loadout :: struct {
	hand:      Item,
	paint:     Item,
	slots:     [LOADOUT_SLOTS]Item,
	spot:      Spot,
	spot_slot: int, // which hook, when the spot is a slot
	spot_t:    f32,
}

// Whether a balloon is in the hands. The hands hold a balloon or a vessel, not both.
loadout_hands_full :: proc(lo: ^Loadout) -> bool {
	return lo.hand.used
}

// Finds what the crosshair is on among the fill clamp, the paint station, and the
// hooks of the rack: the nearest one within reach, and nearer than any vessel. Run it
// after `filler_aim`, which says whether the crosshair is on the fill clamp.
loadout_aim :: proc(lo: ^Loadout, f: ^Filler, props: ^Props, v: View) {
	dir := -v.back
	best_t := f32(1e9)
	lo.spot, lo.spot_slot = .None, -1
	if f.aimed {
		best_t = f.aimed_t
		lo.spot = .Fill
	}
	if t, hit := ray_box(v.eye, dir, lab.PAINT_AIM_LOW, lab.PAINT_AIM_HIGH); hit && t < best_t {
		best_t = t
		lo.spot = .Paint
	}
	for i in 0 ..< LOADOUT_SLOTS {
		low, high := lab.slot_aim(i)
		if t, hit := ray_box(v.eye, dir, low, high); hit && t < best_t {
			best_t = t
			lo.spot, lo.spot_slot = .Slot, i
		}
	}
	lo.spot_t = best_t
	if lo.spot == .None || best_t > REACH || (props.aimed != -1 && best_t >= props.aimed_t) {
		lo.spot, lo.spot_slot = .None, -1
	}
}

// What the grab button would do now. Nothing while a vessel is held. At the fill
// clamp it ties off a balloon that has something in it, and takes it, with empty
// hands. At the paint station and a hook it puts the balloon in the hand there if the
// place is free, and takes the balloon there if the hand is free.
balloon_action :: proc(lo: ^Loadout, f: ^Filler, props: ^Props) -> Balloon_Action {
	if props.held != -1 {
		return .None
	}
	switch lo.spot {
	case .None:
	case .Fill:
		if !lo.hand.used && f.present && f.ml > 0 {
			return .Tie_Take
		}
	case .Paint:
		if lo.hand.used && !lo.paint.used {
			return .Clamp
		} else if !lo.hand.used && lo.paint.used {
			return .Take_Paint
		}
	case .Slot:
		slot := lo.slots[lo.spot_slot]
		if lo.hand.used && !slot.used {
			return .Store
		} else if !lo.hand.used && slot.used {
			return .Take_Slot
		}
	}
	return .None
}

// Ties off the balloon at the fill station and takes what is in it, up to a full
// balloon: a stretched balloon is let down to full, and the excess is lost. The
// station clamps a fresh balloon after a short wait.
filler_tie :: proc(f: ^Filler) -> (item: Item, let_out: f32) {
	if !f.present || f.ml <= 0 {
		return {}, 0
	}
	item = {
		used     = true,
		compound = f.compound,
		ml       = min(f.ml, BALLOON_REST_ML),
		heat     = f.heat,
	}
	let_out = f.ml - item.ml
	f.present = false
	f.compound, f.ml, f.heat = 0, 0, 0
	f.respawn = FILLER_RESPAWN
	f.session = {
		target = -1,
	}
	return
}

// Does the action. Returns what was let out of a stretched balloon when it was tied,
// and false if the action cannot be done.
balloon_do :: proc(lo: ^Loadout, f: ^Filler, action: Balloon_Action) -> (let_out: f32, ok: bool) {
	switch action {
	case .None:
		return 0, false
	case .Tie_Take:
		item, out := filler_tie(f)
		if !item.used {
			return 0, false
		}
		lo.hand = item
		return out, true
	case .Clamp:
		lo.paint, lo.hand = lo.hand, {}
	case .Take_Paint:
		lo.hand, lo.paint = lo.paint, {}
	case .Store:
		lo.slots[lo.spot_slot], lo.hand = lo.hand, {}
	case .Take_Slot:
		lo.hand, lo.slots[lo.spot_slot] = lo.slots[lo.spot_slot], {}
	}
	return 0, true
}

// How many hooks hold a balloon.
loadout_count :: proc(lo: ^Loadout) -> int {
	n := 0
	for s in lo.slots {
		if s.used {
			n += 1
		}
	}
	return n
}

// What the server needs of each balloon in the loadout, hook by hook, as the
// recipe and the drawing of each. Empty hooks are left out, and `count` says how many.
loadout_presets :: proc(lo: ^Loadout) -> (out: [LOADOUT_SLOTS]Preset, count: int) {
	for s in lo.slots {
		if !s.used {
			continue
		}
		out[count] = {
			compound  = s.compound,
			volume_ml = u16(clamp(s.ml + 0.5, 0, f32(BALLOON_REST_ML))),
			art       = s.art,
		}
		count += 1
	}
	return
}
