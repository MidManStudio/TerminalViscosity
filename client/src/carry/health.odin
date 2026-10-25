// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "health.odin"
// ============================================================================

package carry

import "core:math"

HEALTH_MAX :: f32(100)
REGEN_DELAY :: f32(4) // seconds without a hit before health comes back
REGEN_RATE :: f32(8) // health a second once it does
FLASH_FADE :: f32(3) // how fast the red flash dies away, per second

// The player's health, for what the lab can do to them. `flash` is how red the
// screen is, from 0 to 1, and is only for drawing.
Health :: struct {
	hp:         f32,
	since_hurt: f32,
	flash:      f32,
}

health_init :: proc(h: ^Health) {
	h^ = {
		hp = HEALTH_MAX,
	}
}

health_hurt :: proc(h: ^Health, damage: f32) {
	if damage <= 0 {
		return
	}
	h.hp = max(h.hp - damage, 0)
	h.since_hurt = 0
	h.flash = clamp(damage / 40, 0.35, 1)
}

health_update :: proc(h: ^Health, dt: f32) {
	h.since_hurt += dt
	h.flash *= math.exp(-FLASH_FADE * dt)
	if h.since_hurt > REGEN_DELAY && h.hp > 0 {
		h.hp = min(h.hp + REGEN_RATE * dt, HEALTH_MAX)
	}
}

health_dead :: proc(h: ^Health) -> bool {
	return h.hp <= 0
}
