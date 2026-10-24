// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scene_bench.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import "core:fmt"
import "core:time"
import "mpm"

BENCH_STAGES :: len(mpm.BENCH_EDGES)
BENCH_BATCHES :: 12 // timed batches for each particle count; the first two are warm-up
BENCH_BATCH_STEPS :: 6 // substeps in one batch, run in a single frame
BENCH_WARMUP :: 2
BENCH_FRAME_MS :: f64(6) // the share of a 16.7 ms frame the liquid may take

Bench_Result :: struct {
	particles:   int,
	ns_per_step: f64,
	ok:          bool, // false if the liquid blew up
}

// The sim-test scene: it times the liquid simulation on the device itself, at
// five particle counts, a few substeps at a time so the screen keeps moving, and
// shows the cost per particle and what that allows. A tap runs it again.
Bench :: struct {
	sim:     mpm.Sim,
	stage:   int, // the particle count being timed, or BENCH_STAGES when finished
	batches: int,
	samples: [BENCH_BATCHES]f64,
	results: [BENCH_STAGES]Bench_Result,
}

bench_start_stage :: proc(b: ^Bench) {
	edges := mpm.BENCH_EDGES
	b.batches = 0
	mpm.bench_setup(&b.sim, edges[b.stage])
}

bench_restart :: proc(b: ^Bench) {
	b.stage = 0
	b.results = {}
	bench_start_stage(b)
}

bench_load :: proc(game: ^Game) -> rawptr {
	b := new(Bench)
	mpm.sim_init(&b.sim, mpm.DEFAULT_PARAMS, mpm.BENCH_GRID, mpm.BENCH_CAPACITY)
	bench_restart(b)
	return b
}

bench_unload :: proc(game: ^Game, state: rawptr) {
	b := cast(^Bench)state
	mpm.sim_destroy(&b.sim)
	free(b)
}

// The middle of the timed batches, ignoring the warm-up ones.
bench_median :: proc(b: ^Bench) -> f64 {
	timed: [BENCH_BATCHES - BENCH_WARMUP]f64
	for i in 0 ..< len(timed) {
		timed[i] = b.samples[BENCH_WARMUP + i]
	}
	for i in 1 ..< len(timed) {
		v := timed[i]
		j := i - 1
		for j >= 0 && timed[j] > v {
			timed[j + 1] = timed[j]
			j -= 1
		}
		timed[j + 1] = v
	}
	return timed[len(timed) / 2]
}

bench_update :: proc(game: ^Game, state: rawptr, dt: f32) {
	b := cast(^Bench)state
	w, h := f32(game.screen_w), f32(game.screen_h)
	if rl.IsMouseButtonPressed(.LEFT) {
		pointer := platform_mouse_position()
		button := switch_button(w, h)
		if pointer.x >= button.x && pointer.x <= button.x + button.z && pointer.y >= button.y && pointer.y <= button.y + button.w {
			game_switch(game, .Lab_Room)
			return
		}
		if b.stage == BENCH_STAGES {
			bench_restart(b)
		}
	}
	if b.stage == BENCH_STAGES {
		return
	}
	start := time.tick_now()
	for _ in 0 ..< BENCH_BATCH_STEPS {
		mpm.sim_step(&b.sim)
	}
	elapsed := time.tick_diff(start, time.tick_now())
	b.samples[b.batches] = f64(time.duration_nanoseconds(elapsed)) / f64(BENCH_BATCH_STEPS)
	b.batches += 1
	if b.batches == BENCH_BATCHES {
		b.results[b.stage] = {b.sim.count, bench_median(b), mpm.sim_finite(&b.sim)}
		b.stage += 1
		if b.stage < BENCH_STAGES {
			bench_start_stage(b)
		}
	}
}

bench_draw :: proc(game: ^Game, state: rawptr) {
	rl.ClearBackground({14, 20, 28, 255})
}

