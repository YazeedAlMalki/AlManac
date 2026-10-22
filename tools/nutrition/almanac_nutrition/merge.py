"""merge — one record per real food across every source in a built bundle.

The owner's rule (2026-10-19): keep one record per real item across all
sources. Match on a normalised name plus key fields (food codes, or the
nutrient profile). Same, or unsure: merge. Keep every source's rows and
attribution; where merged values disagree keep both, tagged with the source,
and log it. Never pick a value.

Nothing in the bundle changes. A merge is a map, food_ref -> record_ref: the
record is the member the search shows, and every member keeps its own rows,
names, values and licence. Removing a source still removes only its rows.

How two foods are matched, strongest first:

- code: USDA's own links. A Foundation food and an SR Legacy food with the same
  NDB number; an FNDDS food whose only ingredient is an SR Legacy food.
- same: equal normalised English names, unless their energy differs by more
  than half (APART, against the group's median, never under 25 kcal): "Coconut milk" at 22 kcal (the drink) and at 199 kcal
  (the canned cream) share a name, not a food. Those stay separate records and
  are logged as kept apart.
- unsure: names that differ only by NEUTRAL words ("Spinach, baby, fresh,
  raw" / "Spinach, baby, raw") AND agree on the nutrient profile (PROFILE
  within TOLERANCE), checked against every member already in both groups, so
  one loose pair cannot chain two foods together. Any other differing word —
  a cut, a variety, a brand, "with sugar" — is a different food: measured on
  the shipped bundle, a name-overlap threshold merged sirloin with fillet and
  black beans with cannellini, and profiles alone cannot tell those apart.

Almanac's own foods (`almanac:`, the regional dishes) are never merged.
"""
from __future__ import annotations

import json
import re
import sqlite3
from collections import defaultdict
from pathlib import Path

from .lake import sha256_file
from .sources.almanac import fold

REPO = Path(__file__).resolve().parents[3]
MERGES_JSON = REPO / "Sources/AlmanacCore/Nutrition/Resources/food-merges.json"
MERGE_LOG = REPO / "docs/features/food-merge-log.md"

# Words that say nothing about which food it is.
NEUTRAL = {"fresh", "average", "type", "plain", "standard", "regular", "typical", "generic",
           "commercial", "all", "variety", "mean"}
# Per 100 g. Two values agree when they differ by no more than the larger of
# the absolute and the relative bound. Publishers use different energy
# factors and carbohydrate definitions (dictionary/nutrients.csv), so the
# bounds are loose on purpose: they separate different foods, not two
# analyses of one food.
TOLERANCE = {"energy_kcal": (25.0, 0.12), "protein": (1.5, 0.15), "fat_total": (1.5, 0.15),
             "carbohydrate": (2.0, 0.15)}
PROFILE = tuple(TOLERANCE)
# Owner, 2026-10-22: two foods with one name are still two foods when their
# energy per 100 g differs by more than half of the larger value. Compared
# with each group's median, so one outlying analysis cannot split a group by
# arriving first, and never for less than the energy tolerance's 25 kcal,
# where a half of nearly nothing (two waters) says nothing.
APART = 0.5
# The record a merged group shows: USDA first (its three data types in this
# order), then the others. A fixed rule, not a choice per group.
BASE_ORDER = ("foundation_food.csv", "sr_legacy_food.csv", "survey_fndds_food.csv", "usda",
              "cofid", "ciqual", "afcd")

STOP = {"and", "or", "with", "of", "the", "a", "an", "in", "as", "to", "for", "ns", "nfs",
        "var", "average"}
SPELLING = {"yoghurt": "yogurt", "flavoured": "flavored", "colour": "color", "fibre": "fiber",
            "savoury": "savory"}


def singular(word: str) -> str:
    if len(word) <= 3 or word.endswith(("ss", "us", "is")):
        return word
    if word.endswith("ies"):
        return word[:-3] + "y"
    if re.search(r"(ss|sh|ch|x|o)es$", word):
        return word[:-2]
    return word[:-1] if word.endswith("s") else word


def tokens(name: str) -> frozenset[str]:
    text = re.sub(r"\bnot (?:further )?specified\b", " ", fold(name).replace("&", " and "))
    words = re.sub(r"[^a-z0-9]+", " ", text).split()
    return frozenset(singular(SPELLING.get(w, w)) for w in words if w not in STOP)


