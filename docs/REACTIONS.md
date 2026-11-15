# Compound pages: the format, and the rules of mixing

**Status: proposed, and checked by the real compiler.** This is the format worked out for the design in `docs/DESIGN.md`. The `chemistry` package (`client/src/chemistry`) reads it, as tables that `scripts/gen_chem.py` writes from the pages, and implements the rules below with tests, but the lab does not use it yet: it still runs on the placeholder chemicals of the `chem` package. Every page below compiles with the DixScript compiler (the `midmanstudio-mdix` Python package) and passes `scripts/check_chem.py`, which also catches the mistakes listed under "What the checker checks". The numbers in the pages are drafts from a first pass at the chemistry, and the owner reworks the chemistry, so the numbers and the reactions are his to change. What is proposed is the shape.

Two things in the first draft of the chemistry were wrong and are not in the pages. Acetic acid with sulfuric acid does not make acetic anhydride, which is made another way, so that pair is only a hot corrosive mix. And ethanol flashes at about 13 degrees Celsius, not at 365, which is its autoignition temperature.

## What a page is

Each compound has its own page, one `.mdix` file, the owner's "dedicated reactions page". A page says who the compound is and how it looks, what purity bands it comes in, what temperature does to it by itself, which reactions it starts, and what electrolysis gives from it. Products are compounds too. Each needs a page before it can be made in the game, even if the page only says who it is and how it looks.

```
data/chem/
  core/enums.mdix       the vocabulary: phases, stations, outcomes, liquid effects
  core/builders.mdix    the functions that build the records of a page
  index.mdix            the ids of the pages in order: a compound's number is its place in the list, from 1
  water.mdix            one page for each compound, named by its id
  acetic_acid.mdix
  ethanol.mdix
  sulfuric_acid.mdix
  ethyl_acetate.mdix    and a page for each product, 13 so far (17 pages in all)
```

## The vocabulary

- **Phase**: SOLID, LIQUID, GAS.
- **Station**: where a reaction needs the vessel to be. ANY is anywhere, then HOT_BATH, COLD_BATH, OVEN, FREEZER, FURNACE, ELECTROLYSIS, DISTILLATION, CENTRIFUGE.
- **Outcome**: what can happen in the world: NONE, FREEZE, BOIL, VAPOR, SPLASH, FUMES, FIRE, BURST.
- **LiquidEffect**: the small effect of the liquid shader: NONE, SHIMMER, SWIRL, BUBBLES, OILY.
- **Status**: what a compound does to a player on top of its damage: NONE, BURNING, CORRODING, CHOKING, DROWSY.
- **Death**: how a player goes who dies of a compound: NONE, SOAKED, MELTED, BURNED, BLOWN, SUFFOCATED.
- **Gear** is written as text in a list, `"goggles"`, `"gas_mask"`, `"ballistic_shield"`, `"fire_extinguisher"`, so a list of it needs no enum.

An enum comes out of the compiler as its number. Temperatures are in degrees Celsius, volumes in parts that are relative to each other, and the meters (`unsafe`, `reactivity`, `purity`, `clarity`, `strength`) run from 0 to 1. QuickFunc parameters start with an underscore, as the owner asks.

## The records

