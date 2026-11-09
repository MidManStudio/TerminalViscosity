# Compound pages: the format, and the rules of mixing

**Status: proposed.** This is the format worked out for the design in `docs/DESIGN.md`, waiting for the owner's yes. Nothing reads it yet. The files below were checked by hand against the grammar and against the owner's chemistry database in DixScript-Rust, and each builder call was checked for the number of arguments and each enum value for existing. They have **not** been run through the DixScript compiler, which is not run in the sandbox. Run `mdix` over them before relying on them.

The numbers in the water page are drafts taken from a first pass at the chemistry. The owner reworks the chemistry, so the numbers and the reactions are his to change. What is proposed here is the shape.

## What a page is

Each compound has its own page, one `.mdix` file, in the owner's words "a dedicated reactions page". A page says who the compound is, what purity bands it comes in, what temperature does to it by itself, which reactions it starts, and what electrolysis gives from it. Products are compounds too, and each needs a page of its own before it can be made in the game, even if the page only says who it is.

```
data/chem/
  core/enums.mdix       the vocabulary: phases, stations, outcomes
  core/builders.mdix    the functions that build the records of a page
  index.mdix            the pages by id and tier (not yet written): a build for a phone cannot list a folder
  water.mdix            one page for each compound, named by its id
  acetic_acid.mdix
  ethanol.mdix
  sulfuric_acid.mdix
  ethyl_acetate.mdix    and a page for each product
```

## The vocabulary

- **Phase**: SOLID, LIQUID, GAS.
- **Station**: where a reaction needs the vessel to be. ANY is anywhere, then HOT_BATH, COLD_BATH, OVEN, FREEZER, FURNACE, ELECTROLYSIS, DISTILLATION, CENTRIFUGE.
- **Outcome**: what can happen in the world: NONE, FREEZE, BOIL, VAPOR, SPLASH, FUMES, FIRE, BURST.
- **Gear** is written as text in a list, `"goggles"`, `"gas_mask"`, `"ballistic_shield"`, `"fire_extinguisher"`, so a list of it needs no enum. The loader checks the words against a list of its own.

Temperatures are in degrees Celsius, volumes in parts that are relative to each other, and the meters (`unsafe`, `reactivity`, `purity`) run from 0 to 1.

## The records

| Builder | Arguments | What it says |
|---|---|---|
| `identity` | id, name, real_name, formula, phase, tier, price | The id is the key everything else uses. The name is what the game calls it, which may not be the real one. Tier 0 is there from the start, and the price is per litre in the shop, 0 for what is not sold. |
| `properties` | melts_c, boils_c, flash_c, color, unsafe | Melting, boiling and flash points, -1 for none, a colour as text, and how unsafe it is by itself. |
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

The unsafe meter, and the outcomes it can trigger, are for the world to work out: a SPLASH hurts what is near, a BURST breaks the vessel, FUMES need a gas mask, FIRE needs an extinguisher. What each does is not part of this format.

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
  ~identity<object>(id<string>, name<string>, real_name<string>, formula<string>, phase<enum>, tier<int>, price<float>) {
    return {
      id = id,
      name = name,
      real_name = real_name,
      formula = formula,
      phase = phase,
      tier = tier,
      price_per_litre = price
    }
  }

  ~properties<object>(melts_c<float>, boils_c<float>, flash_c<float>, color<string>, unsafe<float>) {
    return {
      melts_c = melts_c,
      boils_c = boils_c,
      flash_c = flash_c,
      color = color,
      unsafe = unsafe
    }
  }

  ~form<object>(id<string>, label<string>, purity_min<float>, purity_max<float>, price_factor<float>) {
    return {
      id = id,
      label = label,
      purity_min = purity_min,
      purity_max = purity_max,
      price_factor = price_factor
    }
  }

  ~behavior<object>(from_c<float>, to_c<float>, outcome<enum>, rate<float>) {
    return {
      from_c = from_c,
      to_c = to_c,
      outcome = outcome,
      rate = rate
    }
  }

  ~part<object>(compound<string>, parts<float>, purity_min<float>, purity_max<float>) {
    return {
      compound = compound,
      parts = parts,
      purity_min = purity_min,
      purity_max = purity_max
    }
  }

  ~product<object>(compound<string>, parts<float>, purity<float>) {
    return {
      compound = compound,
      parts = parts,
      purity = purity
    }
  }

  ~rule<object>(station<enum>, min_c<float>, max_c<float>, catalyst<string>, first<string>, wrong_order<enum>, ratio_tol<float>) {
    return {
      station = station,
      min_c = min_c,
      max_c = max_c,
      catalyst = catalyst,
      first = first,
      wrong_order = wrong_order,
      ratio_tol = ratio_tol
    }
  }

  ~effect<object>(heat_c<float>, unsafe<float>, reactivity<float>) {
    return {
      heat_c = heat_c,
      unsafe = unsafe,
      reactivity = reactivity
    }
  }

  ~failure<object>(over_c<float>, outcome<enum>) {
    return {
      over_c = over_c,
      outcome = outcome
    }
  }

  ~gate<object>(tier<int>, cost<int>) {
    return {
      tier = tier,
      cost = cost
    }
  }

  ~electrolysis<object>(form<string>, catalyst<string>, power<float>, outcome<enum>) {
    return {
      form = form,
      catalyst = catalyst,
      power = power,
      outcome = outcome
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
  // ---- who it is ----
  water.identity:
    core = builders.identity("water", "Water", "water", "H2O", enums.Phase.LIQUID, 0, 0.0),
    properties = builders.properties(0.0, 100.0, -1.0, "#6fb4e8", 0.0)

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

- The pages of the other three first compounds and of the products. The format is ready for them. They wait for the owner's chemistry.
- What a mix does when its reaction is not unlocked: does not happen, or happens and makes an unknown substance.
- How the server learns the pages. Damage and volatility are worked out there, so it needs what the client has, in a form Rust can read.
- Whether the vessel's one temperature is enough, or whether a mix needs a temperature for each ingredient.
- Whether a catalyst can be used up, and whether it can be made worse by sink water, as the notes of the first pass say activated charcoal is.
- The scale of every number. The meters in the example are placeholders.
