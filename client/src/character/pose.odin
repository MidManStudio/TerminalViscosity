// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "pose.odin"
// ============================================================================

package character

import "core:math"

WALK_SPEED :: f32(3.2) // the walking speed of the match, at which the swing is full
STRIDE :: f32(2.2) // radians of the walk cycle for each metre a second of speed, about 0.9 s for a step cycle at full speed
LEG_SWING :: f32(0.7) // radians each way at full speed
ARM_SWING :: f32(0.5)
BOB :: f32(0.03) // metres the body rises at each step
THROW_TIME :: f32(0.5) // seconds for the throwing arm to wind up, throw, and come back

// What a character is doing, as far as its body goes. The match says where a player is, and the
// body follows: how fast it moved, whether it is in the air, and whether it just threw.
Anim :: struct {
	phase:   f32, // where in the walk cycle, in radians
	speed:   f32, // the speed it walks at, smoothed so that stopping is not a snap
	air:     f32, // 0 on the floor to 1 in the air, smoothed
	throw_t: f32, // seconds since the throw began, or below 0 when there is none
}

anim_new :: proc() -> Anim {
	return {throw_t = -1}
}

// The angles of the moving parts, in radians. The swings are about the x axis, positive
// swinging the end of a hanging part toward the front.
Pose :: struct {
	arm_l, arm_r: f32,
	leg_l, leg_r: f32,
	arm_out:      f32, // how far both arms are held out from the sides, about the z axis
	lift:         f32, // metres the whole body is lifted by the walk
}

smooth :: proc(x: f32) -> f32 {
	t := clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
}

// Moves the animation on by `dt` seconds for a character that is moving at `speed` metres a
// second along the floor, and in the air or not.
anim_step :: proc(a: ^Anim, speed: f32, airborne: bool, dt: f32) {
	a.speed += (speed - a.speed) * min(dt * 10, 1)
	a.phase = math.mod(a.phase + dt * a.speed * STRIDE, 2 * math.PI)
	target: f32 = airborne ? 1 : 0
	a.air += (target - a.air) * min(dt * 12, 1)
	if a.throw_t >= 0 {
		a.throw_t += dt
		if a.throw_t >= THROW_TIME {
			a.throw_t = -1
		}
	}
}

// Starts the throw, from the wind-up.
anim_throw :: proc(a: ^Anim) {
	a.throw_t = 0
}

// The angle of the right arm through a throw: back and a little out for the wind-up, then
// fast up and forward over the head, then down again.
throw_angle :: proc(t: f32) -> f32 {
	switch {
	case t < 0 || t >= THROW_TIME:
		return 0
	case t < 0.2 * THROW_TIME / 0.5:
		return -1.3 * smooth(t / (0.2 * THROW_TIME / 0.5))
	case t < 0.35 * THROW_TIME / 0.5:
		return -1.3 + 3.7 * smooth((t - 0.2 * THROW_TIME / 0.5) / (0.15 * THROW_TIME / 0.5))
	}
	return 2.4 * (1 - smooth((t - 0.35 * THROW_TIME / 0.5) / (0.15 * THROW_TIME / 0.5)))
}

anim_pose :: proc(a: ^Anim) -> (p: Pose) {
	amp := clamp(a.speed / WALK_SPEED, 0, 1)
	walk := 1 - a.air
	s := math.sin(a.phase)
	p.leg_l = s * LEG_SWING * amp * walk
	p.leg_r = -p.leg_l
	p.arm_l = -s * ARM_SWING * amp * walk
	p.arm_r = s * ARM_SWING * amp * walk
	p.lift = BOB * abs(s) * amp * walk
	// In the air the legs are drawn up a little and the arms go out and forward.
	p.leg_l += a.air * 0.5
	p.leg_r -= a.air * 0.2
	p.arm_l += a.air * 0.6
	p.arm_r += a.air * 0.6
	p.arm_out = a.air * 0.5
	if a.throw_t >= 0 {
		p.arm_r = throw_angle(a.throw_t)
	}
	return
}

// The matrix of a part, given the one of the whole character: the part is turned about its pivot
// by its swing, and arms are held out by a little from the sides.
part_matrix :: proc(root: Mat, pose: Pose, part: Part) -> Mat {
	pivot := part_pivot(part)
	swing: f32
	out: f32
	lift: f32
	switch part {
	case .Body:
		lift = pose.lift
	case .Head:
		lift = pose.lift
	case .Arm_L:
		swing, out, lift = pose.arm_l, -(0.12 + pose.arm_out), pose.lift
	case .Arm_R:
		swing, out, lift = pose.arm_r, 0.12 + pose.arm_out, pose.lift
	case .Leg_L:
		swing = pose.leg_l
	case .Leg_R:
		swing = pose.leg_r
	}
	local := mat_mul(mat_translate(pivot + {0, lift, 0}), mat_mul(mat_rotate_x(swing), mat_rotate_z(out)))
	if part == .Body {
		local = mat_translate({0, lift, 0})
	}
	return mat_mul(root, local)
}