def segments(name: str) -> frozenset[frozenset[str]]:
    """The name's comma-separated parts, each normalised. Equal parts in any order
    is the same name; the same words grouped differently ("lean, weighed with fat"
    / "lean and fat, weighed") may not be."""
    return frozenset(t for part in name.split(",") if (t := tokens(part)))


def similarity(a: frozenset[str], b: frozenset[str]) -> float:
    return len(a & b) / len(a | b) if a | b else 0.0


def agree(nutrient: str, a: float, b: float) -> bool:
    absolute, relative = TOLERANCE[nutrient]
    return abs(a - b) <= max(absolute, relative * max(a, b))


def median_energy(foods: list[dict]) -> float | None:
    values = sorted(f["profile"]["energy_kcal"] for f in foods if "energy_kcal" in f["profile"])
    if not values:
        return None
    mid = len(values) // 2
    return values[mid] if len(values) % 2 else (values[mid - 1] + values[mid]) / 2


def energy_apart(x: float | None, y: float | None) -> bool:
    if x is None or y is None:
        return False
    return abs(x - y) > max(TOLERANCE["energy_kcal"][0], APART * max(x, y))


def profiles_agree(a: dict, b: dict) -> bool:
    """Every profile nutrient both foods state agrees, and they share at least three."""
    shared = [n for n in PROFILE if n in a and n in b]
    return len(shared) >= 3 and all(agree(n, a[n], b[n]) for n in shared)


# --- Reading the bundle ----------------------------------------------------------


def carbohydrate(values: dict[str, float]) -> float | None:
    """Total carbohydrate for comparison only: by difference, else available plus
    fibre (monosaccharide equivalents divided by 1.05 first). Never stored."""
    if "carbohydrate_by_difference" in values:
        return values["carbohydrate_by_difference"]
    fibre = values.get("fibre_total_dietary")
    if fibre is None:
        return None
    if "carbohydrate_available" in values:
        return values["carbohydrate_available"] + fibre
    if "carbohydrate_available_monosaccharide" in values:
        return values["carbohydrate_available_monosaccharide"] / 1.05 + fibre
    return None


def read_foods(bundle: Path) -> list[dict]:
    db = sqlite3.connect(f"file:{bundle}?mode=ro", uri=True)
    foods = {ref: {"food_ref": ref, "namespace": ns, "source_record": record, "values": {}}
             for ref, ns, record in db.execute(
                 "SELECT food_ref, namespace, source_record FROM nutrition_food WHERE namespace <> 'almanac'")}
    for ref, name in db.execute("SELECT food_ref, name FROM nutrition_food_name "
                                "WHERE language = 'en'"):
        if ref in foods:
            foods[ref]["name"] = name
    for ref, nutrient, amount in db.execute(
            "SELECT food_ref, nutrient_id, amount FROM nutrition_value "
            "WHERE basis = 'per_100g' AND amount IS NOT NULL"):
        if ref in foods:
            foods[ref]["values"][nutrient] = amount
    db.close()
    for food in foods.values():
        published = food.pop("values")
        profile = {n: published[n] for n in ("energy_kcal", "protein", "fat_total") if n in published}
        if (carb := carbohydrate(published)) is not None:
            profile["carbohydrate"] = round(carb, 3)
        food["profile"] = profile
        food.setdefault("name", food["food_ref"])
    return sorted(foods.values(), key=lambda f: f["food_ref"])


CODE = re.compile(r"(foundation_food|sr_legacy_food|survey_fndds_food)\.csv (?:NDB_number|food_code)=(\S+)")
SOLE = re.compile(r"sole input fdc_id=(\S*) sr_code=(\S*)")


def code_links(foods: list[dict]) -> list[tuple[str, str]]:
    """USDA's own same-food links, read from source_record (usda.py writes them)."""
    sr_by_ndb, sr_refs = {}, set()
    foundation, fndds = [], []
    for f in foods:
        match = CODE.search(f["source_record"])
        if not match:
            continue
        kind, code = match.groups()
        if kind == "sr_legacy_food":
            sr_by_ndb[code.lstrip("0")] = f["food_ref"]
            sr_refs.add(f["food_ref"])
        elif kind == "foundation_food":
            foundation.append((f["food_ref"], code.lstrip("0")))
        elif sole := SOLE.search(f["source_record"]):
            fndds.append((f["food_ref"], *sole.groups()))
    links = [(ref, sr_by_ndb[ndb]) for ref, ndb in foundation if ndb in sr_by_ndb]
    for ref, input_fdc, sr_code in fndds:
        target = f"usda:{input_fdc}" if f"usda:{input_fdc}" in sr_refs else sr_by_ndb.get(sr_code.lstrip("0"))
        if target:
            links.append((ref, target))
    return links


