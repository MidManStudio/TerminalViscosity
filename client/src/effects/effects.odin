// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "effects.odin"
// ============================================================================

// Package effects is the look of a violent reaction as data: the particles of a
// blast, a spatter, or a burst balloon, the rings that spread from it, the flash
// of light it throws on the room, and how hard it shakes the view. It decides
// nothing about the game, and it has no raylib dependency, so it is tested
// without a window. The client draws what it holds. Units are metres and seconds.
package effects

import "core:math"

Vec3 :: [3]f32

MAX_PARTICLES :: 220
MAX_RINGS :: 6

SHAKE_FADE :: f32(3) // how fast the shake dies away, per second
HEAT_FADE :: f32(2.5) // and the wobble of the picture

// What a particle is. Fire and Spark are added to the picture and glow, the rest
// are blended over it.
Kind :: enum u8 {
	Fire,
	Spark,
	Smoke,
	Liquid,
	Mist,
}

Particle :: struct {
	kind:    Kind,
	pos:     Vec3,
	vel:     Vec3,
	color:   [3]f32,
	age:     f32,
	life:    f32,
	size:    f32, // radius at birth
	grow:    f32, // radius gained each second
	gravity: f32, // metres a second squared, positive falls
	drag:    f32, // share of the speed lost each second
	floor:   f32, // the particle is gone when it falls below this height
}

// A ring that spreads out from a blast and fades.
Ring :: struct {
	pos:    Vec3,
	color:  [3]f32,
	age:    f32,
	life:   f32,
	radius: f32, // radius when it is done
}

// The one light a blast throws on the room: the strongest of those still going.
Light :: struct {
	pos:    Vec3,
	color:  [3]f32,
	radius: f32,
	peak:   f32,
	age:    f32,
	life:   f32,
}

Effects :: struct {
	particles:  [MAX_PARTICLES]Particle,
	count:      int,
	rings:      [MAX_RINGS]Ring,
	ring_count: int,
	light:      Light,
	shake:      f32, // how far the view is knocked, in radians, fading
	heat:       f32, // how hard the picture wobbles, fading
	seed:       u32,
	clock:      f32,
}

init :: proc(e: ^Effects) {
	e^ = {}
	e.seed = 0x9E3779B9
}

// Takes away everything in the air, and the light, the shake, and the wobble.
reset :: proc(e: ^Effects) {
	seed := e.seed
	e^ = {}
	e.seed = seed
}

// A number from 0 up to but not including 1, from a small generator that is the
// same on every machine, so a given blast looks the same each time and is tested.
rand01 :: proc(e: ^Effects) -> f32 {
	x := e.seed
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5
	e.seed = x
	return f32(x >> 8) / f32(1 << 24)
}

range :: proc(e: ^Effects, lo, hi: f32) -> f32 {
	return lo + (hi - lo) * rand01(e)
}

// A direction spread evenly over the sphere.
direction :: proc(e: ^Effects) -> Vec3 {
	y := range(e, -1, 1)
	a := range(e, 0, math.TAU)
	r := math.sqrt(max(1 - y * y, 0))
	return {r * math.cos(a), y, r * math.sin(a)}
}

// Adds a particle. When the pool is full it takes the place of the one nearest
// the end of its life, so a new burst is never lost to an old one.
spawn :: proc(e: ^Effects, p: Particle) {
	if e.count < MAX_PARTICLES {
		e.particles[e.count] = p
		e.count += 1
		return
	}
	worst, worst_share := 0, f32(-1)
	for i in 0 ..< e.count {
		share := e.particles[i].age / max(e.particles[i].life, 1e-3)
		if share > worst_share {
			worst, worst_share = i, share
		}
	}
	e.particles[worst] = p
}

add_ring :: proc(e: ^Effects, r: Ring) {
	if e.ring_count < MAX_RINGS {
		e.rings[e.ring_count] = r
		e.ring_count += 1
		return
	}
	// The oldest was added first and is nearly done, so it makes way.
	for i in 1 ..< MAX_RINGS {
		e.rings[i - 1] = e.rings[i]
	}
	e.rings[MAX_RINGS - 1] = r
}

