// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "arena.odin"
// ============================================================================

// Package arena is the match as the client sees it: data in, data out. The match view
// holds what the simulation last said (players, balloons in flight, bursts), the input
// and throw structs hold what the player asks for, and a host is whatever answers, the
// Rust world running in this process today and a network connection later. Nothing here
// simulates: players are placed and balloons fly by the numbers they are given. It has
// no raylib dependency, so it is tested without a window.
package arena

import "../carry"
import "../chemistry"
import "core:math"

MAX_PLAYERS :: 8 // the same number as tv_proto::MAX_PLAYERS
MAX_BALLOONS :: 40 // the same number as tv_proto::MAX_BALLOONS_PER_SNAPSHOT
MAX_BURSTS :: 40 // the most bursts one step reports, one for each balloon that could be in flight

ARENA_RADIUS :: f32(20) // metres, tv_sim::ARENA_RADIUS_M. The selftest checks the two agree.
EYE_HEIGHT :: f32(1.6)
LOCAL_PLAYER :: u8(0) // the player this client is, until a match can say otherwise
PITCH_LIMIT :: f32(1.25) // radians up or down, as in the lab
MAX_HEALTH :: u8(100) // hit points a player starts with, tv_proto::MAX_HEALTH. The selftest checks the two agree.

POWER_MIN :: u8(60) // a tap: 6 m/s, a gentle lob
POWER_MAX :: u8(180) // fully charged: 18 m/s
CHARGE_SECONDS :: f32(1.2) // how long holding the throw button takes to reach full power
THROW_COOLDOWN :: f32(0.5) // seconds before the next balloon can start charging

PRACTICE_ML :: u16(500)

Vec3 :: [3]f32

// A player as the simulation placed them. `yaw` is in radians: 0 faces -z and a quarter
// turn faces +x, the same as the lab's player.
Player_View :: struct {
	id:  u8,
	pos: Vec3, // the feet, in metres
	yaw: f32,
	hp:  u8, // hit points left, 0 when knocked out
}

// Whether a player is knocked out: out of hit points, down until the match brings them back.
knocked_out :: proc(p: Player_View) -> bool {
	return p.hp == 0
}

// A balloon in flight. `slot` is the slot of its thrower's loadout it came from, which says
// which drawing it wears.
Flight :: struct {
	id:       u16,
	owner:    u8,
	slot:     u8,
	compound: u16,
	pos:      Vec3, // metres
	vel:      Vec3, // metres a second
}

// A balloon that burst. `volatility` is 0 for a plain splash and 1 for the worst.
Burst :: struct {
	balloon:    u16,
	compound:   u16,
	volatility: f32,
	pos:        Vec3,
	radius:     f32,
}

// Everything the scene needs to draw one frame of the match. `bursts` holds what
// happened since the previous step, and is emptied by the next one.
Match_View :: struct {
	tick:          u32,
	players:       [MAX_PLAYERS]Player_View,
	player_count:  int,
	balloons:      [MAX_BALLOONS]Flight,
	balloon_count: int,
	bursts:        [MAX_BURSTS]Burst,
	burst_count:   int,
}

// What the player is doing with the walking controls. Stick values run from -1 to 1, and
// `jump` is whether the jump button is held, which the match turns into a jump if the player
// is on the floor.
Input :: struct {
	forward: f32,
	strafe:  f32,
	yaw:     f32,
	jump:    bool,
}

// A balloon to throw: where it came from in the loadout, what it holds, and how it is
// aimed. `dir` need not be a unit vector.
Throw :: struct {
	slot:     u8,
	compound: u16,
	ml:       u16,
	dir:      Vec3,
	power:    u8,
}

// Whatever answers the match: the scene sends input and throws, steps it, and reads the
// view. The first host runs the Rust world in this process, and a network client can
// take its place without the scene changing.
Host :: struct {
	data:         rawptr,
	submit_input: proc(data: rawptr, input: Input),
	submit_throw: proc(data: rawptr, throw: Throw) -> bool,
	step:         proc(data: rawptr, dt: f32),
	view:         proc(data: rawptr) -> ^Match_View,
}

host_input :: proc(h: ^Host, input: Input) {
	h.submit_input(h.data, input)
}

host_throw :: proc(h: ^Host, throw: Throw) -> bool {
	return h.submit_throw(h.data, throw)
}