| Builder | Arguments | What it says |
|---|---|---|
| `identity` | id, name, real_name, formula, phase, level, tier, price | The id is the key everything else uses. The name is what the game calls it, which may not be the real one. The level is how many reactions it is from the base chemicals: 0, 1 or 2. The tier is when it unlocks. The price is per litre: what the shop charges for a base chemical, or what the broker pays for a product, 0 for neither. |
| `properties` | melts_c, boils_c, flash_c, unsafe | Melting, boiling and flash points, -1 for no flash point, and how unsafe it is by itself. |
| `look` | color, seed, clarity, effect, strength | How the liquid is drawn: a base colour as text, a seed for the procedural shader, how clear it is, a small effect and how strong. |
| `harm` | damage, status, status_power, status_seconds, death | What a balloon of the compound does to the player it hits: the damage at a point blank, a status effect with its power and its seconds, and how a player goes who dies of it. It is written as `water.harm`, with one record named `effect`. |
| `form` | id, label, purity_min, purity_max, price_factor | One band of the purity ladder of the compound: its name, the purity it covers, and what it multiplies a price by. |
| `behavior` | from_c, to_c, outcome, rate | What temperature does to it alone, between two temperatures. |
| `part` | compound, parts, purity_min, purity_max | An ingredient of a reaction: which compound, how many parts of the mix, and the band of purity it has to have. |
| `product` | compound, parts, purity | What comes out: which compound, how many parts, and the purity it comes out at. A purity of -1 means the mean of the purities that went in, by volume. |
| `rule` | station, min_c, max_c, catalyst, first, wrong_order, ratio_tol | When it runs: at which station, between which temperatures, with which catalyst present (text, empty for none), which compound has to be in the vessel before the others (empty for none) and what happens if it is not, and how far the proportions may stray. |
| `effect` | heat_c, unsafe, reactivity | What it does while it runs: how many degrees it warms the mix (negative cools it), how much it adds to the unsafe meter, and how fast it goes. |
| `failure` | over_c, outcome | The temperature above which it goes wrong, and what happens. |
| `gate` | tier, cost | What it takes to unlock the reaction. |
| `electrolysis` | form, catalyst, power, outcome | What the electrolysis station does to one band of purity of this compound, with which catalyst (empty for none), how strongly it yields, and a side effect. |

A group of a page is named by the compound and what it is, `water.reactions.vinegar`, and the lists of a reaction hang off it as `.inputs`, `.outputs`, `.failure_outputs` and `.gear`, as the owner's chemistry database does it for isotopes. A reaction that has no `.outputs` is a solution: its ingredients stay in the vessel and the book gives the mix a name in its `note`.

## Levels

The most a chemical can be from the base chemicals is two reactions. Level 0 is a base chemical. A reaction whose inputs are all level 0 makes level 1, and one that has a level 1 chemical among its inputs makes level 2. A level 2 chemical is the end of the line and starts no reaction. A base chemical coming out of a reaction, like the water of an esterification, is a by-product and does not count. Electrolysis is one level too, so it can be run on a level 0 or level 1 compound and its products are one level up.

## How the game reads a vessel against the pages

This is proposed too.

1. A vessel holds a list of ingredients, each a compound, an amount and a purity, and one temperature for the lot. Pouring two lots of the same compound together gives the mean of their purities, by volume.
2. Reactions are looked at when something changes: an ingredient goes in, the temperature moves, a catalyst goes in, or the vessel is put at a station.
3. A reaction **matches** when every one of its inputs is in the vessel with a purity inside the band it asks for; the shares are within `ratio_tol` of the parts (each share may differ from the wanted share by that fraction of it); the catalyst, if there is one, is present, in any amount, and is not used up; the vessel is at the station the rule names, or the station is ANY; and the temperature is between `min_c` and `max_c`.
4. If several match, the one with the most inputs runs. A mix of all four is therefore a reaction of its own and not four of two. Anything it does not use stays in the vessel.
5. `first` is the compound that has to be in the vessel before the others go in. If the others go in first, the `wrong_order` outcome happens instead. It is how "acid into water, never water into acid" is said.
6. Running changes the temperature by `heat_c`, adds `unsafe` to the unsafe meter, and, if there are outputs, turns the inputs into them, with the same total volume split by the parts of the outputs.
7. Above `over_c`, or when the unsafe meter reaches 1, the failure happens: its outcome, and the `.failure_outputs` in place of the `.outputs`.
8. A band of purity is how one reaction can be written twice for one set of inputs, as the clean and the sink-water dilution of the acid are in the example.
9. A reaction is written once, on the page of the compound that is first among its inputs. The book shows it on the page of every compound in it, and of its catalyst.
10. A reaction that is not unlocked does not run. What the player sees then is open.
11. A mix is drawn in the blend of its ingredients' colours by volume, with a pattern whose seed is made from the seeds of the ingredients.

The unsafe meter, and the outcomes it can trigger, are for the world to work out: a SPLASH hurts what is near, a BURST breaks the vessel, FUMES need a gas mask, FIRE needs an extinguisher. What each does is not part of this format.

### What a compound does to a player

