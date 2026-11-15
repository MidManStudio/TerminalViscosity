// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "host_local.odin"
// ============================================================================

package main

import "arena"
import "chemistry"
import "core:math"

TICK_DT :: f32(1.0 / 60.0) // the simulation's tick, tv_sim::DT
MAX_HOST_TICKS :: 8 // the most ticks one step may run, so a slow frame does not make the next slower
MAX_BOTS :: arena.MAX_PLAYERS - 1 // every player but the local one

// A stand-in for another player: its brain and the player id it plays as.
Host_Bot :: struct {
	bot: arena.Bot,
	id:  u8,
}

// The match host that runs the Rust world in this process, through the C ABI the server
// will use too. Everything the scene learns comes back out of the wire format, decoded
// by the Rust library, so what the client sees is what a network client would see. The
// world ticks on its own clock: the host keeps time, steps it as often as the frames
// ask, and hands out the players and balloons drawn between the last two ticks.
Local_Host :: struct {
	world:      ^TvWorld,
	player:     u8, // the player this client is
	input:      arena.Input, // the latest stick and heading, sent again every tick
	has_input:  bool,
	bots:       [MAX_BOTS]Host_Bot, // the stand-ins for other players, the first `bot_count` of them
	bot_count:  int,
	pending:    f32, // seconds of the frame clock not yet stepped
	prev, curr: arena.Match_View, // the last two ticks
	out:        arena.Match_View, // what the scene is shown
	snap:       [1200]u8,
	events:     [1200]u8,
	balloons:   [arena.MAX_BALLOONS]TvBalloonView,
	players:    [arena.MAX_PLAYERS]TvPlayerView,
	dets:       [arena.MAX_BURSTS]TvDetonateView,
}

// Starts a match with `player` already standing on its spawn point, and with `bots` stand-in
// players after it (the next ids, up to MAX_BOTS), which the host drives like clients would.
// Returns nil if the library cannot make a world.
local_host_new :: proc(seed: u64, player: u8, bots := 0) -> ^Local_Host {
	h := new(Local_Host)
	h.world = tv_world_new(seed)
	if h.world == nil {
		free(h)
		return nil
	}
	h.player = player
	if tv_world_join(h.world, player) != TV_OK || !local_read(h, &h.curr) {
		tv_world_free(h.world)
		free(h)
		return nil
	}
	for i in 0 ..< clamp(bots, 0, MAX_BOTS) {
		id := u8((int(player) + 1 + i) % arena.MAX_PLAYERS)
		if tv_world_join(h.world, id) != TV_OK || !local_read(h, &h.curr) {
			tv_world_free(h.world)
			free(h)
			return nil
		}
		// Each starts facing the middle, as the match placed it, and plays its own game for each
		// seed. The first bot's numbers are the ones a match with a single bot always had.
		h.bots[i].id = id
		h.bots[i].bot = arena.bot_new(u32(seed) ~ 0x9E3779B9 ~ (u32(i) * 0x85EBCA6B))
		if p, found := arena.view_player(&h.curr, id); found {
			h.bots[i].bot.heading = p.yaw
		}
		h.bot_count += 1
	}
	h.prev = h.curr
	arena.view_blend(&h.out, &h.prev, &h.curr, 1)
	return h
}

local_host_free :: proc(h: ^Local_Host) {
	if h == nil {
		return
	}
	tv_world_free(h.world)
	free(h)
}

local_host_table :: proc(h: ^Local_Host) -> arena.Host {
	return {data = h, submit_input = local_submit_input, submit_throw = local_submit_throw, step = local_step, view = local_view}
}

// Reads the world's snapshot into `view`, leaving its bursts alone. False if the library
// refused, which would be a bug in one of the two sides.
local_read :: proc(h: ^Local_Host, view: ^arena.Match_View) -> bool {
	n := tv_world_snapshot(h.world, raw_data(h.snap[:]), len(h.snap))
	if n <= 0 {
		return false
	}
	tick: u32
	bc := tv_snapshot_decode(raw_data(h.snap[:]), u32(n), raw_data(h.balloons[:]), len(h.balloons), &tick)
	pc := tv_snapshot_decode_players(raw_data(h.snap[:]), u32(n), raw_data(h.players[:]), len(h.players))
	if bc < 0 || pc < 0 {
		return false
	}
	view.tick = tick
	view.player_count = int(pc)
	for i in 0 ..< int(pc) {
		p := h.players[i]
		view.players[i] = {
			id  = p.id,
			pos = {f32(p.pos_mm[0]), f32(p.pos_mm[1]), f32(p.pos_mm[2])} * 0.001,
			yaw = f32(p.yaw_mrad) * 0.001,
			hp  = p.hp,
		}
	}
	view.balloon_count = int(bc)
	for i in 0 ..< int(bc) {
		b := h.balloons[i]
		view.balloons[i] = {
			id       = b.id,
			owner    = b.owner,
			slot     = b.flags,
			compound = b.compound,
			pos      = {f32(b.pos_mm[0]), f32(b.pos_mm[1]), f32(b.pos_mm[2])} * 0.001,
			vel      = {f32(b.vel_cms[0]), f32(b.vel_cms[1]), f32(b.vel_cms[2])} * 0.01,
		}
	}
	return true
}

