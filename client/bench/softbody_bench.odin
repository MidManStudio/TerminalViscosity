// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "softbody_bench.odin"
// ============================================================================

// Headless benchmark entry point. It runs the soft-body ring benchmark here, the
// 3D balloon benchmark from balloon_bench.odin, and the liquid simulation
// benchmark from mpm_bench.odin, and prints one line per
// case in the form `BENCH <name> <ns_per_step>`, which scripts/bench_summary.py reads.
package main

import "core:fmt"
import "core:time"
import sb "../src/softbody"

STEPS_PER_SAMPLE :: 2000
SAMPLES :: 9

bench_ring :: proc(count: int) -> f64 {
	samples: [SAMPLES]f64
	for s in 0 ..< SAMPLES {
		r: sb.Ring
		sb.ring_init(&r, {400, 200}, 80, count)
		r.floor_y = 600
		start := time.tick_now()
		for _ in 0 ..< STEPS_PER_SAMPLE {
			sb.ring_step(&r, 1.0 / 60.0)
		}
		elapsed := time.tick_diff(start, time.tick_now())
		samples[s] = f64(time.duration_nanoseconds(elapsed)) / f64(STEPS_PER_SAMPLE)
		// Keep the result observable so the loop cannot be optimized away.
		if sb.ring_area(&r) < 0 do fmt.eprintln("unreachable")
	}
	// Median of the samples, insertion sort is plenty for nine values.
	for i in 1 ..< SAMPLES {
		v := samples[i]
		j := i - 1
		for j >= 0 && samples[j] > v {
			samples[j + 1] = samples[j]
			j -= 1
		}
		samples[j + 1] = v
	}
	return samples[SAMPLES / 2]
}

bench_softbody :: proc() {
	for count in ([]int{16, 24, 48, 64}) {
		fmt.printf("BENCH softbody_step_%d %.1f\n", count, bench_ring(count))
	}
}

main :: proc() {
	bench_softbody()
	bench_balloon_all()
	bench_mpm_all()
}