host_step :: proc(h: ^Host, dt: f32) {
	h.step(h.data, dt)
}

host_view :: proc(h: ^Host) -> ^Match_View {
	return h.view(h.data)
}

// The view of the player with this id, if they are in the match.
view_player :: proc(v: ^Match_View, id: u8) -> (p: Player_View, ok: bool) {
	for i in 0 ..< v.player_count {
		if v.players[i].id == id {
			return v.players[i], true
		}
	}
	return {}, false
}

// Whether a player is standing on the floor, within a couple of centimetres, which is what
// the jump button shows. The view is drawn between ticks, so it is a little loose at the ends
// of a jump.
on_floor :: proc(p: Player_View) -> bool {
	return p.pos.y <= 0.02
}

// Whether `owner` has just thrown: there is a balloon of theirs in `curr` that was not in `prev`,
// two views of the match one after the other.
thrown_by :: proc(prev, curr: ^Match_View, owner: u8) -> bool {
	for i in 0 ..< curr.balloon_count {
		if curr.balloons[i].owner != owner {
			continue
		}
		known := false
		for j in 0 ..< prev.balloon_count {
			if prev.balloons[j].id == curr.balloons[i].id {
				known = true
				break
			}
		}
		if !known {
			return true
		}
	}
	return false
}

// Where the eye of a player is: the feet, and the height of the head.
eye_of :: proc(p: Player_View) -> Vec3 {
	return p.pos + {0, EYE_HEIGHT, 0}
}

// Where the player looks. The player chooses it, and the simulation only hears of the
// heading, so the view turns the moment a finger moves.
Look :: struct {
	yaw:   f32,
	pitch: f32,
}

look_turn :: proc(l: ^Look, d_yaw, d_pitch: f32) {
	l.yaw += d_yaw
	l.pitch = clamp(l.pitch + d_pitch, -PITCH_LIMIT, PITCH_LIMIT)
}

// The direction of the view, as a unit vector, with yaw 0 looking toward -z.
look_dir :: proc(l: Look) -> Vec3 {
	cp := math.cos(l.pitch)
	return {math.sin(l.yaw) * cp, math.sin(l.pitch), -math.cos(l.yaw) * cp}
}

// The direction as the wire carries it: scaled so that its longest side is 1000.
dir_wire :: proc(dir: Vec3) -> [3]i16 {
	longest := max(abs(dir.x), abs(dir.y), abs(dir.z))
	if longest < 1e-6 {
		return {}
	}
	k := 1000 / longest
	return {i16(math.round(dir.x * k)), i16(math.round(dir.y * k)), i16(math.round(dir.z * k))}
}

// How much of the way to full power a held throw button is, after `dt` more seconds.
charge_step :: proc(charge, dt: f32) -> f32 {
	return clamp(charge + dt / CHARGE_SECONDS, 0, 1)
}

// The launch power of a charge from 0 to 1.
charge_power :: proc(charge: f32) -> u8 {
	c := clamp(charge, 0, 1)
	return POWER_MIN + u8(math.round(f32(POWER_MAX - POWER_MIN) * c))
}

// A balloon the player can throw: one slot of the loadout. `practice` marks the plain
// water balloon the arena offers when the loadout is empty, so the scene can say so.
Slot :: struct {
	used:     bool,
	mix:      chemistry.Mixture, // the whole mixture the balloon carries
	compound: u16, // the compound there is most of, which is all the wire carries so far
	ml:       u16, // and the whole volume
	art:      u16,
	practice: bool,
}

// The balloons the arena offers, hook for hook as in the lab. With nothing on any hook the
// first slot is a practice water balloon, so the arena can still be tried.
slots_from_loadout :: proc(lo: ^carry.Loadout) -> (slots: [carry.LOADOUT_SLOTS]Slot) {
	any_used := false
	for item, i in lo.slots {
		if !item.used {
			continue
		}
		any_used = true
		m := item.mix
		slots[i] = {
			used     = true,
			mix      = m,
			compound = carry.main_of(&m),
			ml       = u16(clamp(carry.ml_of(&m) + 0.5, 1, f32(carry.BALLOON_REST_ML))),
			art      = item.art,
		}
	}
	if !any_used {
		slots[0] = {
			used     = true,
			compound = u16(chemistry.Id.Water),
			ml       = PRACTICE_ML,
			practice = true,
		}
		chemistry.mix_add(&slots[0].mix, .Water, f32(PRACTICE_ML), carry.SINK_PURITY, carry.ROOM_C)
	}
	return
}

