// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "chemistry.odin"
// ============================================================================

// Package chemistry is what the compound pages in data/chem say, as tables, and the rules of
// docs/REACTIONS.md for reading a mixture against them: which reaction runs, what it makes, and
// what goes wrong. It has no raylib dependency and does not know about vessels, balloons or the
// world: a caller keeps a `Mixture` and asks what happens. The tables are in `pages_data.odin`,
// which scripts/gen_chem.py writes from the pages.
package chemistry

MAX_INGREDIENTS :: 8 // the different compounds one mixture can hold
MAX_STEPS :: 8 // the most reactions one `settle` runs, so a loop in the pages cannot hang the game
ALL_UNLOCKED :: u64(0xFFFFFFFFFFFFFFFF)

// A list inside one of the tables: `count` rows from `first`.
Span :: struct {
	first, count: u16,
}

Gear :: bit_set[Gear_Kind;u8]

Compound :: struct {
	id, name, real_name, formula: string,
	phase:                        Phase,
	level, tier:                  u8,
	price:                        f32, // per litre, at purity band factor 1
	melts_c, boils_c, flash_c:    f32, // flash_c is -1 for none
	unsafe:                       f32,
	color:                        [3]u8,
	seed:                         u32,
	clarity:                      f32,
	effect:                       Liquid_Effect,
	strength:                     f32,
	forms, behaviors:             Span,
}

// One band of the purity ladder of a compound: from `purity_min` up to but not including
// `purity_max`, and the top band takes 1 too.
Form :: struct {
	compound:                     Id,
	id, label:                    string,
	purity_min, purity_max:       f32,
	price_factor:                 f32,
}

// What temperature does to a compound alone, from `from_c` up to but not including `to_c`.
Behavior :: struct {
	compound:     Id,
	from_c, to_c: f32,
	event:        Event,
	rate:         f32,
}

// An input of a reaction: how many parts of the mix, and the band of purity it has to have.
Part :: struct {
	compound:               Id,
	parts:                  f32,
	purity_min, purity_max: f32,
}

// An output of a reaction. A purity of -1 means the mean purity of what went in, by volume.
Product :: struct {
	compound: Id,
	parts:    f32,
	purity:   f32,
}

Reaction :: struct {
	id:              string,
	owner:           Id, // the page it is written on, which is its first input
	station:         Station,
	min_c, max_c:    f32, // it runs from min_c up to but not including max_c
	catalyst:        Id,
	first:           Id,
	wrong_order:     Event,
	ratio_tol:       f32,
	heat_c:          f32, // what it adds to the temperature
	unsafe:          f32, // what it adds to the unsafe meter
	reactivity:      f32,
	has_failure:     bool,
	over_c:          f32, // it fails at this temperature and above
	failure:         Event,
	tier:            u8,
	cost:            u16,
	note:            string,
	inputs:          Span, // into `parts`
	outputs:         Span, // into `products`
	failure_outputs: Span, // into `products`
	gear:            Gear,
}

// What electrolysis does to one purity band of a compound.
Electrolysis :: struct {
	compound: Id,
	form:     string, // the id of a band of the compound
	catalyst: Id,
	power:    f32,
	event:    Event,
	products: Span, // into `products`
}

// The compound with this number, or nil for 0 and numbers past the last.
compound_of :: proc(id: Id) -> ^Compound {
	if id == .None || int(id) > COMPOUND_COUNT {
		return nil
	}
	return &compounds[int(id) - 1]
}

// The number of the compound with this page id, such as "sulfuric_acid", or .None.
id_of :: proc(page_id: string) -> Id {
	for i in 0 ..< COMPOUND_COUNT {
		if compounds[i].id == page_id {
			return Id(i + 1)
		}
	}
	return .None
}

// The table index of the reaction with this id, or -1.
reaction_index :: proc(reaction_id: string) -> int {
	for i in 0 ..< REACTION_COUNT {
		if reactions[i].id == reaction_id {
			return i
		}
	}
	return -1
}

in_band :: proc(purity, lo, hi: f32) -> bool {
	return purity >= lo && (purity < hi || (hi >= 1 && purity <= hi))
}

// The purity band of a compound that `purity` falls in, such as "Distilled water" for water at 0.7.
form_of :: proc(id: Id, purity: f32) -> (form: ^Form, ok: bool) {
	c := compound_of(id)
	if c == nil {
		return
	}
	for i in c.forms.first ..< c.forms.first + c.forms.count {
		if in_band(purity, forms[i].purity_min, forms[i].purity_max) {
			return &forms[i], true
		}
	}
	return
}

// What electrolysis does to a compound at this purity, if its page says.
electrolysis_of :: proc(id: Id, purity: f32) -> (run: ^Electrolysis, ok: bool) {
	band, found := form_of(id, purity)
	if !found {
		return
	}
	for i in 0 ..< ELECTROLYSIS_COUNT {
		if electrolyses[i].compound == id && electrolyses[i].form == band.id {
			return &electrolyses[i], true
		}
	}
	return
}

