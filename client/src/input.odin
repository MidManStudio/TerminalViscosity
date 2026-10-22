// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "input.odin"
// ============================================================================

package main

import "core:math"
import rl "vendor:raylib"

MAX_POINTERS :: 5

// A finger on the screen, or the mouse while its button is held. The id stays
// the same for as long as it is down.
Pointer :: struct {
	id:  int,
	pos: [2]f32,
}

Pointers :: struct {
	items: [MAX_POINTERS]Pointer,
	count: int,
}

// Movement and look controls. On a phone the first finger down on the left of
// the screen becomes a floating joystick, wherever it lands, and a finger
// down anywhere else turns the view. With a mouse there is no joystick, and
// the keyboard moves instead.
Controls :: struct {
	stick_id:     int,
	stick_origin: [2]f32,
	stick:        [2]f32, // from -1 to 1, y is down
	look_id:      int,
	look_last:    [2]f32,
	look_delta:   [2]f32, // pixels moved this frame
	button_id:    int, // a finger that landed on the button, kept out of the controls until it lifts
	tapped:       bool, // the button was pressed this frame
	// Which ids were down last frame, to tell a new finger from a held one.
	known:        [MAX_POINTERS]int,
	known_count:  int,
}

STICK_SIDE :: f32(0.4) // the left part of the screen where a finger starts the joystick

// Starts the controls. Any finger already down, such as the one that just
// tapped a button in the previous scene, is noted as known, so it is ignored
// until it lifts and cannot press anything in this scene.
controls_init :: proc(c: ^Controls, pointers: ^Pointers) {
	c^ = {}
	c.stick_id = -1
	c.look_id = -1
	c.button_id = -1
	c.known_count = pointers.count
	for i in 0 ..< pointers.count {
		c.known[i] = pointers.items[i].id
	}
}

// Pixels the joystick can be pushed.
stick_radius :: proc(w, h: f32) -> f32 {
	return min(w, h) * 0.14
}

// Reads the pointers and updates the joystick and look. `button` is a box
// (x, y, width, height) that a finger can press without moving or looking.
controls_update :: proc(c: ^Controls, pointers: ^Pointers, w, h: f32, button: [4]f32) {
	c.tapped = false
	c.look_delta = {}

	// Roles of fingers that lifted are released.
	still_down :: proc(pointers: ^Pointers, id: int) -> bool {
		for i in 0 ..< pointers.count {
			if pointers.items[i].id == id {
				return true
			}
		}
		return false
	}
	if c.stick_id != -1 && !still_down(pointers, c.stick_id) {
		c.stick_id = -1
		c.stick = {}
	}
	if c.look_id != -1 && !still_down(pointers, c.look_id) {
		c.look_id = -1
	}
	if c.button_id != -1 && !still_down(pointers, c.button_id) {
		c.button_id = -1
	}

	touch_layout := true
	when ODIN_PLATFORM_SUBTARGET != .Android {
		touch_layout = false
	}

	for i in 0 ..< pointers.count {
		p := pointers.items[i]
		is_new := true
		for k in 0 ..< c.known_count {
			if c.known[k] == p.id {
				is_new = false
			}
		}
		if is_new && c.stick_id != p.id && c.look_id != p.id && c.button_id != p.id {
			inside := p.pos.x >= button.x && p.pos.x <= button.x + button.z && p.pos.y >= button.y && p.pos.y <= button.y + button.w
			if inside {
				c.button_id = p.id
				c.tapped = true
			} else if touch_layout && c.stick_id == -1 && p.pos.x < w * STICK_SIDE {
				c.stick_id = p.id
				c.stick_origin = p.pos
			} else if c.look_id == -1 {
				c.look_id = p.id
				c.look_last = p.pos
			}
		}
		if p.id == c.stick_id {
			radius := stick_radius(w, h)
			d := p.pos - c.stick_origin
			length := math.sqrt(d.x * d.x + d.y * d.y)
			if length > radius {
				d *= radius / length
			}
			c.stick = d / radius
		} else if p.id == c.look_id {
			c.look_delta = p.pos - c.look_last
			c.look_last = p.pos
		}
	}

	c.known_count = pointers.count
	for i in 0 ..< pointers.count {
		c.known[i] = pointers.items[i].id
	}
}

// The ring where a thumb starts the joystick, and the stick itself while held.
controls_draw :: proc(c: ^Controls, w, h: f32) {
	when ODIN_PLATFORM_SUBTARGET == .Android {
		radius := stick_radius(w, h)
		if c.stick_id == -1 {
			rl.DrawCircleLines(i32(w * 0.16), i32(h * 0.72), radius, {255, 255, 255, 50})
			return
		}
		ox, oy := i32(c.stick_origin.x), i32(c.stick_origin.y)
		rl.DrawCircle(ox, oy, radius, {255, 255, 255, 28})
		rl.DrawCircleLines(ox, oy, radius, {255, 255, 255, 90})
		rl.DrawCircle(ox + i32(c.stick.x * radius), oy + i32(c.stick.y * radius), radius * 0.42, {255, 255, 255, 120})
	}
}

// A small button in the top right corner for moving between scenes.
switch_button :: proc(w, h: f32) -> [4]f32 {
	size := max(f32(56), h * 0.1)
	return {w - size * 2.2 - 16, 16, size * 2.2, size}
}

draw_switch_button :: proc(w, h: f32, label: cstring) {
	b := switch_button(w, h)
	font := i32(b.w / 7)
	rl.DrawRectangle(i32(b.x), i32(b.y), i32(b.z), i32(b.w), {255, 255, 255, 36})
	rl.DrawRectangleLines(i32(b.x), i32(b.y), i32(b.z), i32(b.w), {255, 255, 255, 120})
	rl.DrawText(label, i32(b.x) + 12, i32(b.y + b.w * 0.5) - font / 2, font, rl.RAYWHITE)
}
