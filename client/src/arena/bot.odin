// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "bot.odin"
// ============================================================================

package arena

import "core:math"

BOT_RADIUS :: f32(12) // metres from the middle beyond which the bot turns back toward it
BOT_STICK :: f32(0.6) // how far the bot pushes the stick, so it walks and does not run
BOT_PAUSE_EVERY :: f32(7.5) // seconds between the times it stops
BOT_PAUSE :: f32(1.5) // how long it stands still
BOT_JUMP_EVERY :: f32(5)
BOT_JUMP_HELD :: f32(0.15) // seconds the jump button is held, a tap
BOT_THROW_EVERY :: f32(4)
BOT_THROW_PITCH :: f32(0.45) // radians up, so a balloon lands some way off
BOT_THROW_POWER :: u8(110)

// A stand-in for another player: it wanders the sand, stops now and then, jumps, and throws a
// balloon straight ahead every few seconds. It decides from where it is and how long it has been
// going, and gives what any client gives: an input and, now and then, a throw. It exists so that
// there is somebody to look at while the match has only one human.
Bot :: struct {
	heading: f32, // radians, 0 faces -z
	t:       f32, // seconds it has been going
	thrown:  int, // throws made so far
}

// One step of `dt` seconds for a bot standing at `pos`. Returns what it does with the controls,
// and whether it throws a balloon this step, along `look_dir({yaw, BOT_THROW_PITCH})`.
bot_step :: proc(b: ^Bot, pos: Vec3, dt: f32) -> (input: Input, throw: bool) {
	b.t += dt
	// A slow wander: the heading drifts one way and then the other.
	b.heading += 0.6 * math.sin(b.t * 0.37) * dt
	// Too far out, it turns for the middle: the heading that looks at it.
	if pos.x * pos.x + pos.z * pos.z > BOT_RADIUS * BOT_RADIUS {
		want := math.atan2(-pos.x, pos.z)
		b.heading = lerp_angle(b.heading, want, min(dt * 2, 1))
	}
	b.heading = math.mod(b.heading + 2 * math.PI, 2 * math.PI)

	paused := math.mod(b.t, BOT_PAUSE_EVERY) < BOT_PAUSE
	input = {
		forward = paused ? 0 : BOT_STICK,
		yaw     = b.heading,
		jump    = math.mod(b.t, BOT_JUMP_EVERY) < BOT_JUMP_HELD,
	}
	due := int(b.t / BOT_THROW_EVERY)
	if due > b.thrown {
		b.thrown = due
		throw = true
	}
	return
}
