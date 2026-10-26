// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "chem.odin"
// ============================================================================

// Package chem is what the lab liquids are and what happens when two of them
// meet: the compounds, the classes they belong to, and the reaction matrix. It
// has no raylib dependency. A table written for this game stands in for the
// compound database, which will later be DixScript content shared with the
// server, and its answer has the same shape as tv_sim's `ChemBackend::react`:
// volatility from 0 to 1 and a heat, with the product added for the lab.
package chem

// What a compound does when it meets another. Only classes meet in the matrix,
// so a new compound only has to be given a class.
Class :: enum u8 {
	Neutral, // water and things that behave like it
	Acid,
	Base,
	Fuel,
	Oxidizer,
	Cryo,
	Gel,
	Lube,
	Dye,
	Inert, // dead ends: what is left when a mix went wrong
}

CLASS_COUNT :: len(Class)

// Id 0 means empty, and the ids are what the wire format carries. The stock
// liquids come first, then the products that mixing them can make.
Id :: enum u16 {
	None,
	Water,
	Fizz_Acid,
	Soda_Base,
	Ember_Oil,
	Spark_Blue,
	Frost_Gel,
	Glue_Goo,
	Slick,
	Dye_Red,
	Dye_Violet,
	Neutral_Foam,
	Slush,
	Sticky_Mess,
	Slick_Mess,
	Char,
	Slurry,
	Magenta,
	Acrid_Brew,
}

STOCK_COUNT :: 10 // the first ten ids are the liquids on the shelf

Compound :: struct {
	name:  cstring,
	class: Class,
	color: [3]u8,
}

COMPOUNDS :: [?]Compound {
	{"Water", .Neutral, {120, 185, 235}},
	{"Fizz Acid", .Acid, {170, 230, 70}},
	{"Soda Base", .Base, {235, 150, 220}},
	{"Ember Oil", .Fuel, {240, 128, 40}},
	{"Spark Blue", .Oxidizer, {60, 140, 255}},
	{"Frost Gel", .Cryo, {170, 235, 245}},
	{"Glue Goo", .Gel, {240, 220, 110}},
	{"Slick", .Lube, {96, 74, 120}},
	{"Dye Red", .Dye, {225, 50, 60}},
	{"Dye Violet", .Dye, {140, 70, 220}},
	{"Neutral Foam", .Neutral, {232, 238, 244}},
	{"Slush", .Neutral, {190, 226, 236}},
	{"Sticky Mess", .Gel, {196, 166, 88}},
	{"Slick Mess", .Lube, {132, 112, 150}},
	{"Char", .Inert, {42, 42, 48}},
	{"Slurry", .Inert, {122, 112, 92}},
	{"Magenta", .Dye, {205, 60, 170}},
	{"Acrid Brew", .Inert, {150, 172, 60}},
}

compound_count :: proc() -> int {
	table := COMPOUNDS
	return len(table)
}

compound_name :: proc(id: u16) -> string {
	return string(compound_cname(id))
}

// The same name as a C string, for drawing text without making a copy.
compound_cname :: proc(id: u16) -> cstring {
	table := COMPOUNDS
	if id == 0 || int(id) > len(table) {
		return "Empty"
	}
	return table[id - 1].name
}

// The color of a liquid as red, green, and blue between 0 and 1.
compound_color :: proc(id: u16) -> [3]f32 {
	table := COMPOUNDS
	if id == 0 || int(id) > len(table) {
		return {1, 1, 1}
	}
	c := table[id - 1].color
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
}

// An id the table does not know is treated as inert.
class_of :: proc(id: u16) -> Class {
	table := COMPOUNDS
	if id == 0 || int(id) > len(table) {
		return .Inert
	}
	return table[id - 1].class
}

// In a rule's product: the answer is whichever of the two compounds is not
// neutral, so water thins an acid or a dye without changing what it is.
KEEP_OTHER :: u16(0xFFFF)

// One entry of the matrix: what a class makes when it meets another, as the
// product, how violent it is from 0 to 1, and how hot it gets (below zero is
// cold). The two classes are in either order.
Rule :: struct {
	a, b:       Class,
	product:    u16,
	volatility: f32,
	heat:       f32,
}