# --- Grouping ----------------------------------------------------------------------


def group(foods: list[dict]) -> tuple[list[list[dict]], list[dict], list[dict]]:
    by_ref = {f["food_ref"]: f for f in foods}
    toks = {f["food_ref"]: tokens(f["name"]) for f in foods}
    parent = {ref: ref for ref in by_ref}
    members = {ref: [ref] for ref in by_ref}

    def find(ref: str) -> str:
        while parent[ref] != ref:
            parent[ref] = parent[parent[ref]]
            ref = parent[ref]
        return ref

    matches, apart = [], []

    def union(a: str, b: str, kind: str, score: float, check_profiles: bool) -> bool:
        ra, rb = find(a), find(b)
        if ra == rb:
            return True
        if check_profiles and not all(profiles_agree(by_ref[x]["profile"], by_ref[y]["profile"])
                                      for x in members[ra] for y in members[rb]):
            return False
        if kind == "same" and energy_apart(median_energy([by_ref[x] for x in members[ra]]),
                                           median_energy([by_ref[y] for y in members[rb]])):
            return False
        parent[rb] = ra
        members[ra] += members.pop(rb)
        matches.append({"a": a, "b": b, "kind": kind, "score": round(score, 2)})
        return True

    for a, b in code_links(foods):
        if a in by_ref and b in by_ref:
            union(a, b, "code", 1.0, False)

    by_name = defaultdict(list)
    for ref in sorted(by_ref):
        by_name[segments(by_ref[ref]["name"])].append(ref)
    # Each food joins the first same-name group whose energy it fits; one that
    # fits none starts its own, so a drink and a cream can each gather their own.
    for refs in by_name.values():
        for i, ref in enumerate(refs):
            roots = list(dict.fromkeys(find(r) for r in refs[:i]))
            if roots and not any(union(root, ref, "same", 1.0, False) for root in roots):
                apart.append({"food_ref": ref, "others": [r for r in refs[:i]]})

    # Unsure: blocked on the first word, which every source here makes the food's head noun.
    blocks = defaultdict(list)
    for f in foods:
        head = re.sub(r"[^a-z0-9]+", " ", fold(f["name"])).split()
        if head:
            blocks[singular(head[0])].append(f["food_ref"])
    pairs = []
    for refs in blocks.values():
        for i, a in enumerate(refs):
            for b in refs[i + 1:]:
                if not toks[a] & toks[b] or not (toks[a] ^ toks[b]) <= NEUTRAL:
                    continue
                if profiles_agree(by_ref[a]["profile"], by_ref[b]["profile"]):
                    pairs.append((similarity(toks[a], toks[b]), a, b))
    for s, a, b in sorted(pairs, key=lambda p: (-p[0], p[1], p[2])):
        union(a, b, "unsure", s, True)

    groups = [[by_ref[r] for r in sorted(refs)] for refs in members.values() if len(refs) > 1]
    return sorted(groups, key=lambda g: g[0]["food_ref"]), matches, apart


def base_of(group: list[dict]) -> dict:
    def rank(f: dict) -> tuple:
        match = CODE.search(f["source_record"])
        key = f"{match.group(1)}.csv" if match else f["namespace"]
        return (BASE_ORDER.index(key) if key in BASE_ORDER else len(BASE_ORDER), f["food_ref"])
    return min(group, key=rank)


def conflicts(group: list[dict]) -> list[dict]:
    out = []
    for nutrient in PROFILE:
        stated = [(f["food_ref"], f["profile"][nutrient]) for f in group if nutrient in f["profile"]]
        if any(not agree(nutrient, a, b) for i, (_, a) in enumerate(stated) for _, b in stated[i + 1:]):
            out.append({"nutrient": nutrient, "values": [{"food_ref": r, "value": v} for r, v in stated]})
    return out


# --- Writing -------------------------------------------------------------------------