local_submit_input :: proc(data: rawptr, input: arena.Input) {
	h := cast(^Local_Host)data
	h.input = input
	h.has_input = true
}

// Sends an input for `player` to the world. Run once for every tick, so the world keeps walking
// the player for as long as the sticks are held.
local_send :: proc(h: ^Local_Host, player: u8, input: arena.Input) {
	stick :: proc(v: f32) -> i8 {
		return i8(clamp(math.round(v * 127), -127, 127))
	}
	cmd: [16]u8
	buttons := input.jump ? TV_BUTTON_JUMP : 0
	n := tv_encode_input(stick(input.forward), stick(input.strafe), i32(math.round(input.yaw * 1000)), buttons, raw_data(cmd[:]), len(cmd))
	if n > 0 {
		tv_world_submit(h.world, player, raw_data(cmd[:]), u32(n))
	}
}

local_send_input :: proc(h: ^Local_Host) {
	if h.has_input {
		local_send(h, h.player, h.input)
	}
}

local_throw :: proc(h: ^Local_Host, player: u8, throw: arena.Throw) -> bool {
	chamber := TvChamber{compound = throw.compound, volume_ml = throw.ml}
	dir := arena.dir_wire(throw.dir)
	cmd: [64]u8
	n := tv_encode_throw(&chamber, 1, throw.slot, dir.x, dir.y, dir.z, throw.power, raw_data(cmd[:]), len(cmd))
	if n <= 0 {
		return false
	}
	return tv_world_submit(h.world, player, raw_data(cmd[:]), u32(n)) == TV_OK
}

local_submit_throw :: proc(data: rawptr, throw: arena.Throw) -> bool {
	h := cast(^Local_Host)data
	return local_throw(h, h.player, throw)
}

// What each bot does this tick: it looks at the match as of the last tick, and sends an input and
// now and then a throw, as a client would. A water balloon of the size the practice balloon is.
local_bot_tick :: proc(h: ^Local_Host) {
	for i in 0 ..< h.bot_count {
		b := &h.bots[i]
		act := arena.bot_step(&b.bot, &h.curr, b.id, TICK_DT)
		local_send(h, b.id, act.input)
		if act.throw {
			local_throw(h, b.id, {slot = 0, compound = u16(chemistry.Id.Water), ml = arena.PRACTICE_ML, dir = act.dir, power = act.power})
		}
	}
}

local_step :: proc(data: rawptr, dt: f32) {
	h := cast(^Local_Host)data
	h.out.burst_count = 0
	h.pending = min(h.pending + dt, MAX_HOST_TICKS * TICK_DT)
	for h.pending >= TICK_DT {
		h.pending -= TICK_DT
		local_send_input(h)
		local_bot_tick(h)
		tv_world_step(h.world)
		h.prev = h.curr
		local_read(h, &h.curr)
		local_take_bursts(h)
	}
	arena.view_blend(&h.out, &h.prev, &h.curr, h.pending / TICK_DT)
}

// Collects what burst during the tick that just ran.
local_take_bursts :: proc(h: ^Local_Host) {
	n := tv_world_take_events(h.world, raw_data(h.events[:]), len(h.events))
	if n <= 0 {
		return
	}
	count := tv_events_decode(raw_data(h.events[:]), u32(n), raw_data(h.dets[:]), len(h.dets))
	for i in 0 ..< max(int(count), 0) {
		if h.out.burst_count == arena.MAX_BURSTS {
			return
		}
		d := h.dets[i]
		h.out.bursts[h.out.burst_count] = {
			balloon    = d.balloon,
			compound   = d.compound,
			volatility = f32(d.volatility_q) / 255,
			pos        = {f32(d.pos_mm[0]), f32(d.pos_mm[1]), f32(d.pos_mm[2])} * 0.001,
			radius     = f32(d.radius_mm) * 0.001,
		}
		h.out.burst_count += 1
	}
}

local_view :: proc(data: rawptr) -> ^arena.Match_View {
	return &(cast(^Local_Host)data).out
}
