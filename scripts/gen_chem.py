#!/usr/bin/env python3
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "gen_chem.py"
# ============================================================================
"""Writes client/src/chemistry/pages_data.odin from the compound pages in data/chem.

The pages are compiled by the real DixScript compiler (pip install midmanstudio-mdix) after
scripts/check_chem.py has passed on them, and the numbers of the compounds come from the order
of data/chem/index.mdix. Usage: python3 scripts/gen_chem.py [--check] [folder] [output].
With --check nothing is written, and the exit code is 1 if the file on disk is not what the pages
make, which is how CI notices a page that was edited without running this again.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_chem  # noqa: E402

MAX_REACTIONS = 64  # one bit each in the u64 that remembers which have run
GEAR_NAMES = ["goggles", "gas_mask", "ballistic_shield", "fire_extinguisher"]


def ada(name):
    """water_vapor -> Water_Vapor, HOT_BATH -> Hot_Bath."""
    return "_".join(part.capitalize() for part in name.lower().split("_"))


def num(value):
    """A number as Odin source: whole floats keep their point."""
    if isinstance(value, float):
        text = repr(value)
        return text if ("." in text or "e" in text) else text + ".0"
    return str(value)


def text(value):
    return json.dumps(value, ensure_ascii=True)


class Table:
    """Rows of one struct type, with spans handed out to the rows that own lists."""

    def __init__(self):
        self.rows = []

    def add(self, rows):
        first = len(self.rows)
        self.rows.extend(rows)
        return "{%d, %d}" % (first, len(rows))


def build(folder):
    errors = []
    pages = check_chem.load_pages(folder, errors)
    listed = check_chem.load_index(folder, errors)
    enums = check_chem.enum_values(folder)
    if errors:
        raise SystemExit("\n".join(errors))
    order = list(listed)
    ids = {stem: n + 1 for n, stem in enumerate(order)}

    def ref(stem):
        return "." + ada(stem) if stem else ".None"

    def enum(kind, value):
        return "." + ada(enums[kind][value])

    forms, behaviors, parts, products, reactions, electro = Table(), Table(), Table(), Table(), Table(), Table()
    compounds = []
    for stem in order:
        page = pages[stem]
        core, props, look = (page["identity"][k] for k in ("core", "properties", "look"))
        form_span = forms.add(
            [
                "{compound = %s, id = %s, label = %s, purity_min = %s, purity_max = %s, price_factor = %s}"
                % (ref(stem), text(f["id"]), text(f["label"]), num(f["purity_min"]), num(f["purity_max"]), num(f["price_factor"]))
                for f in page.get("forms", [])
            ]
        )
        behavior_span = behaviors.add(
            [
                "{compound = %s, from_c = %s, to_c = %s, event = %s, rate = %s}"
                % (ref(stem), num(b["from_c"]), num(b["to_c"]), enum("Outcome", b["outcome"]), num(b["rate"]))
                for b in page.get("behaviors", [])
            ]
        )
        color = [int(look["color"][i : i + 2], 16) for i in (1, 3, 5)]
        compounds.append(
            "{id = %s, name = %s, real_name = %s, formula = %s, phase = %s, level = %d, tier = %d, price = %s, "
            "melts_c = %s, boils_c = %s, flash_c = %s, unsafe = %s, color = {%d, %d, %d}, seed = %d, clarity = %s, "
            "effect = %s, strength = %s, forms = %s, behaviors = %s}"
            % (
                text(core["id"]), text(core["name"]), text(core["real_name"]), text(core["formula"]),
                enum("Phase", core["phase"]), core["level"], core["tier"], num(core["price_per_litre"]),
                num(props["melts_c"]), num(props["boils_c"]), num(props["flash_c"]), num(props["unsafe"]),
                color[0], color[1], color[2], look["seed"], num(look["clarity"]),
                enum("LiquidEffect", look["effect"]), num(look["strength"]), form_span, behavior_span,
            )
        )

    def part_rows(items):
        return [
            "{compound = %s, parts = %s, purity_min = %s, purity_max = %s}"
            % (ref(p["compound"]), num(p["parts"]), num(p["purity_min"]), num(p["purity_max"]))
            for p in items
        ]

    def product_rows(items):
        return ["{compound = %s, parts = %s, purity = %s}" % (ref(p["compound"]), num(p["parts"]), num(p["purity"])) for p in items]

    for stem in order:
        for rid in sorted(pages[stem].get("reactions", {})):
            r = pages[stem]["reactions"][rid]
            rule, eff, gate, fail = r["rule"], r["effect"], r["gate"], r.get("failure")
            gear = ", ".join("." + ada(g) for g in GEAR_NAMES if g in r.get("gear", []))
            reactions.add(
                [
                    "{id = %s, owner = %s, station = %s, min_c = %s, max_c = %s, catalyst = %s, first = %s, wrong_order = %s, "
                    "ratio_tol = %s, heat_c = %s, unsafe = %s, reactivity = %s, has_failure = %s, over_c = %s, failure = %s, "
                    "tier = %d, cost = %d, note = %s, inputs = %s, outputs = %s, failure_outputs = %s, gear = {%s}}"
                    % (
                        text(rid), ref(stem), enum("Station", rule["station"]), num(rule["min_c"]), num(rule["max_c"]),
                        ref(rule["catalyst"]), ref(rule["first"]), enum("Outcome", rule["wrong_order"]),
                        num(rule["ratio_tol"]), num(eff["heat_c"]), num(eff["unsafe"]), num(eff["reactivity"]),
                        "true" if fail else "false", num(fail["over_c"]) if fail else "0.0",
                        enum("Outcome", fail["outcome"]) if fail else ".None",
                        gate["tier"], gate["cost"], text(r.get("note", "")),
                        parts.add(part_rows(r["inputs"])), products.add(product_rows(r.get("outputs", []))),
                        products.add(product_rows(r.get("failure_outputs", []))), gear,
                    )
                ]
            )
    if len(reactions.rows) > MAX_REACTIONS:
        raise SystemExit(f"{len(reactions.rows)} reactions: the game remembers {MAX_REACTIONS} at most")
    for stem in order:
        for form in sorted(pages[stem].get("electrolysis", {})):
            run = pages[stem]["electrolysis"][form]
            spec = run["run"]
            electro.add(
                [
                    "{compound = %s, form = %s, catalyst = %s, power = %s, event = %s, products = %s}"
                    % (ref(stem), text(form), ref(spec["catalyst"]), num(spec["power"]), enum("Outcome", spec["outcome"]),
                       products.add(product_rows(run["products"])))
                ]
            )

    def enum_source(name, kind):
        members = ",\n".join("\t%s = %d" % (ada(n), v) for v, n in sorted(enums[kind].items()))
        return "%s :: enum u8 {\n%s,\n}\n" % (name, members)

    def table(name, kind, rows):
        body = "".join("\t%s,\n" % row for row in rows)
        return "@(rodata)\n%s := [%d]%s{\n%s}\n" % (name, len(rows), kind, body)

    out = [
        "// ============================================================================",
        "// NOTICE: Full documentation, design decisions, and fix history for this file",
        '// live in docs/client.md, section "pages_data.odin"',
        "// ============================================================================",
        "",
        "// GENERATED by scripts/gen_chem.py from the pages in data/chem. Do not edit by hand: change a page and run the",
        "// script again. Compound number n is the n-th line of data/chem/index.mdix.",
        "package chemistry",
        "",
        "Id :: enum u16 {\n\tNone,\n" + ",\n".join("\t" + ada(s) for s in order) + ",\n}\n",
        "COMPOUND_COUNT :: %d" % len(order),
        "FORM_COUNT :: %d" % len(forms.rows),
        "BEHAVIOR_COUNT :: %d" % len(behaviors.rows),
        "PART_COUNT :: %d" % len(parts.rows),
        "PRODUCT_COUNT :: %d" % len(products.rows),
        "REACTION_COUNT :: %d" % len(reactions.rows),
        "ELECTROLYSIS_COUNT :: %d" % len(electro.rows),
        "",
        enum_source("Phase", "Phase"),
        enum_source("Station", "Station"),
        enum_source("Event", "Outcome"),
        enum_source("Liquid_Effect", "LiquidEffect"),
        "Gear_Kind :: enum u8 {\n" + ",\n".join("\t" + ada(g) for g in GEAR_NAMES) + ",\n}\n",
        table("compounds", "Compound", compounds),
        table("forms", "Form", forms.rows),
        table("behaviors", "Behavior", behaviors.rows),
        table("parts", "Part", parts.rows),
        table("products", "Product", products.rows),
        table("reactions", "Reaction", reactions.rows),
        table("electrolyses", "Electrolysis", electro.rows),
    ]
    return "\n".join(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv[1:]
    folder = args[0] if args else "data/chem"
    target = args[1] if len(args) > 1 else "client/src/chemistry/pages_data.odin"
    here = os.path.dirname(os.path.abspath(__file__))
    if not os.path.isdir(folder):
        print(f"no folder {folder}: nothing to generate")
        return 0
    if subprocess.run([sys.executable, os.path.join(here, "check_chem.py"), folder]).returncode != 0:
        print("the pages do not pass check_chem.py, so nothing was generated")
        return 1
    source = build(folder)
    if check:
        current = open(target).read() if os.path.isfile(target) else None
        if current != source:
            print(f"{target} is not what the pages in {folder} make: run python3 scripts/gen_chem.py")
            return 1
        print(f"{target} is what the pages make")
        return 0
    with open(target, "w") as f:
        f.write(source)
    print(f"wrote {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
