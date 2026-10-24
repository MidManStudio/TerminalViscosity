// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mpm_bench.odin"
// ============================================================================

// Headless benchmark for the liquid simulation. Each case times one substep of
// the benchmark cube from mpm.bench_setup, so the cost per particle can be read
// off the result. The same cases run on the phone from the sim-test scene.
package main

import "core:fmt"
import "core:time"
import "../src/mpm"

MPM_STEPS_PER_SAMPLE :: 40
MPM_SAMPLES :: 9

bench_mpm :: proc(s: ^mpm.Sim, edge: int) -> (count: int, ns_per_step: f64) {
	samples: [MPM_SAMPLES]f64
	count = mpm.bench_setup(s, edge)
	for sample in 0 ..< MPM_SAMPLES {
		start := time.tick_now()
		for _ in 0 ..< MPM_STEPS_PER_SAMPLE {
			mpm.sim_step(s)
		}
		elapsed := time.tick_diff(start, time.tick_now())
		samples[sample] = f64(time.duration_nanoseconds(elapsed)) / f64(MPM_STEPS_PER_SAMPLE)
		// Keep the result observable so the loop cannot be optimized away.
		if !mpm.sim_finite(s) do fmt.eprintln("unreachable")
	}
	for i in 1 ..< MPM_SAMPLES {
		v := samples[i]
		j := i - 1
		for j >= 0 && samples[j] > v {
			samples[j + 1] = samples[j]
			j -= 1
		}
		samples[j + 1] = v
	}
	return count, samples[MPM_SAMPLES / 2]
}

bench_mpm_all :: proc() {
	s: mpm.Sim
	mpm.sim_init(&s, mpm.DEFAULT_PARAMS, mpm.BENCH_GRID, mpm.BENCH_CAPACITY)
	defer mpm.sim_destroy(&s)
	for edge in mpm.BENCH_EDGES {
		count, ns := bench_mpm(&s, edge)
		fmt.printf("BENCH mpm_step_%d %.1f\n", count, ns)
	}
}
