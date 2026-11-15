// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "chem_test.odin"
// ============================================================================

package chem

import "../chemistry"
import "core:testing"

@(test)
names_and_colours_come_from_the_pages :: proc(t: ^testing.T) {
	testing.expect_value(t, compound_name(u16(chemistry.Id.Ethanol)), "Ethanol")
	testing.expect_value(t, compound_name(0), "")
	testing.expect_value(t, string(compound_cname(u16(chemistry.Id.Water))), "Water")
	testing.expect_value(t, compound_color(0), [3]f32{1, 1, 1})
	c := compound_color(u16(chemistry.Id.Water))
	testing.expect(t, abs(c.b - f32(0xe8) / 255) < 0.001, "water is blue")
	testing.expect_value(t, compound_name(9999), "")
}

@(test)
the_hazard_levels_start_where_they_are_documented :: proc(t: ^testing.T) {
	testing.expect_value(t, hazard_of(0), Hazard.Calm)
	testing.expect_value(t, hazard_of(0.29), Hazard.Calm)
	testing.expect_value(t, hazard_of(0.3), Hazard.Spatter)
	testing.expect_value(t, hazard_of(0.59), Hazard.Spatter)
	testing.expect_value(t, hazard_of(0.6), Hazard.Blast)
	testing.expect_value(t, hazard_of(1), Hazard.Blast)
}

@(test)
damage_falls_with_distance_and_grows_with_volatility :: proc(t: ^testing.T) {
	for v in ([]f32{0.3, 0.45, 0.6, 0.7, 0.85, 1}) {
		previous := f32(1e9)
		for d := f32(0); d < 5; d += 0.25 {
			dmg := damage_of(v, d)
			testing.expect(t, dmg >= 0 && dmg <= previous)
			previous = dmg
		}
		testing.expect_value(t, damage_of(v, 5), 0)
	}
	testing.expect_value(t, damage_of(0.1, 0), 0)
	testing.expect(t, blast_damage(1, 1) > blast_damage(0.7, 1))
	testing.expect(t, blast_damage(0.6, 0) == BLAST_DAMAGE_MIN)
	testing.expect(t, blast_damage(1, 0) == BLAST_DAMAGE_MAX)
}

// Mixing happens with the vessel in the hands, so under a metre from the eye.
@(test)
the_worst_blast_at_arms_length_hurts_a_lot_but_does_not_kill :: proc(t: ^testing.T) {
	worst := damage_of(1, 0.8)
	testing.expectf(t, worst >= 60 && worst < 100, "the worst blast does %v at 0.8 m", worst)
	smaller := damage_of(0.7, 0.8)
	testing.expectf(t, smaller >= 20 && smaller < 100, "a smaller blast does %v at 0.8 m", smaller)
	spatter := damage_of(0.45, 0.8)
	testing.expectf(t, spatter > 0 && spatter < 10, "a spatter does %v at 0.8 m", spatter)
}
