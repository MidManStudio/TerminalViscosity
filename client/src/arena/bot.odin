// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "bot.odin"
// ============================================================================

package arena

import "core:math"

// All of these are first guesses, to be tuned by playing.
BOT_TURN_RATE :: f32(3.2) // radians a second it can turn to face a target
BOT_NOTICE :: f32(0.35) // seconds a target has to have been in view before it first throws
BOT_RANGE_NEAR :: f32(6) // closer than this to its target it backs away
BOT_RANGE_FAR :: f32(11) // farther than this it closes in
BOT_RANGE_EASE :: f32(2) // metres over which backing away and closing in grow to full push
BOT_WOUNDED :: u8(30) // at or below this many hit points it keeps its distance
BOT_WOUNDED_NEAR :: f32(10)
BOT_WOUNDED_FAR :: f32(15)
BOT_CIRCLE :: f32(0.8) // how hard it circles its target when it is at a good range
BOT_STICK :: f32(0.9) // the most it pushes the stick, so it walks a little under full speed
BOT_FLIP_CHANCE :: f32(0.7) // the chance that it turns the other way round when its circling timer runs out
BOT_STRAFE_MIN :: f32(1)
BOT_STRAFE_MAX :: f32(2.5)
BOT_DODGE_RANGE :: f32(7) // a balloon coming at it from nearer than this along its path is dodged
BOT_DODGE_WIDTH :: f32(1.8) // and only when its path passes this close to the bot
BOT_DODGE :: f32(2) // how hard it sidesteps, more than anything else it wants
BOT_DODGE_CHANCE :: f32(0.4) // the chance that it sees a balloon coming at it at all, decided once for each balloon
BOT_REACT_MIN :: f32(0.25) // seconds between seeing a balloon and starting to move out of its way
BOT_REACT_MAX :: f32(0.45)
BOT_DODGE_REST :: f32(1.2) // seconds after it last sidestepped in which it sees no new balloon coming
BOT_AWARE :: 8 // balloons it keeps track of at once
BOT_WALL :: f32(16.5) // metres from the middle beyond which it steers back inward
BOT_HOME :: f32(3) // with nobody to fight it goes back to within this of the middle
BOT_JUMP_MIN :: f32(2.5)
BOT_JUMP_MAX :: f32(6)
BOT_JUMP_HELD :: f32(0.15) // seconds the jump button is held, a tap
BOT_THROW_MIN :: f32(3) // closest and farthest it throws at
BOT_THROW_MAX :: f32(18)
BOT_GAP_MIN :: f32(2.2) // seconds between one throw and the next
BOT_GAP_MAX :: f32(4)
BOT_AIM_TOLERANCE :: f32(0.12) // radians off its aim that it may be and still let go
BOT_SPREAD_BASE :: f32(0.012) // radians of aim error at no distance
BOT_SPREAD_PER_M :: f32(0.005) // and more for every metre to the target
BOT_LEAD :: f32(0.9) // how much of its target's motion it leads by
BOT_VEL_SMOOTH :: f32(8) // how quickly its idea of the target's speed follows what it sees, per second
BOT_LEAD_PASSES :: 3
BOT_SPEED_MIN :: f32(6) // m/s, a tap, the weakest throw
BOT_SPEED_MAX :: f32(18) // m/s, fully charged
BOT_HAND_HEIGHT :: f32(1.5) // tv_sim's THROW_HEIGHT_M: where a balloon leaves the hand
BOT_HAND_REACH :: f32(0.5) // tv_sim's THROW_REACH_M: how far along the aim it starts
BOT_CHEST :: f32(1.1) // metres above the target's feet that it aims at
GRAVITY :: f32(9.81) // tv_sim::GRAVITY

// What a bot knows about one balloon that was heading its way. `sees` is whether it ever
// noticed that balloon, which is decided once, when the balloon first comes at it, and `wait` is
// how many seconds are left before it starts to move.
Aware :: struct {
	id:   u16,
	sees: bool,
	wait: f32,
}

