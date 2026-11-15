#!/usr/bin/env python3
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "check_chem.py"
# ============================================================================
"""Checks the compound pages in data/chem against the rules of docs/REACTIONS.md.

Each page is compiled by the real DixScript compiler (pip install midmanstudio-mdix), read back,
and checked: who it is, its purity bands, what it does to a player, its reactions, its
electrolysis, the pages together, and index.mdix, which gives each compound its number. Usage: python3 scripts/check_chem.py [folder]. Exits 1 if anything is wrong.
"""
import os
import re
import sys

MAX_LEVEL = 2
GEAR = {"goggles", "gas_mask", "ballistic_shield", "fire_extinguisher"}
MIN_COLOR_DISTANCE = 40.0


class Quiet:
    """Silences the compiler's own log lines, which it writes below Python's reach."""

    def __enter__(self):
        sys.stdout.flush()
        self.saved = [os.dup(1), os.dup(2)]
        null = os.open(os.devnull, os.O_WRONLY)
        os.dup2(null, 1)
        os.dup2(null, 2)
        os.close(null)

    def __exit__(self, *exc):
        os.dup2(self.saved[0], 1)
        os.dup2(self.saved[1], 2)
        for fd in self.saved:
            os.close(fd)


def read(db, path):
    """Reads the value at `path` of a compiled page into dicts, lists and plain values."""
    kind = db.get_type(path)
    if kind == "array":
        return [read(db, f"{path}[{i}]") for i in range(db.get_array_length(path))]
    if kind == "object":
        return {k: read(db, f"{path}.{k}") for k in db.get_keys(path) if "[" not in k}
    getter = {"string": db.get_string, "int": db.get_int, "double": db.get_double, "bool": db.get_bool}
    return getter[kind](path)