Each page has a `harm` group with one record, built by `builders.harm(damage, status, status_power, status_seconds, death)`: the damage in hit points that a balloon of nothing but that compound does at a point blank, from 0 to 100; a status effect from the vocabulary (`NONE`, `BURNING`, `CORRODING`, `CHOKING`, `DROWSY`), its power from 0 to 1 and the seconds it lasts, 0 for both when there is none; and how a player goes who dies of it (`NONE`, `SOAKED`, `MELTED`, `BURNED`, `BLOWN`, `SUFFOCATED`). The checker requires it of every page. All the numbers are drafts.

`harm_of` in `chemistry.odin` reads a mixture: the damage is the mean of the compounds' damage by volume. A compound that is at least a tenth of the mixture gives its status, at the power of its page scaled up to full at half the mixture, for the seconds of its page. Two compounds with the same status add their powers, to at most 1, and the longer time counts, and a hit carries two statuses at most, the strongest. How the player goes is the death of the compound that does the most of the damage, which is its share times its damage, and a tie goes to the one that went in first. The distance from the balloon, the burst radius and what a status does each second belong to the simulation, and are not worked out here.

### What the engine does with them

`chemistry.odin` reads the rules above as follows. Where the rules say nothing, this is what it does, and each of these is open to the owner to change.

- A band of purity runs from its minimum up to but not including its maximum, and the top band includes 1. A window of temperature runs from `min_c` up to but not including `max_c`. A reaction fails at `over_c` and above, which leaves no gap when `over_c` is also `max_c`. A failure never acts outside the shares, bands, catalyst and station that make a reaction match, and the unsafe meter causes a failure only inside the window.
- The shares are worked out among the inputs only, so an ingredient that is not an input, such as a catalyst, does not change them.
- A reaction with outputs uses up the whole of each of its inputs, so a vessel a little off the ratio but inside the tolerance still reacts completely. The total volume of the inputs is split among the outputs by their parts, and an output with a purity of -1 gets the mean purity of the inputs by volume.
- A reaction with no outputs leaves everything where it is, adds its heat and unsafe once, and does not run again while its conditions hold. A failure with failure outputs turns the inputs into those, and a failure without leaves the vessel as it is. The failure's own heat and unsafe are only added when it turns anything into something.
- If several reactions act, the one with the most inputs wins, then one that needs its own station over one that works anywhere, then the one listed first. Pages are numbered by `index.mdix` and a page's reactions are listed by id.
- A reaction that acted, or failed, or was penalised for the wrong order, is not looked at again while the conditions it did that in still hold. More poured in, in the same shares, does not make it act again, so a long pour does not warm a vessel with every drop, and it can act again once the vessel has stopped being that mix and become it again.
- A compound that a reaction made does not count for `first`: nobody poured it, so it cannot have gone in at the wrong time. Without this, the water that the ethyl acetate reaction makes would splash against the acid that is only there as its catalyst.
- A mixture holds eight different compounds. A ninth is refused, and nothing is poured.
- Reactions are run one after another until none acts or eight have, so a product can start a second reaction. Levels cap this at two for the pages as they are.

## What the checker checks

`python3 scripts/check_chem.py data/chem` compiles every page and reports, for each: a page that does not compile or is named for another compound; a level outside 0 to 2; a melting point at or above the boiling point; a bad colour, seed, clarity or strength; a harm that is missing, with a damage outside 0 to 100, a status or a death that is not in the vocabulary, a power outside 0 to 1, a status with no power or no seconds, or a power or seconds on a compound that has no status; purity bands that leave a gap, overlap or do not run from 0 to 1; behaviors that overlap; a reaction with fewer than two inputs, written on a page that is not its first input's, naming a compound with no page, with a catalyst that is also an input, with `first` outside the inputs or without a wrong-order outcome, with a meter outside 0 to 1, with a failure below the window or failure outputs and no failure, or gear that is not in the list; two reactions that can both match; a product of the wrong level, or a level 3; electrolysis of a band that does not exist, of a level 2 compound, or making the wrong level; two compounds with the same seed or colours less than 40 steps apart; and a product that nothing makes.

## The files

`core/enums.mdix`:

