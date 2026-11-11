// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "touch.odin"
// ============================================================================

package touch

import "core:math"

MAX_FINGERS :: 8 // fingers followed at once; a ninth is not followed until one lifts
MAX_BUTTONS :: 32 // buttons are numbered 0 to 31, one bit each in a u32; a finger on a later one holds it but is never reported

STICK_SIDE :: f32(0.5) // the left share of the screen where a finger starts the walking stick
STICK_RADIUS_OF_HEIGHT :: f32(0.19) // the ring is this share of the screen height, as in Tower-Of-Babylon (87 of 450)
STICK_DEAD_ZONE :: f32(0.08) // the share of the ring that does nothing, then rescaled so its edge reads zero
LOOK_CAP_OF_HEIGHT :: f32(0.2) // the most one frame may turn the view, as a share of the screen height

// A finger on the screen, or the mouse while its button is held. The id stays the same
// for as long as it is down.
Finger :: struct {
	id:  int,
	pos: [2]f32,
}

// The job a finger was given when it landed. It keeps the job until it lifts, wherever it
// wanders: a look finger that slides over a button does not press it, and a stick finger
// that drifts into the right half is still the stick.
Role :: enum u8 {
	None,
	Ignore, // a spare finger: a second one for a job that has one already, or one that was down at the start
	Stick,
	Look,
	Button,
}

Slot :: struct {
	used:   bool,
	fresh:  bool, // this frame is the first one of the finger
	id:     int,
	role:   Role,
	button: int, // which button, for the Button role
	last:   [2]f32,
}

State :: struct {
	slots:  [MAX_FINGERS]Slot,
	anchor: [2]f32, // the middle of the walking stick while a finger holds it
}

// What the game says about this frame.
Screen :: struct {
	w, h:          f32,
	buttons:       [][4]f32, // boxes (x, y, width, height); a finger that lands in one holds that button
	aim_mask:      u32, // buttons whose finger also turns the view as it moves, like a fire pad
	stick_enabled: bool, // false on a desktop, where the left of the screen is for looking too
}

Out :: struct {
	stick:        [2]f32, // from -1 to 1 on each axis, y is down, after the dead zone
	stick_active: bool,
	anchor:       [2]f32, // for drawing: the middle of the ring
	knob:         [2]f32, // and where the knob is, never farther than the ring's radius from the middle
	look:         [2]f32, // pixels the view is to turn this frame
	look_active:  bool,
	pressed:      u32, // bit i: button i had a finger land this frame
	held:         u32, // bit i: a finger is down on button i
}

// The ring of the walking stick, and how far the knob travels, in pixels.
stick_radius :: proc(h: f32) -> f32 {
	return h * STICK_RADIUS_OF_HEIGHT
}

// The most the view may be turned by one frame of finger movement, in pixels, so a frame
// that arrives with a jump in it does not throw the view across the arena.
look_cap :: proc(h: f32) -> f32 {
	return h * LOOK_CAP_OF_HEIGHT
}

// Where the walking stick's middle goes for a finger landing at `p`: under the finger, but
// kept far enough in that the whole ring stays on the screen and inside the left part.
anchor_for :: proc(p: [2]f32, w, h: f32) -> [2]f32 {
	r := stick_radius(h)
	return {clamp(p.x, r * 1.14, w * STICK_SIDE - r * 0.69), clamp(p.y, h * 0.355, h - r)}
}

// Starts the state. A finger that is already down, such as the one that just tapped a button
// in the previous scene, is a spare finger until it lifts, so it cannot press anything here.
init :: proc(s: ^State, fingers: []Finger) {
	s^ = {}
	for i in 0 ..< min(len(fingers), MAX_FINGERS) {
		s.slots[i] = {
			used = true,
			id   = fingers[i].id,
			role = .Ignore,
			last = fingers[i].pos,
		}
	}
}