// Makes this light the one in use if it is stronger than what is left of the
// current one.
add_light :: proc(e: ^Effects, l: Light) {
	if light_intensity(e) <= l.peak {
		e.light = l
	}
}

mix_color :: proc(a, b: [3]f32, t: f32) -> [3]f32 {
	return a + (b - a) * clamp(t, 0, 1)
}

// What the burst is made of: the colors of the two liquids that met, darkened
// for smoke, and used as they are for the droplets.
smoke_color :: proc(a, b: [3]f32) -> [3]f32 {
	return mix_color(a, b, 0.5) * 0.35 + [3]f32{0.06, 0.06, 0.07}
}

// A blast at `at`. `power` runs from 0 for the weakest to 1 for the strongest, `a`
// and `b` are the colors of the liquids that met, `floor` is the height of what
// the debris falls onto, and `open` runs from 0 to 1 for how free the blast was:
// 1 in the open and less in a fume hood, which gives a smaller burst, a dimmer
// flash, and a softer shake.
blast :: proc(e: ^Effects, at: Vec3, power, open: f32, a, b: [3]f32, floor: f32) {
	pw := clamp(power, 0, 1)
	free_air := clamp(open, 0, 1)
	scale := 0.35 + 0.65 * free_air // a contained blast is still seen
	floor_y := min(floor, at.y - 0.02)

	fire := int((8 + 10 * pw) * scale)
	for _ in 0 ..< fire {
		d := direction(e)
		spawn(e, {kind = .Fire, pos = at + d * range(e, 0, 0.06), vel = d * range(e, 0.8, 2.2 + 1.6 * pw) + {0, 0.6, 0}, color = {1, 0.8, 0.4}, life = range(e, 0.35, 0.7), size = range(e, 0.07, 0.12) * (0.6 + 0.4 * scale), grow = 0.35, gravity = -1.2, drag = 2.2, floor = floor_y})
	}
	sparks := int((12 + 16 * pw) * scale)
	for _ in 0 ..< sparks {
		d := direction(e)
		spawn(e, {kind = .Spark, pos = at, vel = d * range(e, 2.5, 5 + 3 * pw) + {0, 1.5, 0}, color = {1, 0.85, 0.4}, life = range(e, 0.5, 1.1), size = 0.014, grow = 0, gravity = 9.8, drag = 0.4, floor = floor_y})
	}
	smoke := int((6 + 6 * pw) * scale)
	dark := smoke_color(a, b)
	for _ in 0 ..< smoke {
		d := direction(e)
		spawn(e, {kind = .Smoke, pos = at + d * range(e, 0, 0.1), vel = d * range(e, 0.2, 0.9) + {0, range(e, 0.4, 1.0), 0}, color = dark, life = range(e, 1.4, 2.6), size = range(e, 0.1, 0.18), grow = 0.28, gravity = -0.3, drag = 1.2, floor = floor_y - 5})
	}
	for i in 0 ..< 12 {
		d := direction(e)
		color := (i % 2 == 0) ? a : b
		spawn(e, {kind = .Liquid, pos = at, vel = d * range(e, 1.5, 3.5 + 2 * pw) + {0, 1.2, 0}, color = color, life = range(e, 0.8, 1.4), size = range(e, 0.012, 0.022), grow = 0, gravity = 9.8, drag = 0.2, floor = floor_y})
	}

	add_ring(e, {pos = at, color = {1, 0.85, 0.55}, life = 0.45, radius = (1.5 + 2.5 * pw) * scale})
	add_light(e, {pos = at, color = {1, 0.72, 0.4}, radius = (4 + 4 * pw) * scale, peak = 2.2 * scale, life = 0.6})
	e.shake = max(e.shake, (0.012 + 0.03 * pw) * scale)
	e.heat = max(e.heat, (1.5 + 2.5 * pw) * scale)
}

