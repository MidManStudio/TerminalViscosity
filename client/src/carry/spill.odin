// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "spill.odin"
// ============================================================================

package carry

import "core:math"

MAX_PUDDLES :: 24
SPILL_FILM :: f32(0.0012) // how thick a puddle is, in metres, which sets how wide the liquid in it spreads
SPILL_SPREAD :: f32(7) // how fast the edge of a puddle goes to where it will stop, as a share of the way a second
SPILL_STAY :: f32(4) // seconds a puddle lies before it begins to dissolve
SPILL_FADE :: f32(2.5) // seconds it takes to dissolve
SPILL_JOIN :: f32(0.9) // a drop that lands within this much of the radius of a puddle of the same liquid joins it
SPILL_START :: f32(0.35) // how much of its width a new puddle begins with
SPILL_R_MIN :: f32(0.012) // the smallest and the largest a puddle is drawn, in metres
SPILL_R_MAX :: f32(0.35)
PUDDLE_START :: f32(0.08) // seconds a drop lies still before it becomes part of a puddle

// Liquid that has landed on a surface: where it is, how much there is, how wide it has spread, and how long ago
// it landed. `delay` is the time before it lands, for liquid that falls from the stream's box to a floor far below.
Puddle :: struct {
	pos:      Vec3,
	ml:       f32,
	radius:   f32,
	age:      f32,
	delay:    f32,
	compound: u16,
}

// The puddles in the lab. They are only for looking at: nothing in the game reads them.
Spill :: struct {
	puddles: [MAX_PUDDLES]Puddle,
	count:   int,
}

// How wide the liquid in a puddle spreads in the end: the circle that holds it at the thickness of a puddle.
spill_size :: proc(ml: f32) -> f32 {
	return clamp(math.sqrt(ml * 1e-6 / (math.PI * SPILL_FILM)), SPILL_R_MIN, SPILL_R_MAX)
}

// Lets `ml` of `compound` land at `pos`, which is on a surface, after `delay` seconds. It joins a puddle of the same
// liquid on the same surface that it lands in, which makes that puddle larger and fresh again, and otherwise makes
// a new puddle. When all the puddles are in use the one that has lain longest is taken.
spill_add :: proc(sp: ^Spill, pos: Vec3, ml: f32, compound: u16, delay: f32 = 0) {
	for i in 0 ..< sp.count {
		p := &sp.puddles[i]
		if p.compound != compound || abs(p.pos.y - pos.y) > 0.03 {
			continue
		}
		reach := max(p.radius, spill_size(p.ml)) * SPILL_JOIN
		dx, dz := pos.x - p.pos.x, pos.z - p.pos.z
		if dx * dx + dz * dz <= reach * reach {
			total := p.ml + ml
			p.pos.x += dx * ml / total
			p.pos.z += dz * ml / total
			p.ml = total
			p.age = min(p.age, p.delay)
			return
		}
	}
	k := sp.count
	if k == MAX_PUDDLES {
		k = 0
		for i in 1 ..< sp.count {
			if sp.puddles[i].age - sp.puddles[i].delay > sp.puddles[k].age - sp.puddles[k].delay {
				k = i
			}
		}
	} else {
		sp.count += 1
	}
	sp.puddles[k] = {pos, ml, spill_size(ml) * SPILL_START, 0, delay, compound}
}

// Moves time on: puddles that have landed spread towards their size, and those that have dissolved are removed.
spill_step :: proc(sp: ^Spill, dt: f32) {
	for i := sp.count - 1; i >= 0; i -= 1 {
		p := &sp.puddles[i]
		p.age += dt
		if p.age < p.delay {
			continue
		}
		p.radius += (spill_size(p.ml) - p.radius) * min(SPILL_SPREAD * dt, 1)
		if p.age - p.delay > SPILL_STAY + SPILL_FADE {
			sp.puddles[i] = sp.puddles[sp.count - 1]
			sp.count -= 1
		}
	}
}

// Whether a puddle has landed, so that it can be seen.
puddle_landed :: proc(p: Puddle) -> bool {
	return p.age >= p.delay
}

// How far a puddle has dissolved: 0 while it lies, up to 1 when it has gone.
puddle_dissolve :: proc(p: Puddle) -> f32 {
	return clamp((p.age - p.delay - SPILL_STAY) / SPILL_FADE, 0, 1)
}
