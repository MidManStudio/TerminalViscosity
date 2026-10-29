// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "effects_test.odin"
// ============================================================================

package effects

import "core:testing"

RED :: [3]f32{0.9, 0.1, 0.1}
BLUE :: [3]f32{0.1, 0.2, 0.9}

fresh :: proc() -> ^Effects {
	e := new(Effects)
	init(e)
	return e
}

count_of :: proc(e: ^Effects, k: Kind) -> int {
	n := 0
	for i in 0 ..< e.count {
		if e.particles[i].kind == k {
			n += 1
		}
	}
	return n
}

@(test)
blast_makes_every_part :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	blast(e, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	testing.expect(t, count_of(e, .Fire) > 0, "fire")
	testing.expect(t, count_of(e, .Spark) > 0, "sparks")
	testing.expect(t, count_of(e, .Smoke) > 0, "smoke")
	testing.expect(t, count_of(e, .Liquid) > 0, "liquid")
	testing.expect_value(t, e.ring_count, 1)
	testing.expect(t, light_intensity(e) > 1, "a blast lights the room")
	testing.expect(t, e.shake > 0.03, "and shakes the view")
	testing.expect(t, e.heat > 3, "and wobbles the picture")
}

@(test)
stronger_blast_is_bigger :: proc(t: ^testing.T) {
	weak, strong := fresh(), fresh()
	defer free(weak)
	defer free(strong)
	blast(weak, {0, 1.2, 0}, 0, 1, RED, BLUE, 1.1)
	blast(strong, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	testing.expect(t, strong.count > weak.count, "more particles")
	testing.expect(t, strong.rings[0].radius > weak.rings[0].radius, "a wider ring")
	testing.expect(t, strong.shake > weak.shake, "a harder shake")
	testing.expect(t, strong.light.radius > weak.light.radius, "a wider light")
}

@(test)
contained_blast_is_smaller_but_still_seen :: proc(t: ^testing.T) {
	open, hood := fresh(), fresh()
	defer free(open)
	defer free(hood)
	blast(open, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	blast(hood, {0, 1.2, 0}, 1, 0, RED, BLUE, 1.1)
	testing.expect(t, hood.count < open.count, "fewer particles")
	testing.expect(t, hood.shake < open.shake, "a softer shake")
	testing.expect(t, light_intensity(hood) < light_intensity(open), "a dimmer flash")
	testing.expect(t, hood.count > 0 && hood.shake > 0, "but it is not nothing")
}

@(test)
everything_ends :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	blast(e, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	for _ in 0 ..< 400 {
		step(e, 1.0 / 60)
	}
	testing.expect_value(t, e.count, 0)
	testing.expect_value(t, e.ring_count, 0)
	testing.expect_value(t, light_intensity(e), 0)
	testing.expect_value(t, e.shake, 0)
	testing.expect_value(t, e.heat, 0)
}

@(test)
pool_never_overflows :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	for _ in 0 ..< 40 {
		blast(e, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	}
	testing.expect(t, e.count <= MAX_PARTICLES, "particles")
	testing.expect(t, e.ring_count <= MAX_RINGS, "rings")
	testing.expect_value(t, e.count, MAX_PARTICLES)
}

@(test)
full_pool_replaces_the_oldest :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	for _ in 0 ..< MAX_PARTICLES {
		spawn(e, {kind = .Liquid, life = 1, age = 0.5})
	}
	e.particles[5].age = 0.99 // the one nearest its end
	e.particles[7].age = 0.1 // a young one
	spawn(e, {kind = .Spark, life = 1})
	testing.expect_value(t, e.particles[5].kind, Kind.Spark)
	testing.expect_value(t, e.particles[7].kind, Kind.Liquid)
	testing.expect_value(t, e.particles[0].kind, Kind.Liquid)
	testing.expect_value(t, e.count, MAX_PARTICLES)
}

@(test)
liquid_falls_and_is_gone_at_the_floor :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	spawn(e, {kind = .Liquid, pos = {0, 1.2, 0}, life = 10, gravity = 9.8, floor = 1.1})
	step(e, 0.1)
	testing.expect(t, e.particles[0].pos.y < 1.2, "it falls")
	for _ in 0 ..< 30 {
		step(e, 0.05)
	}
	testing.expect_value(t, e.count, 0)
}

@(test)
same_seed_same_blast :: proc(t: ^testing.T) {
	a, b := fresh(), fresh()
	defer free(a)
	defer free(b)
	blast(a, {1, 1.2, 2}, 0.5, 1, RED, BLUE, 1.1)
	blast(b, {1, 1.2, 2}, 0.5, 1, RED, BLUE, 1.1)
	testing.expect_value(t, a.count, b.count)
	same := true
	for i in 0 ..< a.count {
		if a.particles[i].pos != b.particles[i].pos || a.particles[i].vel != b.particles[i].vel {
			same = false
		}
	}
	testing.expect(t, same, "the same blast looks the same")
}

