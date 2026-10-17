// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "balloon_bench.odin"
// ============================================================================

// Headless benchmark for the 3D balloon. Each case times one 60 Hz step, all
// substeps included, while the balloon dangles from its tip and swings, so the
// pinned-vertex path, the constraints, and the damping all run.
package main

import "core:fmt"
import "core:time"
import bl "../src/balloon"

BALLOON_STEPS_PER_SAMPLE :: 600
BALLOON_SAMPLES :: 9

bench_balloon :: proc(frequency, substeps: int, with_render_prep: bool) -> f64 {
	samples: [BALLOON_SAMPLES]f64
	b := new(bl.Balloon)
	defer free(b)
	for s in 0 ..< BALLOON_SAMPLES {
		cfg := bl.default_config()
		cfg.frequency = frequency
		cfg.substeps = substeps
		bl.init(b, cfg)
		bl.reset(b, {0, 2, 0})
		start := time.tick_now()
		for tick in 0 ..< BALLOON_STEPS_PER_SAMPLE {
			bl.pin(b, bl.TIP, {f32(tick % 120) * 0.02 - 1.2, 4.4, 0})
			bl.step(b, 1.0 / 60.0)
			if with_render_prep {
				bl.update_normals(b)
			}
		}
		elapsed := time.tick_diff(start, time.tick_now())
		samples[s] = f64(time.duration_nanoseconds(elapsed)) / f64(BALLOON_STEPS_PER_SAMPLE)
		// Keep the result observable so the loop cannot be optimized away.
		if !bl.is_finite(b) do fmt.eprintln("unreachable")
	}
	for i in 1 ..< BALLOON_SAMPLES {
		v := samples[i]
		j := i - 1
		for j >= 0 && samples[j] > v {
			samples[j + 1] = samples[j]
			j -= 1
		}
		samples[j + 1] = v
	}
	return samples[BALLOON_SAMPLES / 2]
}

bench_balloon_all :: proc() {
	cases := [?][2]int{{4, 6}, {6, 8}, {8, 8}}
	for c in cases {
		fmt.printf("BENCH balloon_step_f%d_s%d %.1f\n", c[0], c[1], bench_balloon(c[0], c[1], false))
	}
	// A whole frame of work: the step plus the normals the renderer needs.
	fmt.printf("BENCH balloon_frame_f6_s8 %.1f\n", bench_balloon(6, 8, true))
}