// A spatter at `at`: a fan of drops of the liquid thrown up and out, and a small
// puff of mist. It is a nuisance, not a blast, so there is no ring and the light
// is faint.
spatter :: proc(e: ^Effects, at: Vec3, color: [3]f32, floor: f32) {
	floor_y := min(floor, at.y - 0.02)
	for _ in 0 ..< 14 {
		d := direction(e)
		d.y = abs(d.y) * 0.6 + 0.5
		spawn(e, {kind = .Liquid, pos = at, vel = d * range(e, 0.8, 2.2), color = color, life = range(e, 0.5, 0.9), size = range(e, 0.010, 0.018), grow = 0, gravity = 9.8, drag = 0.3, floor = floor_y})
	}
	for _ in 0 ..< 4 {
		spawn(e, {kind = .Mist, pos = at + direction(e) * 0.03, vel = {range(e, -0.2, 0.2), range(e, 0.2, 0.5), range(e, -0.2, 0.2)}, color = mix_color(color, {1, 1, 1}, 0.5), life = range(e, 0.5, 0.9), size = 0.06, grow = 0.2, gravity = -0.2, drag = 1.5, floor = floor_y - 5})
	}
	add_light(e, {pos = at, color = mix_color(color, {1, 1, 1}, 0.5), radius = 1.8, peak = 0.45, life = 0.3})
	e.shake = max(e.shake, 0.004)
}

// A balloon bursting at `at`, with `fill` its share of the way to the limit it
// burst at, from 0 to 1: the liquid flies out in all directions in its own color,
// with a quick ring and some mist. It does not hurt anyone.
pop :: proc(e: ^Effects, at: Vec3, color: [3]f32, fill: f32, floor: f32) {
	share := clamp(fill, 0, 1)
	floor_y := min(floor, at.y - 0.02)
	for _ in 0 ..< int(18 + 10 * share) {
		d := direction(e)
		spawn(e, {kind = .Liquid, pos = at + d * 0.03, vel = d * range(e, 1.0, 2.6 + share) + {0, 0.5, 0}, color = color, life = range(e, 0.7, 1.3), size = range(e, 0.014, 0.026), grow = 0, gravity = 9.8, drag = 0.25, floor = floor_y})
	}
	for _ in 0 ..< 8 {
		spawn(e, {kind = .Mist, pos = at + direction(e) * 0.05, vel = direction(e) * range(e, 0.2, 0.7), color = mix_color(color, {1, 1, 1}, 0.55), life = range(e, 0.5, 1.0), size = 0.07, grow = 0.25, gravity = 0, drag = 1.4, floor = floor_y - 5})
	}
	add_ring(e, {pos = at, color = mix_color(color, {1, 1, 1}, 0.6), life = 0.3, radius = 0.45 + 0.25 * share})
	add_light(e, {pos = at, color = mix_color(color, {1, 1, 1}, 0.6), radius = 1.5, peak = 0.35, life = 0.2})
	e.shake = max(e.shake, 0.003)
}

// A puff of steam from a vent at `at`, with now and then a spark, as from the
// reaction oven while it runs. Called a few times a second, it makes a steady
// plume. The steam is tinted a little by `color`, the liquid inside.
vent :: proc(e: ^Effects, at: Vec3, color: [3]f32) {
	for _ in 0 ..< 2 {
		spawn(e, {kind = .Mist, pos = at + Vec3{range(e, -0.5, 0.5), 0, range(e, -0.1, 0.1)}, vel = {range(e, -0.15, 0.15), range(e, 0.5, 1.0), range(e, -0.15, 0.15)}, color = mix_color(color, {1, 1, 1}, 0.6), life = range(e, 0.8, 1.4), size = 0.05, grow = 0.18, gravity = -0.4, drag = 0.8, floor = at.y - 5})
	}
	if rand01(e) < 0.3 {
		spawn(e, {kind = .Spark, pos = at, vel = {range(e, -0.6, 0.6), range(e, 1.5, 2.5), range(e, -0.6, 0.6)}, color = {1, 0.85, 0.4}, life = range(e, 0.4, 0.8), size = 0.012, gravity = 9.8, drag = 0.3, floor = at.y - 0.4})
	}
}