// One compound in a mixture, with how much of it and how pure. `made` is true when a reaction
// produced it and false when somebody poured it in, which matters for the order of pouring.
Ingredient :: struct {
	compound: Id,
	ml:       f32,
	purity:   f32,
	made:     bool,
}

// What is in a vessel: up to MAX_INGREDIENTS compounds, in the order they went in, at one
// temperature, with the unsafe meter. `ran` and `failed` remember the reactions that have
// already done their part, or their penalty, for this set of ingredients, one bit for each table
// index, so a reaction that leaves its inputs in the vessel does not run again every frame.
Mixture :: struct {
	items:        [MAX_INGREDIENTS]Ingredient,
	count:        int,
	heat_c:       f32,
	unsafe:       f32, // from 0 to 1
	ran, failed:  u64,
}

mix_volume :: proc(m: ^Mixture) -> f32 {
	total := f32(0)
	for i in 0 ..< m.count {
		total += m.items[i].ml
	}
	return total
}

// Where the compound is in the list, or -1.
mix_find :: proc(m: ^Mixture, id: Id) -> int {
	for i in 0 ..< m.count {
		if m.items[i].compound == id {
			return i
		}
	}
	return -1
}

// Puts `ml` of a compound into the list, joining one of the same compound with the purities
// averaged by volume. False if it needs a place and the list is full.
add_ingredient :: proc(m: ^Mixture, id: Id, ml, purity: f32, made: bool) -> bool {
	if ml <= 0 {
		return true
	}
	at := mix_find(m, id)
	if at >= 0 {
		it := &m.items[at]
		total := it.ml + ml
		it.purity = (it.purity * it.ml + purity * ml) / total
		it.ml = total
		return true
	}
	if m.count >= MAX_INGREDIENTS {
		return false
	}
	m.items[m.count] = {id, ml, purity, made}
	m.count += 1
	return true
}

// Pours `ml` of a compound at `heat_c` degrees into the mixture. The temperature becomes the
// mean of the two by volume, and the reactions that had already run get their turn again,
// because the ingredients are not what they were. False, with nothing changed, if there is no
// room for another compound.
mix_add :: proc(m: ^Mixture, id: Id, ml, purity, heat_c: f32) -> bool {
	if id == .None || ml <= 0 {
		return false
	}
	before := mix_volume(m)
	if !add_ingredient(m, id, ml, purity, false) {
		return false
	}
	m.heat_c = (m.heat_c * before + heat_c * ml) / (before + ml)
	m.ran, m.failed = 0, 0
	return true
}

remove_at :: proc(m: ^Mixture, at: int) {
	for i in at ..< m.count - 1 {
		m.items[i] = m.items[i + 1]
	}
	m.count -= 1
	m.items[m.count] = {}
}

// Whether everything a reaction asks of the vessel except its temperature is so: every input is
// there in the purity band it wants, in shares within `ratio_tol` of its parts, the catalyst is
// there in any amount, and the vessel is at the station the reaction needs.
context_ok :: proc(m: ^Mixture, r: ^Reaction, station: Station) -> bool {
	if r.station != .Any && r.station != station {
		return false
	}
	if r.catalyst != .None && mix_find(m, r.catalyst) < 0 {
		return false
	}
	total, wanted := f32(0), f32(0)
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		at := mix_find(m, parts[k].compound)
		if at < 0 || !in_band(m.items[at].purity, parts[k].purity_min, parts[k].purity_max) {
			return false
		}
		total += m.items[at].ml
		wanted += parts[k].parts
	}
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		share := m.items[mix_find(m, parts[k].compound)].ml / total
		goal := parts[k].parts / wanted
		if abs(share - goal) > r.ratio_tol * goal {
			return false
		}
	}
	return true
}

// Whether the compound that has to be in first was poured in before the other inputs that were
// poured in. A compound a reaction made does not count: nobody poured it, so it cannot have gone
// in at the wrong time.
in_order :: proc(m: ^Mixture, r: ^Reaction) -> bool {
	if r.first == .None {
		return true
	}
	first_at := mix_find(m, r.first)
	if m.items[first_at].made {
		return true
	}
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		at := mix_find(m, parts[k].compound)
		if parts[k].compound != r.first && !m.items[at].made && at < first_at {
			return false
		}
	}
	return true
}

Pick_Kind :: enum {
	None,
	Run, // the reaction runs
	Fail, // it goes wrong
}

// Which reaction acts on the mixture now, and whether it runs or fails; index -1 and .None when
// none does. A reaction that is not unlocked (its bit in `unlocked`) is passed over, and so is
// one that has already run, or failed, or been penalised for the wrong order, for these
// ingredients. Of those that act, the one with the most inputs wins, then one that needs its own
// station over one that works anywhere, then the one that comes first in the table.
pick :: proc(m: ^Mixture, station: Station, unlocked: u64) -> (index: int, kind: Pick_Kind) {
	index = -1
	best_inputs, best_named := 0, false
	for i in 0 ..< REACTION_COUNT {
		bit := u64(1) << u64(i)
		r := &reactions[i]
		if unlocked & bit == 0 || int(r.inputs.count) < best_inputs || !context_ok(m, r, station) {
			continue
		}
		in_window := m.heat_c >= r.min_c && m.heat_c < r.max_c
		failing := r.has_failure && (m.heat_c >= r.over_c || (in_window && m.unsafe + r.unsafe >= 1))
		acts: Pick_Kind
		switch {
		case failing && m.failed & bit == 0:
			acts = .Fail
		case !failing && in_window && m.ran & bit == 0:
			acts = .Run
		case:
			continue
		}
		if int(r.inputs.count) > best_inputs || (r.station != .Any && !best_named) {
			index, kind = i, acts
			best_inputs, best_named = int(r.inputs.count), r.station != .Any
		}
	}
	return
}