// Every pair of classes appears exactly once, 55 rules for 10 classes, and a
// test checks that. Volatility 0.3 and up spatters, and 0.6 and up is a blast.
RULES :: [?]Rule {
	{.Neutral, .Neutral, u16(Id.Water), 0.0, 0.0},
	{.Neutral, .Acid, KEEP_OTHER, 0.0, 0.0},
	{.Neutral, .Base, KEEP_OTHER, 0.0, 0.0},
	{.Neutral, .Fuel, u16(Id.Slurry), 0.0, 0.0},
	{.Neutral, .Oxidizer, KEEP_OTHER, 0.0, 0.0},
	{.Neutral, .Cryo, u16(Id.Slush), 0.0, -40.0},
	{.Neutral, .Gel, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Neutral, .Lube, u16(Id.Slick_Mess), 0.0, 0.0},
	{.Neutral, .Dye, KEEP_OTHER, 0.0, 0.0},
	{.Neutral, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Acid, .Acid, u16(Id.Slurry), 0.0, 0.0},
	{.Acid, .Base, u16(Id.Neutral_Foam), 0.25, 10.0},
	{.Acid, .Fuel, u16(Id.Slurry), 0.2, 15.0},
	{.Acid, .Oxidizer, u16(Id.Acrid_Brew), 0.7, 40.0},
	{.Acid, .Cryo, u16(Id.Slush), 0.1, -30.0},
	{.Acid, .Gel, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Acid, .Lube, u16(Id.Slick_Mess), 0.05, 0.0},
	{.Acid, .Dye, u16(Id.Slurry), 0.05, 0.0},
	{.Acid, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Base, .Base, u16(Id.Slurry), 0.0, 0.0},
	{.Base, .Fuel, u16(Id.Slick_Mess), 0.1, 5.0},
	{.Base, .Oxidizer, u16(Id.Acrid_Brew), 0.35, 25.0},
	{.Base, .Cryo, u16(Id.Slush), 0.1, -30.0},
	{.Base, .Gel, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Base, .Lube, u16(Id.Slick_Mess), 0.0, 0.0},
	{.Base, .Dye, u16(Id.Slurry), 0.05, 0.0},
	{.Base, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Fuel, .Fuel, u16(Id.Slurry), 0.0, 0.0},
	{.Fuel, .Oxidizer, u16(Id.Char), 1.0, 100.0},
	{.Fuel, .Cryo, u16(Id.Slurry), 0.0, -30.0},
	{.Fuel, .Gel, u16(Id.Sticky_Mess), 0.05, 5.0},
	{.Fuel, .Lube, u16(Id.Slick_Mess), 0.1, 0.0},
	{.Fuel, .Dye, u16(Id.Slurry), 0.05, 0.0},
	{.Fuel, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Oxidizer, .Oxidizer, u16(Id.Slurry), 0.0, 0.0},
	{.Oxidizer, .Cryo, u16(Id.Slush), 0.55, -60.0},
	{.Oxidizer, .Gel, u16(Id.Sticky_Mess), 0.2, 10.0},
	{.Oxidizer, .Lube, u16(Id.Slick_Mess), 0.15, 10.0},
	{.Oxidizer, .Dye, u16(Id.Slurry), 0.15, 5.0},
	{.Oxidizer, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Cryo, .Cryo, u16(Id.Slush), 0.0, -40.0},
	{.Cryo, .Gel, u16(Id.Sticky_Mess), 0.0, -20.0},
	{.Cryo, .Lube, u16(Id.Slick_Mess), 0.0, -20.0},
	{.Cryo, .Dye, u16(Id.Slush), 0.0, -30.0},
	{.Cryo, .Inert, u16(Id.Slurry), 0.0, -10.0},
	{.Gel, .Gel, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Gel, .Lube, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Gel, .Dye, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Gel, .Inert, u16(Id.Sticky_Mess), 0.0, 0.0},
	{.Lube, .Lube, u16(Id.Slick_Mess), 0.0, 0.0},
	{.Lube, .Dye, u16(Id.Slick_Mess), 0.0, 0.0},
	{.Lube, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Dye, .Dye, u16(Id.Magenta), 0.0, 0.0},
	{.Dye, .Inert, u16(Id.Slurry), 0.0, 0.0},
	{.Inert, .Inert, u16(Id.Slurry), 0.0, 0.0},
}

// What came of two compounds meeting. `reacted` is false when nothing happened
// because one side was empty or both were the same compound.
Outcome :: struct {
	product:    u16,
	volatility: f32,
	heat:       f32,
	reacted:    bool,
}

// The outcome of `a` meeting `b`. The order does not matter.
react :: proc(a, b: u16) -> Outcome {
	if a == 0 || b == 0 || a == b {
		return {product = a == 0 ? b : a}
	}
	ca, cb := class_of(a), class_of(b)
	table := RULES
	for r in table {
		if (r.a == ca && r.b == cb) || (r.a == cb && r.b == ca) {
			product := r.product
			if product == KEEP_OTHER {
				product = ca == .Neutral ? b : a
			}
			return {product, r.volatility, r.heat, true}
		}
	}
	// Not reachable while every pair has a rule, and a test makes sure it does.
	return {product = u16(Id.Slurry), reacted = true}
}