@(test)
pop_is_in_the_color_of_the_liquid :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	pop(e, {0, 1.5, 0}, BLUE, 1, 1.1)
	testing.expect(t, count_of(e, .Liquid) > 15, "drops")
	for i in 0 ..< e.count {
		if e.particles[i].kind == .Liquid {
			testing.expect_value(t, e.particles[i].color, BLUE)
		}
	}
	testing.expect_value(t, count_of(e, .Fire), 0)
	testing.expect_value(t, e.ring_count, 1)
}

@(test)
spatter_is_small :: proc(t: ^testing.T) {
	spat, boom := fresh(), fresh()
	defer free(spat)
	defer free(boom)
	spatter(spat, {0, 1.2, 0}, RED, 1.1)
	blast(boom, {0, 1.2, 0}, 0, 1, RED, BLUE, 1.1)
	testing.expect_value(t, spat.ring_count, 0)
	testing.expect_value(t, count_of(spat, .Fire), 0)
	testing.expect(t, light_intensity(spat) < light_intensity(boom), "fainter than the weakest blast")
	testing.expect(t, spat.shake < boom.shake, "and a lighter knock")
}

@(test)
a_bigger_light_is_not_replaced_by_a_smaller :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	blast(e, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	peak := e.light.peak
	pop(e, {5, 1.5, 5}, BLUE, 1, 1.1)
	testing.expect_value(t, e.light.peak, peak)
	for _ in 0 ..< 60 { // a second on, the blast's light is mostly gone
		step(e, 1.0 / 60)
	}
	pop(e, {5, 1.5, 5}, BLUE, 1, 1.1)
	testing.expect(t, e.light.peak < peak, "the next one is let in when the old light has faded")
}

@(test)
fire_cools_as_it_ages :: proc(t: ^testing.T) {
	young := Particle{kind = .Fire, life = 1, age = 0.05}
	old := Particle{kind = .Fire, life = 1, age = 0.9}
	a, b := tint(&young), tint(&old)
	testing.expect(t, a.b > b.b, "less blue as it cools")
	testing.expect(t, a.g > b.g, "and less green")
	testing.expect(t, opacity(&young) > opacity(&old), "and it fades")
}

@(test)
shake_is_zero_when_idle :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	step(e, 0.5)
	testing.expect_value(t, look_shake(e), [2]f32{0, 0})
}

@(test)
ring_spreads_and_fades :: proc(t: ^testing.T) {
	r := Ring {
		life   = 1,
		radius = 3,
	}
	r0, a0 := ring_state(&r)
	r.age = 0.5
	r1, a1 := ring_state(&r)
	r.age = 1
	r2, a2 := ring_state(&r)
	testing.expect_value(t, r0, 0)
	testing.expect(t, r1 > r0 && r2 > r1, "wider")
	testing.expect_value(t, r2, 3)
	testing.expect(t, a0 > a1 && a1 > a2, "fainter")
}

@(test)
blast_knocks_the_view :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	blast(e, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	step(e, 1.0 / 60)
	k := look_shake(e)
	testing.expect(t, k.x != 0 && k.y != 0, "both turns move")
	testing.expect(t, abs(k.x) <= e.shake && abs(k.y) <= e.shake, "and never more than the shake")
}

@(test)
vent_makes_rising_steam :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	for _ in 0 ..< 20 {
		vent(e, {3, 1.7, -7.6}, RED)
	}
	testing.expect(t, count_of(e, .Mist) >= 40, "steam")
	testing.expect_value(t, count_of(e, .Fire), 0)
	testing.expect_value(t, e.ring_count, 0)
	rising := true
	for i in 0 ..< e.count {
		if e.particles[i].kind == .Mist && e.particles[i].vel.y <= 0 {
			rising = false
		}
	}
	testing.expect(t, rising, "it goes up")
	testing.expect_value(t, light_intensity(e), 0) // a vent throws no light
}

@(test)
steam_is_thin_and_has_no_sparks :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	for _ in 0 ..< 30 {
		steam(e, {0, 1.3, 0}, RED)
	}
	testing.expect_value(t, e.count, 30)
	testing.expect_value(t, count_of(e, .Mist), 30)
	testing.expect_value(t, count_of(e, .Spark), 0)
	for i in 0 ..< e.count {
		testing.expect(t, e.particles[i].vel.y > 0, "it rises")
		testing.expect(t, e.particles[i].size < 0.05, "a wisp, not a cloud")
	}
	testing.expect_value(t, light_intensity(e), 0)
}

@(test)
rumble_only_raises_the_shake :: proc(t: ^testing.T) {
	e := fresh()
	defer free(e)
	rumble(e, 0.004)
	testing.expect_value(t, e.shake, 0.004)
	rumble(e, 0.001)
	testing.expect_value(t, e.shake, 0.004)
	blast(e, {0, 1.2, 0}, 1, 1, RED, BLUE, 1.1)
	big := e.shake
	rumble(e, 0.004)
	testing.expect_value(t, e.shake, big)
}