// A wisp of steam rising from `at`, in a pale tint of `color`, as from a vessel of hot
// liquid. Called a few times a second it is a thin plume. Unlike a vent it has no
// sparks.
steam :: proc(e: ^Effects, at: Vec3, color: [3]f32) {
	spawn(e, {kind = .Mist, pos = at + Vec3{range(e, -0.02, 0.02), 0, range(e, -0.02, 0.02)}, vel = {range(e, -0.05, 0.05), range(e, 0.25, 0.5), range(e, -0.05, 0.05)}, color = mix_color(color, {1, 1, 1}, 0.7), life = range(e, 0.8, 1.3), size = 0.03, grow = 0.1, gravity = -0.2, drag = 0.9, floor = at.y - 5})
}

// A small steady shake of the view, for a machine that is running. It only ever
// raises the shake, so a blast is not made weaker by it.
rumble :: proc(e: ^Effects, amount: f32) {
	e.shake = max(e.shake, amount)
}

// Moves everything on by `dt` seconds and drops what is finished.
step :: proc(e: ^Effects, dt: f32) {
	if dt <= 0 {
		return
	}
	e.clock += dt
	for i := e.count - 1; i >= 0; i -= 1 {
		p := &e.particles[i]
		p.age += dt
		p.vel.y -= p.gravity * dt
		p.vel *= math.exp(-p.drag * dt)
		p.pos += p.vel * dt
		p.size += p.grow * dt
		if p.age >= p.life || p.pos.y < p.floor {
			e.particles[i] = e.particles[e.count - 1]
			e.count -= 1
		}
	}
	for i := e.ring_count - 1; i >= 0; i -= 1 {
		e.rings[i].age += dt
		if e.rings[i].age >= e.rings[i].life {
			e.rings[i] = e.rings[e.ring_count - 1]
			e.ring_count -= 1
		}
	}
	e.light.age += dt
	e.shake *= math.exp(-SHAKE_FADE * dt)
	e.heat *= math.exp(-HEAT_FADE * dt)
	if e.shake < 1e-5 {
		e.shake = 0
	}
	if e.heat < 1e-3 {
		e.heat = 0
	}
}

// How bright the light is now, as a share of its peak times the peak: it falls
// off as the square of what is left of its life.
light_intensity :: proc(e: ^Effects) -> f32 {
	l := e.light
	if l.life <= 0 || l.age >= l.life {
		return 0
	}
	left := 1 - l.age / l.life
	return l.peak * left * left
}

// The knock of the view from a blast, as a turn to the side and a turn up, in
// radians. It is zero when nothing shakes it.
look_shake :: proc(e: ^Effects) -> [2]f32 {
	return {e.shake * math.sin(e.clock * 53), e.shake * math.sin(e.clock * 71 + 1.3)}
}

// The color of a particle now. Fire goes from white-yellow through orange to a
// dark red, and sparks from yellow to orange. The others keep their color.
tint :: proc(p: ^Particle) -> [3]f32 {
	t := clamp(p.age / max(p.life, 1e-3), 0, 1)
	switch p.kind {
	case .Fire:
		hot := mix_color({1, 0.95, 0.7}, {0.95, 0.35, 0.06}, t * 1.4)
		return mix_color(hot, {0.25, 0.06, 0.03}, (t - 0.6) * 2.5)
	case .Spark:
		return mix_color({1, 0.9, 0.5}, {1, 0.4, 0.1}, t)
	case .Smoke, .Liquid, .Mist:
		return p.color
	}
	return p.color
}

// How see-through a particle is now, from 1 for solid to 0 for gone.
opacity :: proc(p: ^Particle) -> f32 {
	t := clamp(p.age / max(p.life, 1e-3), 0, 1)
	switch p.kind {
	case .Fire:
		return (1 - t) * (1 - t)
	case .Spark:
		return 1 - t * t
	case .Smoke:
		return min(t * 6, 1) * (1 - t) * 0.7
	case .Liquid:
		return 1
	case .Mist:
		return min(t * 5, 1) * (1 - t) * 0.5
	}
	return 1
}

// How far across a ring is now and how solid it is, for drawing: it spreads
// quickly at first and slows, and fades as it goes.
ring_state :: proc(r: ^Ring) -> (radius, alpha: f32) {
	t := clamp(r.age / max(r.life, 1e-3), 0, 1)
	return r.radius * (1 - (1 - t) * (1 - t)), (1 - t) * 0.8
}