```mdix
@CONFIG(
  version -> "1.0.0",
  author -> "Terminal Viscosity - Chemistry Vocabulary",
  encoding -> "UTF-8",
  features -> "advanced"
)

@ENUMS(
  Phase {
    SOLID = 1,
    LIQUID = 2,
    GAS = 3
  }

  Station {
    ANY = 0,
    HOT_BATH = 1,
    COLD_BATH = 2,
    OVEN = 3,
    FREEZER = 4,
    FURNACE = 5,
    ELECTROLYSIS = 6,
    DISTILLATION = 7,
    CENTRIFUGE = 8
  }

  Outcome {
    NONE = 0,
    FREEZE = 1,
    BOIL = 2,
    VAPOR = 3,
    SPLASH = 4,
    FUMES = 5,
    FIRE = 6,
    BURST = 7
  }

  LiquidEffect {
    NONE = 0,
    SHIMMER = 1,
    SWIRL = 2,
    BUBBLES = 3,
    OILY = 4
  }
)
```

`core/builders.mdix`:

```mdix
@CONFIG(
  version -> "1.0.0",
  author -> "Terminal Viscosity - Chemistry Builders",
  encoding -> "UTF-8",
  features -> "advanced"
)

@IMPORTS(
  enums from "enums.mdix"
)

@QUICKFUNCS(
  ~identity<object>(_id<string>, _name<string>, _real_name<string>, _formula<string>, _phase<enum>, _level<int>, _tier<int>, _price<float>) {
    return {
      id = _id,
      name = _name,
      real_name = _real_name,
      formula = _formula,
      phase = _phase,
      level = _level,
      tier = _tier,
      price_per_litre = _price
    }
  }

  ~properties<object>(_melts_c<float>, _boils_c<float>, _flash_c<float>, _unsafe<float>) {
    return {
      melts_c = _melts_c,
      boils_c = _boils_c,
      flash_c = _flash_c,
      unsafe = _unsafe
    }
  }

  ~look<object>(_color<string>, _seed<int>, _clarity<float>, _effect<enum>, _strength<float>) {
    return {
      color = _color,
      seed = _seed,
      clarity = _clarity,
      effect = _effect,
      strength = _strength
    }
  }

  ~form<object>(_id<string>, _label<string>, _purity_min<float>, _purity_max<float>, _price_factor<float>) {
    return {
      id = _id,
      label = _label,
      purity_min = _purity_min,
      purity_max = _purity_max,
      price_factor = _price_factor
    }
  }

  ~behavior<object>(_from_c<float>, _to_c<float>, _outcome<enum>, _rate<float>) {
    return {
      from_c = _from_c,
      to_c = _to_c,
      outcome = _outcome,
      rate = _rate
    }
  }

  ~part<object>(_compound<string>, _parts<float>, _purity_min<float>, _purity_max<float>) {
    return {
      compound = _compound,
      parts = _parts,
      purity_min = _purity_min,
      purity_max = _purity_max
    }
  }

  ~product<object>(_compound<string>, _parts<float>, _purity<float>) {
    return {
      compound = _compound,
      parts = _parts,
      purity = _purity
    }
  }

  ~rule<object>(_station<enum>, _min_c<float>, _max_c<float>, _catalyst<string>, _first<string>, _wrong_order<enum>, _ratio_tol<float>) {
    return {
      station = _station,
      min_c = _min_c,
      max_c = _max_c,
      catalyst = _catalyst,
      first = _first,
      wrong_order = _wrong_order,
      ratio_tol = _ratio_tol
    }
  }

  ~effect<object>(_heat_c<float>, _unsafe<float>, _reactivity<float>) {
    return {
      heat_c = _heat_c,
      unsafe = _unsafe,
      reactivity = _reactivity
    }
  }

  ~failure<object>(_over_c<float>, _outcome<enum>) {
    return {
      over_c = _over_c,
      outcome = _outcome
    }
  }

  ~gate<object>(_tier<int>, _cost<int>) {
    return {
      tier = _tier,
      cost = _cost
    }
  }

  ~electrolysis<object>(_form<string>, _catalyst<string>, _power<float>, _outcome<enum>) {
    return {
      form = _form,
      catalyst = _catalyst,
      power = _power,
      outcome = _outcome
    }
  }
)
```