// What one reaction did.
Step :: struct {
	reaction:    int, // its index in the table
	event:       Event, // what happened in the world, .None for a quiet run
	failed:      bool, // it went wrong: `event` is its failure
	wrong_order: bool, // the compound that had to go in first did not: `event` is the penalty
}

Settled :: struct {
	steps: [MAX_STEPS]Step,
	count: int,
}

// Turns the inputs of a reaction into `made`, the whole volume of the inputs split by the parts
// of the products, at the mean purity of the inputs unless a product gives its own, and applies
// the heat and the unsafe meter of the reaction.
convert :: proc(m: ^Mixture, r: ^Reaction, made: Span) {
	volume, purity := f32(0), f32(0)
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		it := m.items[mix_find(m, parts[k].compound)]
		volume += it.ml
		purity += it.purity * it.ml
	}
	purity /= volume
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		remove_at(m, mix_find(m, parts[k].compound))
	}
	total := f32(0)
	for k in made.first ..< made.first + made.count {
		total += products[k].parts
	}
	for k in made.first ..< made.first + made.count {
		p := products[k].purity < 0 ? purity : products[k].purity
		add_ingredient(m, products[k].compound, volume * products[k].parts / total, p, true)
	}
	m.heat_c += r.heat_c
	m.unsafe = min(m.unsafe + r.unsafe, 1)
}

// Lets the mixture react as far as it will at this station: the reaction `pick` chooses runs,
// then the next one, until nothing acts or MAX_STEPS have. The steps say what happened in the
// world, and the mixture is changed. `unlocked` has a bit for each reaction the player has.
//
// A reaction with outputs turns its inputs into them. One with none leaves everything in the
// vessel, adds its heat and unsafe once, and does not run again until something is poured in. A
// failure with failure outputs turns the inputs into those, and one without leaves the vessel as
// it is. If the compound that had to go in first did not, the `wrong_order` event happens
// instead of the reaction and the vessel is left as it is.
settle :: proc(m: ^Mixture, station: Station, unlocked := ALL_UNLOCKED) -> (done: Settled) {
	for done.count < MAX_STEPS {
		index, kind := pick(m, station, unlocked)
		if kind == .None {
			break
		}
		r := &reactions[index]
		bit := u64(1) << u64(index)
		step := Step {
			reaction = index,
		}
		switch {
		case !in_order(m, r):
			m.ran |= bit
			m.failed |= bit
			step.event, step.wrong_order = r.wrong_order, true
		case kind == .Fail:
			step.event, step.failed = r.failure, true
			if r.failure_outputs.count == 0 {
				m.failed |= bit
			} else {
				convert(m, r, r.failure_outputs)
			}
		case r.outputs.count == 0:
			m.heat_c += r.heat_c
			m.unsafe = min(m.unsafe + r.unsafe, 1)
			m.ran |= bit
		case:
			convert(m, r, r.outputs)
		}
		done.steps[done.count] = step
		done.count += 1
	}
	return
}

// The colour of a mixture as red, green and blue from 0 to 1: the colours of the ingredients
// blended by volume. Empty is white.
mix_color :: proc(m: ^Mixture) -> [3]f32 {
	total := mix_volume(m)
	if total <= 0 {
		return {1, 1, 1}
	}
	sum := [3]f32{}
	for i in 0 ..< m.count {
		c := compound_of(m.items[i].compound).color
		sum += [3]f32{f32(c.r), f32(c.g), f32(c.b)} * m.items[i].ml
	}
	return sum / (total * 255)
}

// The seed of a mixture's pattern: a compound alone keeps its own seed, and a mix has one made
// from the seeds of its ingredients that does not depend on the order they went in.
mix_seed :: proc(m: ^Mixture) -> u32 {
	if m.count == 1 {
		return compound_of(m.items[0].compound).seed
	}
	acc := u32(0)
	for i in 0 ..< m.count {
		s := compound_of(m.items[i].compound).seed
		acc += (s * 0x9E3779B1) ~ (s >> 7)
	}
	return acc
}

// The clarity of a mixture, from 0 to 1: the clarities of the ingredients blended by volume.
mix_clarity :: proc(m: ^Mixture) -> f32 {
	total := mix_volume(m)
	if total <= 0 {
		return 1
	}
	sum := f32(0)
	for i in 0 ..< m.count {
		sum += compound_of(m.items[i].compound).clarity * m.items[i].ml
	}
	return sum / total
}