// A stand-in for another player. It looks at the match like a client would, picks the nearest
// player still standing, turns to face where a balloon has to be sent to meet them, keeps a
// range at which it can throw and be thrown at, circles instead of standing still, sidesteps
// balloons coming at it, stays off the wall, and throws now and then. It gives back what any
// client gives: an input and, once in a while, a throw. It exists so that there is somebody to
// fight while the match has only one human.
Bot :: struct {
	heading:     f32, // radians, 0 faces -z
	t:           f32, // seconds it has been going
	rng:         u32, // its own random numbers, so that two runs of a match go the same way
	sloppy:      f32, // how much aim error it makes, 1 as it is played and 0 for none
	dodge_chance: f32, // the chance that it sees a balloon coming at it, BOT_DODGE_CHANCE as it is played, 1 to see every one
	react_min:   f32, // the shortest and longest it takes to start moving once it has seen one
	react_max:   f32,
	rest:        f32, // seconds left in which it sees no new balloon, after a sidestep
	aware:       [BOT_AWARE]Aware,
	aware_count: int,
	target:      int, // the id of the player it is after, or -1
	seen:        f32, // seconds it has been after this target
	have_last:   bool,
	last_pos:    Vec3, // where the target was a step ago
	target_vel:  Vec3, // how fast it thinks the target moves, metres a second (only x and z are used)
	strafe_dir:  f32, // 1 or -1, which way round it circles
	strafe_left: f32, // seconds before it may change its mind
	throw_in:    f32, // seconds before it may throw again
	jump_in:     f32,
	jump_hold:   f32,
	thrown:      int, // throws made so far
}

// What the bot does in one step: the controls, and whether it throws, with the aim and power.
Bot_Act :: struct {
	input: Input,
	throw: bool,
	dir:   Vec3, // a unit vector, when it throws
	power: u8, // from POWER_MIN to POWER_MAX, when it throws
}

// A bot with its own random numbers drawn from `seed`.
bot_new :: proc(seed: u32) -> (b: Bot) {
	b.rng = seed | 1 // xorshift never leaves 0
	b.sloppy = 1
	b.dodge_chance = BOT_DODGE_CHANCE
	b.react_min = BOT_REACT_MIN
	b.react_max = BOT_REACT_MAX
	b.target = -1
	b.strafe_dir = 1
	b.throw_in = bot_between(&b, 1, 2)
	b.jump_in = bot_between(&b, BOT_JUMP_MIN, BOT_JUMP_MAX)
	return
}

// A random number from 0 up to but not including 1.
bot_rand :: proc(b: ^Bot) -> f32 {
	x := b.rng
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5
	b.rng = x
	return f32(x >> 8) / f32(1 << 24)
}

bot_between :: proc(b: ^Bot, lo, hi: f32) -> f32 {
	return lo + (hi - lo) * bot_rand(b)
}

// The signed short way round from the angle `a` to the angle `b`, in radians, from -pi to pi.
angle_diff :: proc(a, b: f32) -> f32 {
	d := math.mod(b - a + math.PI, math.TAU)
	if d < 0 {
		d += math.TAU
	}
	return d - math.PI
}

// The pitch, in radians above level, that sends something launched at `speed` m/s to a point `x`
// metres away along the ground and `y` metres up from where it started, the flatter way of the
// two that there are. False when it cannot get there at that speed.
ballistic_pitch :: proc(speed, x, y: f32) -> (pitch: f32, ok: bool) {
	if x <= 0 || speed <= 0 {
		return 0, false
	}
	v2 := speed * speed
	disc := v2 * v2 - GRAVITY * (GRAVITY * x * x + 2 * y * v2)
	if disc < 0 {
		return 0, false
	}
	return math.atan((v2 - math.sqrt(disc)) / (GRAVITY * x)), true
}

// The speed and pitch of a throw that reaches `x` metres out and `y` up. It uses a speed that
// leaves a flat arc, which forgives a small error in the distance, and the full speed if that
// falls short. The speed is a whole number of tenths of a metre a second, as the power is.
bot_launch :: proc(x, y: f32) -> (speed, pitch: f32, ok: bool) {
	speed = clamp(math.sqrt(GRAVITY * x) * 1.25, BOT_SPEED_MIN, BOT_SPEED_MAX)
	speed = math.round(speed * 10) / 10
	pitch, ok = ballistic_pitch(speed, x, y)
	if !ok {
		speed = BOT_SPEED_MAX
		pitch, ok = ballistic_pitch(speed, x, y)
	}
	return
}