slot_usable :: proc(slots: ^[carry.LOADOUT_SLOTS]Slot, i: int) -> bool {
	return i >= 0 && i < carry.LOADOUT_SLOTS && slots[i].used
}

// Which balloon is chosen and how far a throw is charged.
Thrower :: struct {
	selected: int,
	charging: bool,
	charge:   f32, // from 0 to 1
	cooldown: f32, // seconds left before the next throw can start
}

// Starts with the first slot that holds a balloon.
thrower_init :: proc(t: ^Thrower, slots: ^[carry.LOADOUT_SLOTS]Slot) {
	t^ = {}
	for i in 0 ..< carry.LOADOUT_SLOTS {
		if slots[i].used {
			t.selected = i
			return
		}
	}
}

// Chooses a slot. Only a slot with a balloon in it can be chosen, and choosing one cancels
// a throw that was being charged.
thrower_select :: proc(t: ^Thrower, slots: ^[carry.LOADOUT_SLOTS]Slot, i: int) -> bool {
	if !slot_usable(slots, i) {
		return false
	}
	t.selected = i
	t.charging = false
	t.charge = 0
	return true
}

// Lets go of a throw that was being charged without throwing it, as when the player is knocked
// out with a balloon in the hand.
thrower_cancel :: proc(t: ^Thrower) {
	t.charging = false
	t.charge = 0
}

// Whether the throw button would start a throw right now. The button shows this before it
// is pressed.
thrower_ready :: proc(t: ^Thrower, slots: ^[carry.LOADOUT_SLOTS]Slot) -> bool {
	return slot_usable(slots, t.selected) && t.cooldown <= 0
}

// Runs a frame of the throw button. Holding it charges the throw and letting go throws,
// at the power the charge reached. A tap is the weakest throw.
thrower_update :: proc(t: ^Thrower, slots: ^[carry.LOADOUT_SLOTS]Slot, held: bool, dt: f32) -> (fire: bool, power: u8) {
	t.cooldown = max(t.cooldown - dt, 0)
	switch {
	case t.charging && held:
		t.charge = charge_step(t.charge, dt)
	case t.charging:
		fire = slot_usable(slots, t.selected)
		power = charge_power(t.charge)
		t.charging = false
		t.charge = 0
		if fire {
			t.cooldown = THROW_COOLDOWN
		}
	case held && thrower_ready(t, slots):
		t.charging = true
		t.charge = charge_step(0, dt)
	}
	return
}

// The angle `a` turned `t` of the short way round to `b`, in radians. Headings wrap, so
// 350 degrees to 10 degrees goes through 0 and not back through 180.
lerp_angle :: proc(a, b, t: f32) -> f32 {
	d := math.mod(b - a + math.PI, math.TAU)
	if d < 0 {
		d += math.TAU
	}
	return a + (d - math.PI) * t
}

// Fills the players and balloons of `out` with what they were between two ticks: `alpha`
// of the way from `prev` to `curr`, which are consecutive ticks. The simulation ticks at
// its own pace, and drawing between ticks keeps things moving smoothly at any frame rate.
// A player or balloon that `prev` does not have is placed where `curr` has it. The bursts
// of `out` are left alone.
view_blend :: proc(out, prev, curr: ^Match_View, alpha: f32) {
	t := clamp(alpha, 0, 1)
	out.tick = curr.tick
	out.player_count = curr.player_count
	for i in 0 ..< curr.player_count {
		c := curr.players[i]
		out.players[i] = c
		for j in 0 ..< prev.player_count {
			p := prev.players[j]
			if p.id == c.id {
				out.players[i].pos = p.pos + (c.pos - p.pos) * t
				out.players[i].yaw = lerp_angle(p.yaw, c.yaw, t)
				break
			}
		}
	}
	out.balloon_count = curr.balloon_count
	for i in 0 ..< curr.balloon_count {
		c := curr.balloons[i]
		out.balloons[i] = c
		for j in 0 ..< prev.balloon_count {
			p := prev.balloons[j]
			if p.id == c.id {
				out.balloons[i].pos = p.pos + (c.pos - p.pos) * t
				break
			}
		}
	}
}
