// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "hotbar_ui.odin"
// ============================================================================

package main

import "carry"
import "inventory"
import rl "vendor:raylib"

// The bar along the bottom of the screen: a row of slots that hold stations, always on the screen in the lab. A station
// is dragged out of a slot and the copy of it follows the finger, and is put down where the finger lets go if it can stand
// there. Each slot is a button of the controls, so a finger that lands on one does not walk or look.

HOTBAR_FIRST_BUTTON :: 10 // the number of the button of the first slot among the buttons of the room
HOTBAR_GAP_OF_SLOT :: f32(0.12) // the space between slots, as a share of a slot

// The finger that is on a slot of the bar, if one is: which slot, whether it has left the box of the slot yet, which is
// when the drag begins, and where it was last, which is where a copy that follows it was last aimed.
Bar_Press :: struct {
	slot:   int,
	active: bool,
	last:   [2]f32,
}

// The farthest left the bar goes: just inside the panel of the bag screen, which starts 3 percent of the width in.
hotbar_left :: proc(w: f32) -> f32 {
	return w * 0.03 + 4
}

// How big a slot of the bar is: a tenth of the height of the screen, between 48 and 84 pixels, and less if the buttons at
// the bottom right leave less room than that, in the space between the left edge of the bar and those buttons.
hotbar_slot_size :: proc(w, h: f32) -> f32 {
	n := f32(carry.HOTBAR_SIZE)
	room := pour_button(w, h).x - 16 - hotbar_left(w)
	return min(clamp(h * 0.1, 48, 84), room / (n + (n - 1) * HOTBAR_GAP_OF_SLOT))
}

// The whole bar, as a box (x, y, width, height): in the middle of the bottom of the screen, or just left of the buttons
// at the bottom right if the middle is not clear of them. The slots are sized so that the bar fits between `hotbar_left`
// and those buttons, which is why it never starts left of it. Its bottom edge is at least 12 pixels, or 4 percent of the
// height, up from the bottom of the screen, which keeps it inside the panel of the bag screen.
hotbar_rect :: proc(w, h: f32) -> [4]f32 {
	s := hotbar_slot_size(w, h)
	n := f32(carry.HOTBAR_SIZE)
	total := n * s + (n - 1) * s * HOTBAR_GAP_OF_SLOT
	x := min((w - total) * 0.5, pour_button(w, h).x - 16 - total)
	return {x, h - s - max(f32(12), h * 0.04), total, s}
}

// Slot `i` of the bar, as a box.
hotbar_slot_rect :: proc(w, h: f32, i: int) -> [4]f32 {
	bar := hotbar_rect(w, h)
	return {bar.x + f32(i) * bar.w * (1 + HOTBAR_GAP_OF_SLOT), bar.y, bar.w, bar.w}
}

// The boxes of the slots in the order of the buttons they are.
hotbar_buttons :: proc(w, h: f32) -> (boxes: [carry.HOTBAR_SIZE][4]f32) {
	for i in 0 ..< carry.HOTBAR_SIZE {
		boxes[i] = hotbar_slot_rect(w, h, i)
	}
	return
}

// Draws the bar. A slot is a dark box with a bright edge, with the station in it, if there is one, and a number in the
// corner. While a station is carried the slots that can take it have a blue-green edge and a line over the bar says so,
// which is how the player knows before pressing that a slot will take it.
draw_hotbar :: proc(w, h: f32, bar: ^inventory.Container, carrying: bool) {
	whole := hotbar_rect(w, h)
	for i in 0 ..< carry.HOTBAR_SIZE {
		box := hotbar_slot_rect(w, h, i)
		rect := rl.Rectangle{box.x, box.y, box.z, box.w}
		rl.DrawRectangleRounded(rect, 0.12, 6, {10, 18, 28, 200})
		edge, thick := rl.Color{230, 236, 242, 150}, f32(2)
		if carrying && bar.slots[i].count == 0 {
			edge, thick = {60, 230, 215, 255}, 3
		}
		rl.DrawRectangleRoundedLinesEx(rect, 0.12, 6, thick, edge)
		if bar.slots[i].count > 0 {
			draw_stack(box, bar.slots[i], 255)
		}
		buf: [4]u8
		buf[0] = u8('1' + i)
		rl.DrawText(cstring(raw_data(buf[:])), i32(box.x) + 6, i32(box.y) + 4, i32(max(f32(10), box.w * 0.18)), {170, 182, 196, 255})
	}
	if carrying {
		font := i32(max(f32(12), whole.w * 0.034))
		rl.DrawText("tap a slot to put it in the bar", i32(whole.x), i32(whole.y) - font - 6, font, {60, 230, 215, 255})
	}
}

// The slot of the bar that a point is on, if it is on one.
hotbar_slot_at :: proc(w, h: f32, p: [2]f32) -> (slot: int, ok: bool) {
	for i in 0 ..< carry.HOTBAR_SIZE {
		if inside(p, hotbar_slot_rect(w, h, i)) {
			return i, true
		}
	}
	return 0, false
}