// Formats into a buffer on the stack and returns it as a C string, so the
// screen never allocates.
bench_text :: proc(buf: ^[160]u8, format: string, args: ..any) -> cstring {
	line := fmt.bprintf(buf[:len(buf) - 1], format, ..args)
	buf[len(line)] = 0
	return cstring(raw_data(buf[:]))
}

bench_draw_ui :: proc(game: ^Game, state: rawptr) {
	b := cast(^Bench)state
	w, h := f32(game.screen_w), f32(game.screen_h)
	font := i32(max(f32(16), h * 0.036))
	x := i32(24)
	y := i32(24)
	buf: [160]u8
	row :: proc(text: cstring, x: i32, y: ^i32, font: i32, color: rl.Color) {
		rl.DrawText(text, x, y^, font, color)
		y^ += font + font / 3
	}
	dim := rl.Color{170, 184, 198, 255}
	p := b.sim.p
	steps_per_frame := int((1.0 / 60.0) / f64(p.dt) + 0.999)

	row(bench_text(&buf, "liquid sim test, build %v", ODIN_OPTIMIZATION_MODE), x, &y, font, rl.RAYWHITE)
	row(bench_text(&buf, "cell %.1f cm, step %.2f ms, real time needs %d steps a frame", p.dx * 100, p.dt * 1000, steps_per_frame), x, &y, font, dim)
	y += font / 2
	row("particles   ms a step   us a particle", x, &y, font, dim)

	edges := mpm.BENCH_EDGES
	for stage in 0 ..< BENCH_STAGES {
		r := b.results[stage]
		if stage < b.stage {
			per := r.ns_per_step / f64(r.particles) / 1000
			verdict: cstring = r.ok ? "" : "  BLEW UP"
			row(bench_text(&buf, "%-11d %-11.2f %.2f%v", r.particles, r.ns_per_step / 1e6, per, verdict), x, &y, font, rl.RAYWHITE)
		} else if stage == b.stage {
			row(bench_text(&buf, "%-11d running %d of %d", edges[stage] * edges[stage] * edges[stage], b.batches, BENCH_BATCHES), x, &y, font, {60, 230, 215, 255})
		} else {
			row(bench_text(&buf, "%-11d waiting", edges[stage] * edges[stage] * edges[stage]), x, &y, font, dim)
		}
	}

	if b.stage == BENCH_STAGES {
		// A straight line through the smallest and the largest count.
		first, last := b.results[0], b.results[BENCH_STAGES - 1]
		per_particle := max(0, (last.ns_per_step - first.ns_per_step) / f64(last.particles - first.particles))
		fixed := max(0, first.ns_per_step - per_particle * f64(first.particles))
		y += font / 2
		row(bench_text(&buf, "%.2f us for each particle, %.2f ms for the grid, each step", per_particle / 1000, fixed / 1e6), x, &y, font, rl.RAYWHITE)
		row(bench_text(&buf, "a 125 ml splash, per frame, against %.0f ms to spend:", BENCH_FRAME_MS), x, &y, font, dim)
		for cell in ([]f64{0.01, 0.02, 0.03}) {
			// Twice the cell size is eight times fewer particles and half the steps.
			scale := cell / f64(p.dx)
			particles := 1000 / (scale * scale * scale)
			steps := f64(steps_per_frame) / scale
			grid := fixed / (scale * scale * scale)
			ms := steps * (grid + per_particle * particles) / 1e6
			verdict: cstring = ms <= BENCH_FRAME_MS ? "fits" : "too slow"
			row(bench_text(&buf, "%.0f cm cells: %.0f particles, %.0f steps, %.1f ms  %v", cell * 100, particles, steps, ms, verdict), x, &y, font, rl.RAYWHITE)
		}
		row("tap anywhere to run it again", x, &y, font, dim)
	}
	rl.DrawFPS(i32(w) - 120, i32(h) - 32)
	draw_switch_button(w, h, "lab")
}