def enum_values(folder):
    """The names and numbers of core/enums.mdix, as {enum: {number: name}}."""
    text = open(os.path.join(folder, "core", "enums.mdix")).read().split("@ENUMS(", 1)[1]
    out = {}
    for name, body in re.findall(r"(\w+)\s*\{([^}]*)\}", text):
        out[name] = {int(v): k for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", body)}
    return out


def load_pages(folder, errors):
    from midmanstudio.mdix import MdixDatabase

    pages = {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".mdix") or name == "index.mdix":
            continue
        stem = name[:-5]
        with Quiet():
            result = MdixDatabase.try_load(os.path.join(folder, name))
            ok = result.is_success and result.value.entry_count > 0
            page = read(result.value, stem) if ok and result.value.exists(stem) else None
        if page is None:
            errors.append(f"{name}: does not compile, or has no group named {stem}")
        else:
            pages[stem] = page
    return pages


def load_index(folder, errors):
    """The ids in index.mdix, in order: a compound's number is its place in this list, from 1."""
    from midmanstudio.mdix import MdixDatabase

    path = os.path.join(folder, "index.mdix")
    if not os.path.isfile(path):
        errors.append("index.mdix is missing: it gives each compound its number")
        return []
    with Quiet():
        result = MdixDatabase.try_load(path)
        ok = result.is_success and result.value.entry_count > 0 and result.value.exists("index.pages")
        listed = read(result.value, "index.pages") if ok else None
    if not isinstance(listed, list):
        errors.append("index.mdix does not compile, or has no list named index.pages")
        return []
    return listed


def check_index(listed, pages, errors):
    if len(set(listed)) != len(listed):
        errors.append("index.mdix lists a compound twice")
    for stem in sorted(set(pages) - set(listed)):
        errors.append(f"{stem}: has a page and is not in index.mdix, so it has no number")
    for stem in sorted(set(listed) - set(pages)):
        errors.append(f"{stem}: is in index.mdix and has no page")


def in_range(value, lo, hi):
    return lo <= value <= hi


def check_identity(stem, page, enums, errors):
    e = lambda msg: errors.append(f"{stem}: {msg}")
    ident = page.get("identity", {})
    core, props, look = ident.get("core"), ident.get("properties"), ident.get("look")
    if not (core and props and look):
        e("identity needs core, properties and look")
        return
    if core["id"] != stem:
        e(f"its id is {core['id']}, and the file is named {stem}")
    if core["phase"] not in enums["Phase"]:
        e("phase is not in the vocabulary")
    if core["level"] not in range(MAX_LEVEL + 1):
        e(f"level {core['level']} is not from 0 to {MAX_LEVEL}")
    if core["tier"] < 0 or core["price_per_litre"] < 0:
        e("tier and price cannot be negative")
    if not in_range(props["unsafe"], 0, 1):
        e("unsafe is not from 0 to 1")
    if props["melts_c"] >= props["boils_c"]:
        e("it melts at or above where it boils")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", look["color"]):
        e("color is not text like #rrggbb")
    if look["seed"] < 0:
        e("seed cannot be negative")
    if not in_range(look["clarity"], 0, 1) or not in_range(look["strength"], 0, 1):
        e("clarity and strength run from 0 to 1")
    if look["effect"] not in enums["LiquidEffect"]:
        e("effect is not in the vocabulary")


MAX_DAMAGE = 100  # a player has 100 hit points, so no compound can do more than that at a point blank


def check_harm(stem, page, enums, errors):
    """What a compound does to a player: its damage, its status effect, and how a player dies of it."""
    e = lambda msg: errors.append(f"{stem}: {msg}")
    harm = page.get("harm", {}).get("effect")
    if not harm:
        e("it has no harm: its damage, status and death effect")
        return
    if not in_range(harm["damage"], 0, MAX_DAMAGE):
        e(f"damage is not from 0 to {MAX_DAMAGE}")
    if harm["status"] not in enums["Status"]:
        e("status is not in the vocabulary")
        return
    if harm["death"] not in enums["Death"]:
        e("death is not in the vocabulary")
    if not in_range(harm["status_power"], 0, 1):
        e("status_power is not from 0 to 1")
    if harm["status_seconds"] < 0:
        e("status_seconds cannot be negative")
    quiet = enums["Status"][harm["status"]] == "NONE"
    if quiet and (harm["status_power"] != 0 or harm["status_seconds"] != 0):
        e("it has no status, so its power and its seconds must be 0")
    if not quiet and (harm["status_power"] <= 0 or harm["status_seconds"] <= 0):
        e("a status needs a power and a number of seconds above 0")


def check_forms_and_behaviors(stem, page, errors):
    e = lambda msg: errors.append(f"{stem}: {msg}")
    forms = sorted(page.get("forms", []), key=lambda f: f["purity_min"])
    if forms:
        if forms[0]["purity_min"] != 0 or forms[-1]["purity_max"] != 1:
            e("the purity bands must run from 0 to 1")
        for a, b in zip(forms, forms[1:]):
            if a["purity_max"] != b["purity_min"]:
                e(f"bands {a['id']} and {b['id']} leave a gap or overlap")
        if len({f["id"] for f in forms}) != len(forms):
            e("two purity bands have the same id")
        for f in forms:
            if f["purity_min"] >= f["purity_max"] or f["price_factor"] < 0:
                e(f"band {f['id']} is empty or has a negative price factor")
    spans = sorted(page.get("behaviors", []), key=lambda b: b["from_c"])
    for b in spans:
        if b["from_c"] >= b["to_c"]:
            e("a behavior spans no temperatures")
    for a, b in zip(spans, spans[1:]):
        if b["from_c"] < a["to_c"]:
            e("two behaviors overlap in temperature")


def reaction_level(inputs, pages):
    return 1 + max(pages[p["compound"]]["identity"]["core"]["level"] for p in inputs)


def overlaps(a, b):
    return a[0] < b[1] and b[0] < a[1]


def check_reactions(stem, page, pages, enums, errors, seen_ids):
    e = lambda rid, msg: errors.append(f"{stem}.reactions.{rid}: {msg}")
    reactions = page.get("reactions", {})
    for rid, r in reactions.items():
        if rid in seen_ids:
            e(rid, f"the id is already used by {seen_ids[rid]}")
        seen_ids[rid] = stem
        inputs, outputs, fails = r.get("inputs", []), r.get("outputs", []), r.get("failure_outputs", [])
        rule, eff, gate, fail = r.get("rule"), r.get("effect"), r.get("gate"), r.get("failure")
        if not (rule and eff and gate) or len(inputs) < 2:
            e(rid, "needs a rule, an effect, a gate and at least two inputs")
            continue
        if inputs[0]["compound"] != stem:
            e(rid, "is written on the page of its first input, which is not this compound")
        names = [p["compound"] for p in inputs]
        for ref in names + [p["compound"] for p in outputs + fails] + ([rule["catalyst"]] if rule["catalyst"] else []):
            if ref not in pages:
                e(rid, f"names {ref}, which has no page")
        if any(n not in pages for n in names):
            continue
        for p in inputs:
            if p["parts"] <= 0 or not (0 <= p["purity_min"] < p["purity_max"] <= 1):
                e(rid, f"the input {p['compound']} has no amount, or an empty purity band")
        if rule["station"] not in enums["Station"] or rule["wrong_order"] not in enums["Outcome"]:
            e(rid, "the station or the outcome is not in the vocabulary")
        if rule["min_c"] >= rule["max_c"] or not in_range(rule["ratio_tol"], 0, 1):
            e(rid, "the temperatures are empty or the ratio tolerance is not from 0 to 1")
        if rule["catalyst"] and rule["catalyst"] in names:
            e(rid, "the catalyst is also an input")
        if rule["first"] and rule["first"] not in names:
            e(rid, "first is not one of the inputs")
        if rule["first"] and rule["wrong_order"] == 0:
            e(rid, "first is set but the wrong order does nothing")
        if not in_range(eff["unsafe"], 0, 1) or not in_range(eff["reactivity"], 0, 1):
            e(rid, "unsafe and reactivity run from 0 to 1")
        if gate["tier"] < 0 or gate["cost"] < 0:
            e(rid, "the gate cannot be negative")
        if fail and (fail["over_c"] < rule["max_c"] or fail["outcome"] == 0):
            e(rid, "the failure must be above the top of the window, and be something")
        if fails and not fail:
            e(rid, "has failure outputs and no failure")
        if any(g not in GEAR for g in r.get("gear", [])):
            e(rid, "names gear that is not in the list")
        level = reaction_level(inputs, pages)
        if level > MAX_LEVEL:
            e(rid, f"has an input of level {level - 1}, which would make a product of level {level}")
        for p in outputs + fails:
            got = pages[p["compound"]]["identity"]["core"]["level"] if p["compound"] in pages else level
            if got not in (0, level):
                e(rid, f"makes {p['compound']} of level {got}, and the reaction is level {level}")
            if p["parts"] <= 0 or not (p["purity"] == -1 or 0 <= p["purity"] <= 1):
                e(rid, f"the product {p['compound']} has no amount or a bad purity")
    items = list(reactions.items())
    for i, (ra, a) in enumerate(items):
        for rb, b in items[i + 1 :]:
            ia, ib = a.get("inputs", []), b.get("inputs", [])
            if {p["compound"] for p in ia} != {p["compound"] for p in ib} or not a.get("rule") or not b.get("rule"):
                continue
            ra_rule, rb_rule = a["rule"], b["rule"]
            same_station = ra_rule["station"] == rb_rule["station"] or 0 in (ra_rule["station"], rb_rule["station"])
            bands = all(
                overlaps((p["purity_min"], p["purity_max"]), (q["purity_min"], q["purity_max"]))
                for p in ia
                for q in ib
                if p["compound"] == q["compound"]
            )
            if same_station and bands and overlaps((ra_rule["min_c"], ra_rule["max_c"]), (rb_rule["min_c"], rb_rule["max_c"])):
                errors.append(f"{stem}: {ra} and {rb} have the same inputs and can both match")


def check_electrolysis(stem, page, pages, enums, errors):
    e = lambda form, msg: errors.append(f"{stem}.electrolysis.{form}: {msg}")
    level = page["identity"]["core"]["level"]
    bands = {f["id"] for f in page.get("forms", [])}
    for form, run in page.get("electrolysis", {}).items():
        spec, products = run.get("run"), run.get("products", [])
        if not spec or not products:
            e(form, "needs a run and products")
            continue
        if bands and form not in bands or spec["form"] != form:
            e(form, "is not the id of a purity band of this compound, or its run names another")
        if not (0 < spec["power"] <= 1) or spec["outcome"] not in enums["Outcome"]:
            e(form, "power is not above 0 and up to 1, or the outcome is not in the vocabulary")
        if spec["catalyst"] and spec["catalyst"] not in pages:
            e(form, f"the catalyst {spec['catalyst']} has no page")
        if level + 1 > MAX_LEVEL:
            e(form, f"a compound of level {level} cannot be broken down into a level {level + 1}")
        for p in products:
            if p["compound"] not in pages:
                e(form, f"makes {p['compound']}, which has no page")
            elif pages[p["compound"]]["identity"]["core"]["level"] not in (0, level + 1):
                e(form, f"makes {p['compound']}, which is not of level {level + 1}")


def check_together(pages, errors):
    seeds, colors = {}, {}
    for stem, page in pages.items():
        look = page["identity"]["look"]
        if look["seed"] in seeds:
            errors.append(f"{stem}: seed {look['seed']} is also used by {seeds[look['seed']]}")
        seeds[look["seed"]] = stem
        colors[stem] = tuple(int(look["color"][i : i + 2], 16) for i in (1, 3, 5))
    names = sorted(colors)
    for i, a in enumerate(names):
        for b in names[i + 1 :]:
            d = sum((x - y) ** 2 for x, y in zip(colors[a], colors[b])) ** 0.5
            if d < MIN_COLOR_DISTANCE:
                errors.append(f"{a} and {b}: colours only {d:.0f} apart, so the liquids look alike")
    made = set()
    for page in pages.values():
        for r in page.get("reactions", {}).values():
            made |= {p["compound"] for p in r.get("outputs", []) + r.get("failure_outputs", [])}
        for run in page.get("electrolysis", {}).values():
            made |= {p["compound"] for p in run.get("products", [])}
    for stem, page in pages.items():
        if page["identity"]["core"]["level"] > 0 and stem not in made:
            errors.append(f"{stem}: is of level {page['identity']['core']['level']} and nothing makes it")


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "data/chem"
    if not os.path.isdir(folder):
        print(f"no folder {folder}: nothing to check")
        return 0
    errors = []
    pages = load_pages(folder, errors)
    enums = enum_values(folder)
    seen_ids = {}
    for stem, page in pages.items():
        check_identity(stem, page, enums, errors)
    ready = {s: p for s, p in pages.items() if "core" in p.get("identity", {})}
    for stem, page in ready.items():
        check_forms_and_behaviors(stem, page, errors)
        check_harm(stem, page, enums, errors)
        check_reactions(stem, page, ready, enums, errors, seen_ids)
        check_electrolysis(stem, page, ready, enums, errors)
    check_together(ready, errors)
    check_index(load_index(folder, errors), pages, errors)
    for line in errors:
        print("FAIL", line)
    print(f"{len(pages)} pages, {len(errors)} problems")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
