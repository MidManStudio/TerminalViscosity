// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "player.odin"
// ============================================================================

package lab

import "core:math"

PLAYER_RADIUS :: f32(0.3)
EYE_HEIGHT :: f32(1.6)
WALK_SPEED :: f32(3.2) // metres per second at full stick
PITCH_LIMIT :: f32(1.25) // radians up or down
MAX_STEP :: f32(0.15) // the longest distance moved in one piece, so no counter is skipped over
JUMP_SPEED :: f32(3.0) // metres per second upward at take-off, about a 46 cm jump
GRAVITY :: f32(9.8)

// A walker seen from above, with a view direction. Yaw 0 looks toward -z and a
// positive yaw turns toward +x.
Player :: struct {
	x, z:  f32,
	yaw:   f32,
	pitch: f32,
	jump:  f32, // how far the eye is above its standing height, in metres
	vy:    f32, // how fast the eye is rising, in metres per second
}

player_init :: proc(p: ^Player, l: ^Layout) {
	p^ = {x = l.spawn.x, z = l.spawn.z, yaw = l.spawn_yaw}
}

// Height of the eye above the floor, including a jump in progress.
player_eye_y :: proc(p: ^Player) -> f32 {
	return EYE_HEIGHT + p.jump
}

// Starts a jump. Only works standing on the floor, so there is no double jump.
player_jump :: proc(p: ^Player) -> bool {
	if p.jump > 0 || p.vy != 0 {
		return false
	}
	p.vy = JUMP_SPEED
	return true
}

// Moves the eye up and down for a jump in progress. A jump is too low to get
// onto a counter, so it only changes the height of the view, and walking and
// collision stay as they are.
player_update_air :: proc(p: ^Player, dt: f32) {
	if p.jump <= 0 && p.vy == 0 {
		return
	}
	p.vy -= GRAVITY * dt
	p.jump += p.vy * dt
	if p.jump <= 0 {
		p.jump = 0
		p.vy = 0
	}
}

// Turns the view. Looking up is a positive pitch.
player_look :: proc(p: ^Player, d_yaw, d_pitch: f32) {
	p.yaw += d_yaw
	p.pitch = clamp(p.pitch + d_pitch, -PITCH_LIMIT, PITCH_LIMIT)
}

// Direction of the view, as a unit vector.
player_forward :: proc(p: ^Player) -> Vec3 {
	cp := math.cos(p.pitch)
	return {math.sin(p.yaw) * cp, math.sin(p.pitch), -math.cos(p.yaw) * cp}
}

// Walking directions on the floor: forward is where the view points without
// looking up or down, and right is a quarter turn clockwise from it.
player_flat_forward :: proc(p: ^Player) -> [2]f32 {
	return {math.sin(p.yaw), -math.cos(p.yaw)}
}

player_flat_right :: proc(p: ^Player) -> [2]f32 {
	return {math.cos(p.yaw), math.sin(p.yaw)}
}

// Whether a player centered at (x, z) would overlap a counter or leave the room.
blocked :: proc(l: ^Layout, x, z: f32) -> bool {
	r := PLAYER_RADIUS
	if abs(x) > ROOM_W * 0.5 - r || abs(z) > ROOM_D * 0.5 - r {
		return true
	}
	for i in 0 ..< l.collider_count {
		c := l.colliders[i]
		nearest_x := clamp(x, c.min_x, c.max_x)
		nearest_z := clamp(z, c.min_z, c.max_z)
		dx, dz := x - nearest_x, z - nearest_z
		if dx * dx + dz * dz < r * r {
			return true
		}
	}
	return false
}

// Walks for `dt` seconds. `wish` is the stick, with a length of at most 1, in
// floor coordinates. Each axis is tried on its own, so walking into a counter at
// an angle slides along it instead of stopping dead.
player_move :: proc(p: ^Player, l: ^Layout, wish: [2]f32, dt: f32) {
	length := math.sqrt(wish.x * wish.x + wish.y * wish.y)
	if length < 1e-4 || dt <= 0 {
		return
	}
	scale := min(length, 1) / length
	total := [2]f32{wish.x * scale * WALK_SPEED * dt, wish.y * scale * WALK_SPEED * dt}
	distance := math.sqrt(total.x * total.x + total.y * total.y)
	pieces := max(1, int(math.ceil(distance / MAX_STEP)))
	step := [2]f32{total.x / f32(pieces), total.y / f32(pieces)}
	for _ in 0 ..< pieces {
		if !blocked(l, p.x + step.x, p.z) {
			p.x += step.x
		}
		if !blocked(l, p.x, p.z + step.y) {
			p.z += step.y
		}
	}
}
