// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "scenario.odin"
// ============================================================================

package mpm

BENCH_GRID :: 32 // nodes along each side, so 0.32 m of room at 1 cm cells
BENCH_EDGES :: [?]int{6, 8, 10, 12, 16} // particles along each side of the test cube
BENCH_CAPACITY :: 4096

// The liquid every benchmark uses: a cube with `edge` particles along each side,
// centered in the grid and a little above the floor, so it drops and splashes.
// Returns how many particles were added, which is edge cubed.
bench_setup :: proc(s: ^Sim, edge: int) -> int {
	dx := s.p.dx
	size := f32(edge) * dx * 0.5
	centre := f32(BENCH_GRID) * dx * 0.5
	lo := Vec3{centre - size * 0.5, 4 * dx, centre - size * 0.5}
	hi := Vec3{centre + size * 0.5, 4 * dx + size, centre + size * 0.5}
	sim_clear(s)
	return sim_add_block(s, lo, hi)
}