// Where to throw from a player standing at `from` to hit one standing at `target` who is walking
// at `vel`, leading them by `lead` of the way: the heading, pitch and speed, if they can be
// reached. The balloon leaves the hand half a metre along the aim, which is half a metre forward
// and a little up, and flies by the simulation's gravity, so each pass solves for the flight time
// at the point where the last pass thought the target would be, with the pitch of the last pass
// for how far up the balloon starts. The half metre forward is taken as level: the difference
// with the pitch is under 3 cm and too small to matter.
bot_aim :: proc(from, target, vel: Vec3, lead: f32) -> (yaw, pitch, speed: f32, ok: bool) {
	pred := target
	pitch = 0.3 // a first guess at how steeply it throws, which the passes correct
	for _ in 0 ..< BOT_LEAD_PASSES {
		dx, dz := pred.x - from.x, pred.z - from.z
		x := max(math.sqrt(dx * dx + dz * dz) - BOT_HAND_REACH, 0.1)
		y := target.y + BOT_CHEST - (from.y + BOT_HAND_HEIGHT + BOT_HAND_REACH * math.sin(pitch))
		launched: bool
		speed, pitch, launched = bot_launch(x, y)
		if !launched {
			return 0, 0, 0, false
		}
		flight := x / (speed * math.cos(pitch))
		pred = {target.x + vel.x * flight * lead, target.y, target.z + vel.z * flight * lead}
	}
	return math.atan2(pred.x - from.x, -(pred.z - from.z)), pitch, speed, true
}

