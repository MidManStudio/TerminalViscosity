// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "chem_test.odin"
// ============================================================================

package chem

import "core:testing"

// Every id from 1 up to the last product.
all_ids :: proc() -> []u16 {
	@(static) ids: [64]u16
	n := compound_count()
	for i in 0 ..< n {
		ids[i] = u16(i + 1)
	}
	return ids[:n]
}

// An id for one compound of each class, to walk the matrix by class.
first_of :: proc(c: Class) -> u16 {
	for id in all_ids() {
		if class_of(id) == c {
			return id
		}
	}
	return 0
}

@(test)
the_ids_and_the_table_agree :: proc(t: ^testing.T) {
	testing.expect_value(t, compound_count(), int(max(Id)))
	table := COMPOUNDS
	for i in 0 ..< len(table) {
		for j in i + 1 ..< len(table) {
			testing.expectf(t, string(table[i].name) != string(table[j].name), "two compounds are called %v", table[i].name)
		}
	}
	testing.expect_value(t, compound_name(u16(Id.Spark_Blue)), "Spark Blue")
	testing.expect_value(t, compound_name(u16(Id.Magenta)), "Magenta")
	testing.expect_value(t, compound_name(0), "Empty")
	testing.expect_value(t, compound_name(999), "Empty")
	for id in all_ids() {
		c := compound_color(id)
		testing.expect(t, c.r >= 0 && c.r <= 1 && c.g >= 0 && c.g <= 1 && c.b >= 0 && c.b <= 1)
	}
}

@(test)
every_pair_of_classes_has_exactly_one_rule :: proc(t: ^testing.T) {
	table := RULES
	testing.expect_value(t, len(table), CLASS_COUNT * (CLASS_COUNT + 1) / 2)
	for a in Class {
		for b in Class {
			found := 0
			for r in table {
				if (r.a == a && r.b == b) || (r.a == b && r.b == a) {
					found += 1
				}
			}
			testing.expectf(t, found == 1, "%v with %v has %v rules", a, b, found)
		}
	}
}

@(test)
every_product_is_a_known_compound :: proc(t: ^testing.T) {
	table := RULES
	for r in table {
		if r.product != KEEP_OTHER {
			testing.expectf(t, r.product >= 1 && int(r.product) <= compound_count(), "%v with %v makes an unknown compound", r.a, r.b)
		}
		testing.expect(t, r.volatility >= 0 && r.volatility <= 1)
	}
}

@(test)
the_outcome_does_not_depend_on_the_order :: proc(t: ^testing.T) {
	for a in all_ids() {
		for b in all_ids() {
			testing.expectf(t, react(a, b) == react(b, a), "%v and %v depend on the order", compound_name(a), compound_name(b))
		}
	}
}

@(test)
nothing_reacts_with_itself_or_with_nothing :: proc(t: ^testing.T) {
	for a in all_ids() {
		same := react(a, a)
		testing.expect(t, !same.reacted && same.product == a && same.volatility == 0)
		empty := react(a, 0)
		testing.expect(t, !empty.reacted && empty.product == a)
		testing.expect(t, react(0, a) == empty)
	}
	testing.expect(t, !react(0, 0).reacted)
}

@(test)
a_reaction_always_makes_something_real :: proc(t: ^testing.T) {
	for a in all_ids() {
		for b in all_ids() {
			if a == b {
				continue
			}
			o := react(a, b)
			testing.expect(t, o.reacted)
			testing.expectf(t, o.product >= 1 && int(o.product) <= compound_count(), "%v with %v made %v", compound_name(a), compound_name(b), o.product)
		}
	}
}

@(test)
water_thins_acids_bases_oxidizers_and_dyes_without_changing_them :: proc(t: ^testing.T) {
	water := u16(Id.Water)
	for other in ([]Id{.Fizz_Acid, .Soda_Base, .Spark_Blue, .Dye_Red, .Dye_Violet, .Magenta}) {
		o := react(water, u16(other))
		testing.expect_value(t, o.product, u16(other))
		testing.expect_value(t, o.volatility, 0)
	}
}

@(test)
the_known_recipes_make_what_they_should :: proc(t: ^testing.T) {
	testing.expect_value(t, react(u16(Id.Fizz_Acid), u16(Id.Soda_Base)).product, u16(Id.Neutral_Foam))
	testing.expect_value(t, react(u16(Id.Frost_Gel), u16(Id.Water)).product, u16(Id.Slush))
	testing.expect_value(t, react(u16(Id.Dye_Red), u16(Id.Dye_Violet)).product, u16(Id.Magenta))
	testing.expect_value(t, react(u16(Id.Glue_Goo), u16(Id.Dye_Red)).product, u16(Id.Sticky_Mess))
	testing.expect_value(t, react(u16(Id.Slick), u16(Id.Water)).product, u16(Id.Slick_Mess))
	testing.expect_value(t, react(u16(Id.Ember_Oil), u16(Id.Spark_Blue)).product, u16(Id.Char))
}

// The danger of the matrix is meant to sit around the oxidizer. This fails if a
// rule is changed so that something else becomes a blast or a spatter, which
// is then a decision to make on purpose.
@(test)
only_the_planned_pairs_are_dangerous :: proc(t: ^testing.T) {
	blasts, spatters := 0, 0
	table := RULES
	for r in table {
		switch hazard_of(r.volatility) {
		case .Calm:
		case .Spatter:
			spatters += 1
			testing.expect(t, r.a == .Oxidizer || r.b == .Oxidizer)
		case .Blast:
			blasts += 1
			testing.expect(t, r.a == .Oxidizer || r.b == .Oxidizer)
		}
	}
	testing.expect_value(t, blasts, 2)
	testing.expect_value(t, spatters, 2)
	testing.expect_value(t, hazard_of(react(u16(Id.Ember_Oil), u16(Id.Spark_Blue)).volatility), Hazard.Blast)
	testing.expect_value(t, hazard_of(react(u16(Id.Fizz_Acid), u16(Id.Spark_Blue)).volatility), Hazard.Blast)
	testing.expect_value(t, hazard_of(react(u16(Id.Soda_Base), u16(Id.Spark_Blue)).volatility), Hazard.Spatter)
	testing.expect_value(t, hazard_of(react(u16(Id.Frost_Gel), u16(Id.Spark_Blue)).volatility), Hazard.Spatter)
	testing.expect_value(t, hazard_of(react(u16(Id.Fizz_Acid), u16(Id.Soda_Base)).volatility), Hazard.Calm)
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
	worst := damage_of(react(u16(Id.Ember_Oil), u16(Id.Spark_Blue)).volatility, 0.8)
	testing.expectf(t, worst >= 60 && worst < 100, "the worst blast does %v at 0.8 m", worst)
	smaller := damage_of(react(u16(Id.Fizz_Acid), u16(Id.Spark_Blue)).volatility, 0.8)
	testing.expectf(t, smaller >= 20 && smaller < 45, "the acid blast does %v at 0.8 m", smaller)
	spatter := damage_of(react(u16(Id.Soda_Base), u16(Id.Spark_Blue)).volatility, 0.8)
	testing.expectf(t, spatter > 0 && spatter < 10, "a spatter does %v at 0.8 m", spatter)
}