has_role :: proc(s: ^State, role: Role) -> bool {
	for sl in s.slots {
		if sl.used && sl.role == role {
			return true
		}
	}
	return false
}

button_taken :: proc(s: ^State, button: int) -> bool {
	for sl in s.slots {
		if sl.used && sl.role == .Button && sl.button == button {
			return true
		}
	}
	return false
}

// Which job a finger landing at `p` is given. Buttons come first, then the walking stick on
// the left, then the look finger on the right. A job that has a finger already makes a
// second one a spare. Where buttons overlap, the later one in the list wins.
assign :: proc(s: ^State, p: [2]f32, screen: Screen) -> (role: Role, button: int) {
	hit := -1
	for b, i in screen.buttons {
		if p.x >= b.x && p.x <= b.x + b.z && p.y >= b.y && p.y <= b.y + b.w {
			hit = i
		}
	}
	if hit >= 0 {
		if button_taken(s, hit) {
			return .Ignore, -1
		}
		return .Button, hit
	}
	if screen.stick_enabled && p.x < screen.w * STICK_SIDE {
		if has_role(s, .Stick) {
			return .Ignore, -1
		}
		s.anchor = anchor_for(p, screen.w, screen.h)
		return .Stick, -1
	}
	if has_role(s, .Look) {
		return .Ignore, -1
	}
	return .Look, -1
}

// Runs once a frame with every finger that is down (an empty list when none is, which is
// what lifts them): lifted fingers give up their jobs, new fingers get one, and each finger
// with a job says what it is doing. Fingers past the eight slots are not followed until a slot is
// free.
update :: proc(s: ^State, fingers: []Finger, screen: Screen) -> (out: Out) {
	count := len(fingers)

	for &sl in s.slots {
		if !sl.used {
			continue
		}
		still := false
		for i in 0 ..< count {
			if fingers[i].id == sl.id {
				still = true
				break
			}
		}
		if !still {
			sl = {}
		}
	}

	for i in 0 ..< count {
		known := false
		for sl in s.slots {
			if sl.used && sl.id == fingers[i].id {
				known = true
				break
			}
		}
		if known {
			continue
		}
		free := -1
		for sl, k in s.slots {
			if !sl.used {
				free = k
				break
			}
		}
		if free < 0 {
			continue
		}
		role, button := assign(s, fingers[i].pos, screen)
		s.slots[free] = {
			used   = true,
			fresh  = true,
			id     = fingers[i].id,
			role   = role,
			button = button,
			last   = fingers[i].pos,
		}
	}

	for &sl in s.slots {
		if !sl.used {
			continue
		}
		pos := sl.last
		for i in 0 ..< count {
			if fingers[i].id == sl.id {
				pos = fingers[i].pos
				break
			}
		}
		move := pos - sl.last
		switch sl.role {
		case .None, .Ignore:
		case .Stick:
			out.stick_active = true
			out.anchor = s.anchor
			r := stick_radius(screen.h)
			d := pos - s.anchor
			length := math.sqrt(d.x * d.x + d.y * d.y)
			dir := [2]f32{}
			if length > 0.001 {
				dir = d / length
			}
			out.knob = s.anchor + dir * min(length, r)
			if r > 0 {
				mag := min(length / r, 1)
				if mag > STICK_DEAD_ZONE {
					out.stick = dir * ((mag - STICK_DEAD_ZONE) / (1 - STICK_DEAD_ZONE))
				}
			}
		case .Look:
			out.look_active = true
			out.look += move
		case .Button:
			bit := u32(1) << u32(sl.button)
			out.held |= bit
			if sl.fresh {
				out.pressed |= bit
			}
			if screen.aim_mask & bit != 0 {
				out.look += move
			}
		}
		sl.last = pos
		sl.fresh = false
	}

	limit := look_cap(screen.h)
	reach := math.sqrt(out.look.x * out.look.x + out.look.y * out.look.y)
	if reach > limit {
		out.look *= limit / reach
	}
	return
}