// One step of `dt` seconds for the player `me` of `view`.
bot_step :: proc(b: ^Bot, view: ^Match_View, me: u8, dt: f32) -> (act: Bot_Act) {
	b.t += dt
	b.rest = max(b.rest - dt, 0)
	self, found := view_player(view, me)
	if !found || knocked_out(self) {
		b.target = -1
		b.seen = 0
		b.aware_count = 0
		b.rest = 0
		act.input = {
			yaw = b.heading,
		}
		return
	}

	// The nearest other player who is still standing.
	best := -1
	best_d := f32(1e9)
	for i in 0 ..< view.player_count {
		p := view.players[i]
		if p.id == me || knocked_out(p) {
			continue
		}
		dx, dz := p.pos.x - self.pos.x, p.pos.z - self.pos.z
		if d := math.sqrt(dx * dx + dz * dz); d < best_d {
			best, best_d = i, d
		}
	}
	if best < 0 {
		return bot_alone(b, self, dt)
	}
	target := view.players[best]

	// Follows the target, and works out how fast it is going from how far it moved.
	if int(target.id) != b.target {
		b.target = int(target.id)
		b.seen = 0
		b.have_last = false
		b.target_vel = {}
	} else {
		b.seen += dt
	}
	if b.have_last && dt > 0 {
		moved := (target.pos - b.last_pos) / dt
		b.target_vel += (moved - b.target_vel) * min(dt * BOT_VEL_SMOOTH, 1)
	}
	b.last_pos = target.pos
	b.have_last = true

	// Turns, no faster than it can, to face the place a throw has to go.
	to_x, to_z := target.pos.x - self.pos.x, target.pos.z - self.pos.z
	dist := math.sqrt(to_x * to_x + to_z * to_z)
	aim_yaw, aim_pitch, aim_speed, reachable := bot_aim(self.pos, target.pos, b.target_vel, BOT_LEAD)
	want := reachable ? aim_yaw : math.atan2(to_x, -to_z)
	step := clamp(angle_diff(b.heading, want), -BOT_TURN_RATE * dt, BOT_TURN_RATE * dt)
	b.heading = math.mod(b.heading + step + math.TAU, math.TAU)

	// Where it wants to go on the floor, as an x and a z: to keep its range, around its target,
	// away from balloons coming at it, and in from the wall.
	dir := dist > 0.01 ? [2]f32{to_x / dist, to_z / dist} : [2]f32{0, -1}
	near, far := BOT_RANGE_NEAR, BOT_RANGE_FAR
	if self.hp <= BOT_WOUNDED {
		near, far = BOT_WOUNDED_NEAR, BOT_WOUNDED_FAR
	}
	radial := clamp((dist - far) / BOT_RANGE_EASE, 0, 1) - clamp((near - dist) / BOT_RANGE_EASE, 0, 1)
	b.strafe_left -= dt
	if b.strafe_left <= 0 {
		if bot_rand(b) < BOT_FLIP_CHANCE {
			b.strafe_dir = -b.strafe_dir
		}
		b.strafe_left = bot_between(b, BOT_STRAFE_MIN, BOT_STRAFE_MAX)
	}
	wish := dir * radial + [2]f32{-dir.y, dir.x} * (b.strafe_dir * BOT_CIRCLE * (1 - abs(radial)))
	wish += bot_dodge(b, view, me, self.pos, dt)
	wish += bot_inward(self.pos)
	wish = bot_limit(wish)

	act.input = bot_stick(wish, b.heading)
	act.input.jump = bot_jump(b, dt)

	// Throws when it faces the aim, the target is in reach, it has seen them for a moment, and its
	// last throw is long enough ago.
	b.throw_in = max(b.throw_in - dt, 0)
	aligned := abs(angle_diff(b.heading, want)) <= BOT_AIM_TOLERANCE
	in_reach := dist >= BOT_THROW_MIN && dist <= BOT_THROW_MAX
	if reachable && aligned && in_reach && b.seen >= BOT_NOTICE && b.throw_in <= 0 {
		spread := (BOT_SPREAD_BASE + BOT_SPREAD_PER_M * dist) * b.sloppy
		yaw := aim_yaw + (bot_rand(b) * 2 - 1) * spread
		pitch := aim_pitch + (bot_rand(b) * 2 - 1) * spread * 0.5
		act.throw = true
		act.dir = look_dir({yaw = yaw, pitch = pitch})
		act.power = u8(math.round(aim_speed * 10))
		b.throw_in = bot_between(b, BOT_GAP_MIN, BOT_GAP_MAX)
		b.thrown += 1
	}
	act.input.yaw = b.heading
	return
}

// With nobody left to fight: walks back to the middle and waits there.
bot_alone :: proc(b: ^Bot, self: Player_View, dt: f32) -> (act: Bot_Act) {
	b.target = -1
	b.seen = 0
	away := math.sqrt(self.pos.x * self.pos.x + self.pos.z * self.pos.z)
	if away > BOT_HOME {
		want := math.atan2(-self.pos.x, self.pos.z)
		step := clamp(angle_diff(b.heading, want), -BOT_TURN_RATE * dt, BOT_TURN_RATE * dt)
		b.heading = math.mod(b.heading + step + math.TAU, math.TAU)
		if abs(angle_diff(b.heading, want)) < 1 {
			act.input.forward = BOT_STICK * 0.6
		}
	}
	act.input.jump = bot_jump(b, dt)
	act.input.yaw = b.heading
	return
}

// How the bot taps the jump button now and then: whether it is held this step.
bot_jump :: proc(b: ^Bot, dt: f32) -> bool {
	b.jump_in -= dt
	if b.jump_in <= 0 {
		b.jump_hold = BOT_JUMP_HELD
		b.jump_in = bot_between(b, BOT_JUMP_MIN, BOT_JUMP_MAX)
	}
	held := b.jump_hold > 0
	b.jump_hold = max(b.jump_hold - dt, 0)
	return held
}