def run(bundle: Path, merges_json: Path = MERGES_JSON, merge_log: Path = MERGE_LOG) -> dict:
    foods = read_foods(bundle)
    groups, matches, apart = group(foods)
    records = []
    for g in groups:
        base = base_of(g)
        records.append({
            "record": base["food_ref"],
            "members": [{"food_ref": f["food_ref"], "name": f["name"], "values": f["profile"]} for f in g],
            "conflicts": conflicts(g),
        })
    by_member = defaultdict(list)
    for m in matches:
        by_member[m["a"]].append(m)
        by_member[m["b"]].append(m)
    counts = {
        "foods read (almanac: excluded)": len(foods),
        "records with more than one source row": len(records),
        "foods merged into another food's record": sum(len(r["members"]) - 1 for r in records),
        "matches: code": sum(m["kind"] == "code" for m in matches),
        "matches: same name": sum(m["kind"] == "same" for m in matches),
        "matches: unsure": sum(m["kind"] == "unsure" for m in matches),
        "records with a conflict": sum(bool(r["conflicts"]) for r in records),
        "same-name foods kept apart (energy differs by more than half)": len(apart),
    }
    merges_json.write_text(json.dumps({
        "bundleSHA256": sha256_file(bundle),
        "merges": [{"foodRef": m["food_ref"], "recordRef": r["record"],
                    "kind": next((x["kind"] for x in by_member[m["food_ref"]]), "same"),
                    "score": max((x["score"] for x in by_member[m["food_ref"]]), default=1.0)}
                   for r in records for m in r["members"]],
    }, indent=1, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    by_ref = {f["food_ref"]: f for f in foods}
    write_log(merge_log, bundle, records, by_member, counts, apart, by_ref)
    return counts


def _fmt(v: float) -> str:
    return f"{v:g}"


def write_log(path: Path, bundle: Path, records, by_member, counts, apart=(), by_ref=None) -> None:
    lines = [
        "# Food merge log",
        "",
        "Written by `python3 -m almanac_nutrition merge`; do not edit by hand. "
        f"Bundle: `{bundle.name}` sha256 `{sha256_file(bundle)[:12]}`.",
        "",
        "Rule (owner, 2026-10-19): one record per real food across every source. Foods are matched "
        "on USDA's own codes (**code**: a Foundation and an SR Legacy food with one NDB number, an "
        "FNDDS food whose only ingredient is an SR Legacy food), on equal normalised English names "
        "(**same**, unless their energy per 100 g differs by more than half: owner, 2026-10-22), or on names that differ only by words naming nothing about the food ("
        + ", ".join(f"*{w}*" for w in sorted(NEUTRAL)) + ") and whose nutrient profiles agree "
        "(**unsure**; energy within 25 kcal or 12 %, protein, fat and carbohydrate within 1.5–2 g "
        "or 15 %, per 100 g). Every member keeps its own rows and licence; the search shows the "
        "record (USDA first, then CoFID, CIQUAL, AFCD). Almanac's own dishes are never merged.",
        "",
        "| | Count |", "|---|---:|",
        *[f"| {k} | {v} |" for k, v in counts.items()],
        "",
        "## Conflicts",
        "",
        "Members whose values differ by more than the tolerance. Both values are kept, each on its "
        "own source's row; nothing is picked. Carbohydrate is compared as a total (by difference, "
        "or available plus fibre) and is not a stored value.",
        "",
        "| Record | Nutrient | Values per 100 g |", "|---|---|---|",
    ]
    for r in records:
        name = next(m["name"] for m in r["members"] if m["food_ref"] == r["record"])
        for c in r["conflicts"]:
            vals = "; ".join(f"{_fmt(v['value'])} (`{v['food_ref']}`)" for v in c["values"])
            lines.append(f"| `{r['record']}` {name} | {c['nutrient']} | {vals} |")
    lines += ["", "## Kept apart", "",
              "Foods sharing a name whose energy differs by more than half of the larger value. Each "
              "stays its own record.", "",
              "| Food | kcal per 100 g | Same name as |", "|---|---:|---|"]
    for a in apart:
        food = by_ref[a["food_ref"]]
        others = "<br>".join(f"`{r}` {_fmt(by_ref[r]['profile'].get('energy_kcal', float('nan')))} kcal"
                             for r in a["others"])
        lines.append(f"| `{a['food_ref']}` {food['name']} | "
                     f"{_fmt(food['profile'].get('energy_kcal', float('nan')))} | {others} |")
    lines += ["", "## Merges", "", "| Record | Members | Matches |", "|---|---|---|"]
    for r in records:
        refs = [m["food_ref"] for m in r["members"]]
        members = "<br>".join(f"`{m['food_ref']}` {m['name']}" for m in r["members"])
        seen = {id(x): x for ref in refs for x in by_member[ref]}
        how = "<br>".join(f"{x['kind']} {x['score']}: `{x['a']}` ~ `{x['b']}`" for x in seen.values())
        lines.append(f"| `{r['record']}` | {members} | {how} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