`water.mdix`, the page of the compound that matters most to the sink:

```mdix
@CONFIG(
  version -> "1.0.0",
  author -> "Terminal Viscosity - Compound Page: Water",
  encoding -> "UTF-8",
  features -> "advanced"
)

@IMPORTS(
  enums from "core/enums.mdix",
  builders from "core/builders.mdix"
)

@DATA(
  // ---- who it is: level 0 is a base chemical, bought or fetched, not made ----
  water.identity:
    core = builders.identity("water", "Water", "water", "H2O", enums.Phase.LIQUID, 0, 0, 0.0),
    properties = builders.properties(0.0, 100.0, -1.0, 0.0),
    look = builders.look("#6fb4e8", 101, 0.9, enums.LiquidEffect.SHIMMER, 0.2)

  // ---- the ladder of purity: the bands that reactions can ask for ----
  water.forms::
    builders.form("sink", "Sink water", 0.0, 0.5, 0.0),
    builders.form("distilled", "Distilled water", 0.5, 0.95, 2.0),
    builders.form("ultra_pure", "Ultra pure water", 0.95, 1.0, 8.0)

  // ---- what temperature does to it on its own ----
  water.behaviors::
    builders.behavior(-273.0, 0.0, enums.Outcome.FREEZE, 1.0),
    builders.behavior(100.0, 1000.0, enums.Outcome.BOIL, 1.0)

  // ---- reactions it starts: written here once, shown on the page of every compound in them ----
  water.reactions.vinegar:
    rule = builders.rule(enums.Station.ANY, 0.0, 100.0, "", "", enums.Outcome.NONE, 0.5),
    effect = builders.effect(0.0, 0.0, 0.2),
    gate = builders.gate(1, 0),
    note = "Dilute acetic acid, vinegar. The ingredients stay in the vessel and the book names the result."
  water.reactions.vinegar.inputs::
    builders.part("water", 1.0, 0.0, 1.0),
    builders.part("acetic_acid", 1.0, 0.0, 1.0)

  water.reactions.hydrated_spirit:
    rule = builders.rule(enums.Station.ANY, 0.0, 78.0, "", "", enums.Outcome.NONE, 0.5),
    effect = builders.effect(2.0, 0.05, 0.2),
    gate = builders.gate(1, 0),
    note = "Water and ethanol mix freely and warm a little. The spirit is weaker and flashes less readily, so it is safer to heat."
  water.reactions.hydrated_spirit.inputs::
    builders.part("water", 1.0, 0.0, 1.0),
    builders.part("ethanol", 1.0, 0.0, 1.0)

  water.reactions.dilute_acid_clean:
    rule = builders.rule(enums.Station.ANY, 0.0, 100.0, "", "water", enums.Outcome.SPLASH, 0.5),
    effect = builders.effect(40.0, 0.5, 0.9),
    failure = builders.failure(100.0, enums.Outcome.SPLASH),
    gate = builders.gate(2, 1500),
    note = "Acid into water, never water into acid. Water that is distilled or better dilutes the acid cleanly."
  water.reactions.dilute_acid_clean.inputs::
    builders.part("water", 9.0, 0.5, 1.0),
    builders.part("sulfuric_acid", 1.0, 0.0, 1.0)
  water.reactions.dilute_acid_clean.outputs::
    builders.product("dilute_sulfuric_acid", 10.0, -1.0)
  water.reactions.dilute_acid_clean.gear:: "goggles", "gas_mask"

  water.reactions.dilute_acid_sink:
    rule = builders.rule(enums.Station.ANY, 0.0, 100.0, "", "water", enums.Outcome.SPLASH, 0.5),
    effect = builders.effect(40.0, 0.7, 0.9),
    failure = builders.failure(100.0, enums.Outcome.SPLASH),
    gate = builders.gate(2, 1500),
    note = "The same mix with sink water: its minerals char and cloud the acid, and the product comes out at a purity of 0.5."
  water.reactions.dilute_acid_sink.inputs::
    builders.part("water", 9.0, 0.0, 0.5),
    builders.part("sulfuric_acid", 1.0, 0.0, 1.0)
  water.reactions.dilute_acid_sink.outputs::
    builders.product("dilute_sulfuric_acid", 10.0, 0.5)
  water.reactions.dilute_acid_sink.gear:: "goggles", "gas_mask"

  water.reactions.pickling_mix:
    rule = builders.rule(enums.Station.ANY, 0.0, 100.0, "", "water", enums.Outcome.SPLASH, 0.5),
    effect = builders.effect(35.0, 0.5, 0.7),
    failure = builders.failure(100.0, enums.Outcome.SPLASH),
    gate = builders.gate(2, 1500),
    note = "Water, acetic acid and sulfuric acid: a corrosive pickling solution that spits if it boils. The ingredients stay in the vessel."
  water.reactions.pickling_mix.inputs::
    builders.part("water", 6.0, 0.0, 1.0),
    builders.part("acetic_acid", 3.0, 0.0, 1.0),
    builders.part("sulfuric_acid", 1.0, 0.0, 1.0)
  water.reactions.pickling_mix.gear:: "goggles", "gas_mask"

  water.reactions.spirit_and_acids:
    rule = builders.rule(enums.Station.ANY, 25.0, 150.0, "", "", enums.Outcome.NONE, 0.5),
    effect = builders.effect(1.0, 0.3, 0.1),
    failure = builders.failure(150.0, enums.Outcome.BURST),
    gate = builders.gate(2, 3000),
    note = "All four together. Cool, it settles slowly into ethyl acetate and water. Hot and shut in, the acid dehydrates the spirit and the vessel bursts."
  water.reactions.spirit_and_acids.inputs::
    builders.part("water", 1.0, 0.0, 1.0),
    builders.part("ethanol", 1.0, 0.0, 1.0),
    builders.part("acetic_acid", 1.0, 0.0, 1.0),
    builders.part("sulfuric_acid", 1.0, 0.0, 1.0)
  water.reactions.spirit_and_acids.outputs::
    builders.product("ethyl_acetate", 1.0, -1.0),
    builders.product("water", 1.0, -1.0)
  water.reactions.spirit_and_acids.failure_outputs::
    builders.product("diethyl_ether", 1.0, -1.0),
    builders.product("ethylene", 1.0, -1.0),
    builders.product("sulfur_dioxide", 1.0, -1.0)
  water.reactions.spirit_and_acids.gear:: "ballistic_shield", "gas_mask", "fire_extinguisher"

  // ---- what electrolysis gives, by purity band ----
  water.electrolysis.sink:
    run = builders.electrolysis("sink", "", 1.0, enums.Outcome.FUMES)
  water.electrolysis.sink.products::
    builders.product("hydrogen", 2.0, -1.0),
    builders.product("oxygen", 1.0, -1.0),
    builders.product("chlorine", 0.1, -1.0)

  water.electrolysis.distilled:
    run = builders.electrolysis("distilled", "", 0.5, enums.Outcome.NONE)
  water.electrolysis.distilled.products::
    builders.product("hydrogen", 2.0, -1.0),
    builders.product("oxygen", 1.0, -1.0)

  water.electrolysis.ultra_pure:
    run = builders.electrolysis("ultra_pure", "sulfuric_acid", 0.5, enums.Outcome.NONE)
  water.electrolysis.ultra_pure.products::
    builders.product("hydrogen", 2.0, -1.0),
    builders.product("oxygen", 1.0, -1.0)
)
```

## What it leaves open

- What the owner's chemistry adds. The pages of ethylene, sulfur dioxide and hydrogen were missing when the pages were given to Claude, who wrote them to the pattern of the others (seeds 808, 909 and 1010, the real melting and boiling points, a draft unsafe meter, a draft colour). They are drafts to be replaced.
- What a mix does when its reaction is not unlocked: does not happen, or happens and makes an unknown substance.
- How the server learns the pages. The client has them as generated Odin tables. Damage and volatility are worked out in Rust, so the server needs a copy made from the same pages by the same script, which is not written.
- Whether the vessel's one temperature is enough, or whether a mix needs a temperature for each ingredient.
- Whether a catalyst can be used up, and whether it counts as a level.
- Whether electrolysis should count as a level.
- The scale of every number. The meters in the pages are placeholders.