// A push away from the paths of the balloons coming at the bot: for each one of somebody else's
// that is still heading its way, close enough along its path, and passing close enough, a
// sidestep across the path, to whichever side the bot is already on. The bot does not see every
// balloon. When one first comes at it, it is decided once whether the bot sees it (`dodge_chance`,
// and never within BOT_DODGE_REST of its last sidestep), and a balloon it sees is dodged only
// after a reaction time between `react_min` and `react_max`. A balloon thrown from close by is
// therefore past it before it moves, and one it did not see is not dodged at all.
bot_dodge :: proc(b: ^Bot, view: ^Match_View, me: u8, pos: Vec3, dt: f32) -> (push: [2]f32) {
	bot_forget(b, view)
	for i in 0 ..< view.balloon_count {
		f := view.balloons[i]
		if f.owner == me {
			continue
		}
		rx, rz := pos.x - f.pos.x, pos.z - f.pos.z
		speed := math.sqrt(f.vel.x * f.vel.x + f.vel.z * f.vel.z)
		if speed < 0.5 {
			continue
		}
		along := (rx * f.vel.x + rz * f.vel.z) / speed // how far ahead of it the bot is, negative when it has passed
		if along <= 0 || along > BOT_DODGE_RANGE {
			continue
		}
		side := (-rx * f.vel.z + rz * f.vel.x) / speed // which side of its path the bot is on, and how far
		if abs(side) > BOT_DODGE_WIDTH {
			continue
		}
		known := bot_aware_of(b, f.id)
		if known == nil {
			continue
		}
		known.wait -= dt
		if !known.sees || known.wait > 0 {
			continue
		}
		b.rest = BOT_DODGE_REST
		sign := side >= 0 ? f32(1) : f32(-1)
		if abs(side) < 0.05 {
			sign = b.strafe_dir
		}
		push += [2]f32{-f.vel.z, f.vel.x} / speed * (sign * BOT_DODGE)
	}
	return
}

// What the bot knows about the balloon with this id. A balloon it has not met before gets its
// chance of being seen and its reaction time now. Nil when it is keeping track of as many as it
// can, and then it does not see this one.
bot_aware_of :: proc(b: ^Bot, id: u16) -> ^Aware {
	for i in 0 ..< b.aware_count {
		if b.aware[i].id == id {
			return &b.aware[i]
		}
	}
	if b.aware_count >= BOT_AWARE {
		return nil
	}
	sees := b.rest <= 0 && bot_rand(b) < b.dodge_chance
	b.aware[b.aware_count] = {
		id   = id,
		sees = sees,
		wait = bot_between(b, b.react_min, b.react_max),
	}
	b.aware_count += 1
	return &b.aware[b.aware_count - 1]
}

// Drops what the bot knew about balloons that have burst or gone, so that its list does not fill
// up and an id that comes round again is a new balloon.
bot_forget :: proc(b: ^Bot, view: ^Match_View) {
	i := 0
	for i < b.aware_count {
		gone := true
		for j in 0 ..< view.balloon_count {
			if view.balloons[j].id == b.aware[i].id {
				gone = false
				break
			}
		}
		if gone {
			b.aware_count -= 1
			b.aware[i] = b.aware[b.aware_count]
		} else {
			i += 1
		}
	}
}

// A push toward the middle that grows the farther out the bot is beyond BOT_WALL.
bot_inward :: proc(pos: Vec3) -> (push: [2]f32) {
	out := math.sqrt(pos.x * pos.x + pos.z * pos.z)
	if out > BOT_WALL {
		push = [2]f32{-pos.x, -pos.z} / out * min((out - BOT_WALL) / 1.5, 1.5)
	}
	return
}

// No longer than one.
bot_limit :: proc(v: [2]f32) -> [2]f32 {
	length := math.sqrt(v.x * v.x + v.y * v.y)
	if length > 1 {
		return v / length
	}
	return v
}

// The stick that walks the way of `wish` (an x and a z on the floor) for a player facing `heading`,
// at no more than BOT_STICK. Forward is where the heading points, and right is a quarter turn
// from it, as the simulation has them.
bot_stick :: proc(wish: [2]f32, heading: f32) -> (input: Input) {
	s, c := math.sin(heading), math.cos(heading)
	input.forward = (wish.x * s - wish.y * c) * BOT_STICK
	input.strafe = (wish.x * c + wish.y * s) * BOT_STICK
	return
}
