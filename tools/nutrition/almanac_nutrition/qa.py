"""Quality assurance over what the pipeline wrote — the data:validate-data pass.

Independent of the source modules on purpose: every mapped raw cell is re-read
here with its own reader and compared with what canonicalise wrote, so a
parser bug cannot pass its own test. `python3 -m almanac_nutrition qa` writes
processed/qa/report.md and report.json, and exits non-zero if a hard check fails.

Hard checks — the bundle must not ship if any fails:
  fidelity   every mapped raw cell has exactly one canonical row with the same
             number, bound or token, and no canonical row lacks a raw cell
  tokens     no row whose cell is a token carries an amount; no 0 without a raw 0
  licence    every union and bundle row is shippable and agrees with sources.csv
Soft checks — reported for a person to review:
  plausibility  protein + fat + total carbohydrate + alcohol above 105 g per 100 g
  energy        Almanac's general Atwater figure against each publisher's own
"""
from __future__ import annotations

import csv
import math
import sqlite3
import statistics
from collections import Counter, defaultdict
from contextlib import closing

import openpyxl
from lxml import etree

from .canonical_io import read_canonical
from .dictionary import Dictionary, Mapping
from .lake import Lake, staged_directory, utc_now, write_json

KJ_PER_KCAL = 4.184
# What each publisher's own documentation says its tokens mean. Deliberately not read
# from dictionary/value_tokens.csv, so that a wrong mapping there is caught here.
TOKENS = {("cofid", "Tr"): "trace", ("cofid", "N"): "not_analysed",
          ("ciqual", "traces"): "trace", ("ciqual", "-"): "not_analysed"}
NO_AMOUNT = {"trace", "not_analysed"}
EXAMPLES = 12
Cells = dict[tuple[str, str, str], list[tuple[int, str, Mapping]]]


def _text(value: object) -> str:
    if value is None:
        return ""
    return repr(value) if isinstance(value, float) else str(value)


def _mapped(dictionary: Dictionary, source: str) -> dict[str, Mapping]:
    return {m.source_nutrient_id: m for m in dictionary.mappings if m.source == source}


def _number(text: str) -> float | None:
    try:
        number = float(text.replace(",", ".") if text.count(",") == 1 and "." not in text else text)
    except ValueError:
        return None
    return number if math.isfinite(number) else None


# --- Independent readers of the raw files ------------------------------------------------

def raw_usda(lake: Lake, dictionary: Dictionary) -> tuple[set[str], Cells]:
    base = lake.source_dir("usda") / "FoodData_Central_csv_2026-04-30"
    with open(base / "foundation_food.csv", newline="", encoding="utf-8-sig") as f:
        listed = {r["fdc_id"] for r in csv.DictReader(f)}
    with open(base / "food.csv", newline="", encoding="utf-8-sig") as f:
        foods = {r["fdc_id"] for r in csv.DictReader(f)
                 if r["data_type"] == "foundation_food" and r["fdc_id"] in listed}
    mapped = _mapped(dictionary, "usda")
    cells: Cells = defaultdict(list)
    with open(base / "food_nutrient.csv", newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)
        fdc, nutrient, amount = header.index("fdc_id"), header.index("nutrient_id"), header.index("amount")
        for row in reader:
            m = mapped.get(row[nutrient])
            if m and row[fdc] in foods and row[amount].strip():
                cells[(f"usda:{row[fdc]}", m.nutrient_id, "per_100g")].append(
                    (m.priority, row[amount].strip(), m))
    return {f"usda:{f}" for f in foods}, cells


def raw_ciqual(lake: Lake, dictionary: Dictionary) -> tuple[set[str], Cells]:
    base = lake.source_dir("ciqual")
    root = etree.parse(str(base / "alim_2025_11_03.xml")).getroot()
    foods = {f"ciqual:{(e.findtext('alim_code') or '').strip()}" for e in root}
    mapped = _mapped(dictionary, "ciqual")
    cells: Cells = defaultdict(list)
    for _, e in etree.iterparse(str(base / "compo_2025_11_03.xml"), tag="COMPO"):
        m = mapped.get((e.findtext("const_code") or "").strip())
        text = (e.findtext("teneur") or "").strip()
        if m and text:
            cells[(f"ciqual:{(e.findtext('alim_code') or '').strip()}", m.nutrient_id, "per_100g")].append(
                (m.priority, text, m))
        e.clear()
    return foods, cells


def _sheet(path, title: str) -> list[list[object]]:
    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        return [list(row) for row in book[title].iter_rows(values_only=True)]
    finally:
        book.close()


def _at(row: list[object], index: int) -> str:
    return _text(row[index] if index < len(row) else None).strip()


def raw_cofid(lake: Lake, dictionary: Dictionary) -> tuple[set[str], Cells]:
    rows = _sheet(lake.source_dir("cofid") / "McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx",
                  "1.3 Proximates")
    headings, codes = rows[0], rows[1]
    column = {_text(c).strip(): i for i, c in enumerate(codes) if c}
    code_at, group_at = headings.index("Food Code"), headings.index("Group")
    body = [(n, row) for n, row in enumerate(rows[3:], start=4) if _at(row, code_at)]
    repeats = Counter(_at(row, code_at) for _, row in body)
    mapped = _mapped(dictionary, "cofid")
    foods: set[str] = set()
    cells: Cells = defaultdict(list)
    for n, row in body:
        code = _at(row, code_at)
        ref = f"cofid:{code}" if repeats[code] == 1 else f"cofid:{code}@row{n}"
        foods.add(ref)
        # CoFID user guide p.7: alcoholic beverages (group Q) are per 100 ml.
        basis = "per_100ml" if _at(row, group_at).startswith("Q") else "per_100g"
        for source_id, m in mapped.items():
            if text := _at(row, column[source_id]):
                cells[(ref, m.nutrient_id, basis)].append((m.priority, text, m))
    return foods, cells


def raw_afcd(lake: Lake, dictionary: Dictionary) -> tuple[set[str], Cells]:
    path = lake.source_dir("ausnut") / "AFCD Release 3 - Nutrient profiles.xlsx"
    mapped = _mapped(dictionary, "afcd")
    foods: set[str] = set()
    cells: Cells = defaultdict(list)
    for title, basis in (("All solids & liquids per 100 g", "per_100g"), ("Liquids only per 100 mL", "per_100ml")):
        rows = _sheet(path, title)
        column = {" ".join(_text(h).split()): i for i, h in enumerate(rows[2])}
        for row in rows[3:]:
            if not (key := _at(row, column["Public Food Key"])):
                continue
            if basis == "per_100g":
                foods.add(f"afcd:{key}")
            for source_id, m in mapped.items():
                if text := _at(row, column[source_id]):
                    cells[(f"afcd:{key}", m.nutrient_id, basis)].append((m.priority, text, m))
    return foods, cells


READERS = {"usda": raw_usda, "ciqual": raw_ciqual, "cofid": raw_cofid, "afcd": raw_afcd}


# --- Portions: independent re-read of USDA food_portion and CoFID "1.2 Factors" ------------

def raw_usda_portions(lake: Lake) -> dict[tuple[str, str, str], tuple[str, str]]:
    """(food_ref, 'household_measure', source_record) -> (gram_weight text, amount text)."""
    base = lake.source_dir("usda") / "FoodData_Central_csv_2026-04-30"
    with open(base / "foundation_food.csv", newline="", encoding="utf-8-sig") as f:
        listed = {r["fdc_id"] for r in csv.DictReader(f)}
    with open(base / "food.csv", newline="", encoding="utf-8-sig") as f:
        foods = {r["fdc_id"] for r in csv.DictReader(f)
                 if r["data_type"] == "foundation_food" and r["fdc_id"] in listed}
    cells: dict[tuple[str, str, str], tuple[str, str]] = {}
    with open(base / "food_portion.csv", newline="", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if r["fdc_id"] not in foods:
                continue
            key = (f"usda:{r['fdc_id']}", "household_measure", f"food_portion.csv id={r['id']}")
            cells[key] = (r["gram_weight"].strip(), r["amount"].strip())
    return cells


def raw_cofid_factors(lake: Lake) -> dict[tuple[str, str, str], str]:
    """(food_ref, kind, source_record) -> raw cell text, for Edible proportion and Specific gravity."""
    rows = _sheet(lake.source_dir("cofid") / "McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx",
                  "1.2 Factors")
    headings = rows[0]
    code_at = headings.index("Food Code")
    ep_at = headings.index("Edible proportion")
    sg_at = headings.index("Specific gravity")
    body = [(n, row) for n, row in enumerate(rows[3:], start=4) if _at(row, code_at)]
    repeats = Counter(_at(row, code_at) for _, row in body)
    cells: dict[tuple[str, str, str], str] = {}
    for n, row in body:
        code = _at(row, code_at)
        ref = f"cofid:{code}" if repeats[code] == 1 else f"cofid:{code}@row{n}"
        if text := _at(row, ep_at):
            cells[(ref, "edible_proportion", f"1.2 Factors!row {n}")] = text
        if text := _at(row, sg_at):
            cells[(ref, "specific_gravity", f"1.2 Factors!row {n}")] = text
    return cells


def portion_fidelity(lake: Lake, portions) -> dict:
    """Re-reads USDA food_portion and CoFID Factors independently and compares with canonical."""
    problems: list[str] = []
    by_key = {(p.food_ref, p.kind, p.source_record): p for p in portions}
    kinds: Counter[str] = Counter()

    for key, (gram_text, amount_text) in raw_usda_portions(lake).items():
        kinds["household_measure"] += 1
        where = "/".join(key)
        p = by_key.get(key)
        if p is None:
            problems.append(f"{where}: raw portion has no canonical row")
            continue
        if p.source_value != gram_text:
            problems.append(f"{where}: canonical source_value {p.source_value!r}, raw {gram_text!r}")
        wanted_value, wanted_amount = _number(gram_text), _number(amount_text)
        if p.value is None or wanted_value is None or not math.isclose(p.value, wanted_value, rel_tol=1e-9):
            problems.append(f"{where}: value {p.value!r}, raw gives {wanted_value!r}")
        if p.amount is None or wanted_amount is None or not math.isclose(p.amount, wanted_amount, rel_tol=1e-9):
            problems.append(f"{where}: amount {p.amount!r}, raw gives {wanted_amount!r}")

    for key, text in raw_cofid_factors(lake).items():
        kinds[key[1]] += 1
        where = "/".join(key)
        p = by_key.get(key)
        if p is None:
            problems.append(f"{where}: raw portion has no canonical row")
            continue
        if p.source_value != text:
            problems.append(f"{where}: canonical source_value {p.source_value!r}, raw {text!r}")
        if text == "N":
            if p.value is not None or p.qualifier != "not_analysed":
                problems.append(f"{where}: raw token 'N' became {p.qualifier} {p.value!r}")
            continue
        wanted = _number(text)
        if wanted is None:
            problems.append(f"{where}: raw cell {text!r} is unreadable but became {p.qualifier}")
            continue
        if p.value is None or not math.isclose(p.value, wanted, rel_tol=1e-9):
            problems.append(f"{where}: value {p.value!r}, raw gives {wanted!r}")

    raw_keys = set(raw_usda_portions(lake)) | set(raw_cofid_factors(lake))
    for key in sorted(set(by_key) - raw_keys):
        problems.append(f"{'/'.join(key)}: canonical portion with no raw cell")

    return {"raw_cells": sum(kinds.values()), "raw_cells_by_kind": dict(sorted(kinds.items())),
            "canonical_portions": len(portions), "problems": len(problems), "examples": problems[:EXAMPLES]}


# --- Hard checks --------------------------------------------------------------------------

def expectation(source: str, text: str) -> tuple[str, float | None]:
    """What the publisher's own documentation says a cell is: a kind and, if any, a number."""
    if (source, text) in TOKENS:
        return TOKENS[(source, text)], None
    if source == "ciqual" and text.startswith("<"):
        return "below_loq", _number(text[1:].strip())
    number = _number(text)
    if number is None:
        return "unreadable", None
    if number < 0:
        return "negative", number
    return ("zero" if number == 0 else "number"), number


def fidelity(source: str, raw_foods: set[str], cells: Cells, foods, values, manifest) -> dict:
    problems: list[str] = []
    canonical_foods = {f.food_ref for f in foods}
    for ref in sorted(raw_foods - canonical_foods):
        problems.append(f"food {ref} is in the raw file but not canonical")
    for ref in sorted(canonical_foods - raw_foods):
        problems.append(f"food {ref} is canonical but not in the raw file")
    by_key = {(v.food_ref, v.nutrient_id, v.basis): v for v in values}
    rejected = {(r["food_ref"], r["source_nutrient_id"], r.get("basis", "per_100g"))
                for r in manifest["notes"].get("rejected_values", [])}
    kinds: Counter[str] = Counter()
    for key, found in sorted(cells.items()):
        found.sort(key=lambda c: c[0])
        # The pipeline's priority rule restated: the lowest priority that is not "no number".
        _, text, m = next((c for c in found if TOKENS.get((source, c[1])) != "not_analysed"), found[0])
        kind, number = expectation(source, text)
        kinds[kind] += 1
        where, v = "/".join(key), by_key.get(key)
        if kind == "negative":
            if v is not None:
                problems.append(f"{where}: negative raw cell {text!r} became a row")
            elif (key[0], m.source_nutrient_id, key[2]) not in rejected:
                problems.append(f"{where}: negative raw cell {text!r} is not recorded as rejected")
            continue
        if v is None:
            problems.append(f"{where}: raw cell {text!r} has no canonical row")
            continue
        if (v.source_value, v.source_nutrient_id) != (text, m.source_nutrient_id):
            problems.append(f"{where}: canonical cell {v.source_value!r} ({v.source_nutrient_id}), "
                            f"raw {text!r} ({m.source_nutrient_id})")
        if kind in NO_AMOUNT:
            if v.amount is not None or v.qualifier != kind:
                problems.append(f"{where}: raw token {text!r} became {v.qualifier} {v.amount!r}")
            continue
        if kind == "unreadable":
            problems.append(f"{where}: raw cell {text!r} is unreadable but became {v.qualifier}")
            continue
        wanted = number / KJ_PER_KCAL if m.unit_conversion == "kj_to_kcal" else number
        if v.amount is None or not math.isclose(v.amount, wanted, rel_tol=1e-9, abs_tol=1e-12):
            problems.append(f"{where}: amount {v.amount!r}, raw {text!r} gives {wanted!r}")
        if kind == "zero" and v.qualifier != "zero_reported":
            problems.append(f"{where}: raw zero became {v.qualifier}")
        if kind == "below_loq" and v.qualifier != "below_loq":
            problems.append(f"{where}: raw bound {text!r} became {v.qualifier}")
        if kind == "number" and v.qualifier in NO_AMOUNT | {"zero_reported", "below_loq"}:
            problems.append(f"{where}: raw number {text!r} became {v.qualifier}")
    for key in sorted(set(by_key) - set(cells)):
        problems.append(f"{'/'.join(key)}: canonical row with no raw cell")
    return {"raw_cells": sum(kinds.values()), "raw_cells_by_kind": dict(sorted(kinds.items())),
            "canonical_values": len(values), "problems": len(problems), "examples": problems[:EXAMPLES]}


def token_invariants(values) -> dict:
    tokens = {token for _, token in TOKENS}
    carried = [v for v in values if v.source_value.strip() in tokens and v.amount is not None]
    zero = [v for v in values if v.amount == 0 and _number(v.source_value.strip()) != 0]
    by_token = Counter(v.source_value.strip() for v in values if v.source_value.strip() in tokens)
    examples = [f"{v.food_ref}/{v.nutrient_id}: {v.source_value!r} -> {v.amount!r}" for v in carried + zero]
    return {"token_rows": dict(sorted(by_token.items())), "tokens_with_amounts": len(carried),
            "zeros_without_a_raw_zero": len(zero), "problems": len(carried) + len(zero),
            "examples": examples[:EXAMPLES]}


def licence(dictionary: Dictionary, foods, values, bundle_path) -> dict:
    problems: list[str] = []
    shippable = dictionary.shippable_groups
    group_of_food = {}
    for f in foods:
        group_of_food[f.food_ref] = f.licence_group
        if f.licence_group != dictionary.group_of(f.namespace) or f.licence_group not in shippable:
            problems.append(f"food {f.food_ref}: group {f.licence_group}")
    problems += [f"value {v.food_ref}/{v.nutrient_id}: group {v.licence_group}"
                 for v in values if v.licence_group != group_of_food.get(v.food_ref)]
    in_bundle: dict[str, list[str]] = {}
    with closing(sqlite3.connect(f"file:{bundle_path}?mode=ro", uri=True)) as con:
        for table in ("nutrition_source", "nutrition_food", "nutrition_value"):
            in_bundle[table] = sorted(g for (g,) in con.execute(f"SELECT DISTINCT licence_group FROM {table}"))
            problems += [f"bundle {table}: group {g}" for g in in_bundle[table] if g not in shippable]
        problems += [f"bundle nutrition_source {ns}: no attribution"
                     for ns, text in con.execute("SELECT namespace, attribution FROM nutrition_source")
                     if not text.strip()]
    return {"groups_in_bundle": in_bundle, "problems": len(problems), "examples": problems[:EXAMPLES]}


# --- Soft checks --------------------------------------------------------------------------

def _grams(v) -> float | None:
    """A value as it enters the general-Atwater sum (AlmanacCore's rule, restated here)."""
    if v is None or v.qualifier == "not_analysed":
        return None
    return 0.0 if v.qualifier in ("trace", "below_loq") else v.amount


def general_atwater(values: dict) -> tuple[float, float] | None:
    """(kcal, grams of protein + fat + total carbohydrate + alcohol), or None."""
    protein, fat = _grams(values.get("protein")), _grams(values.get("fat_total"))
    carbohydrate = _grams(values.get("carbohydrate_by_difference"))
    if carbohydrate is None:
        fibre = _grams(values.get("fibre_total_dietary"))
        available = _grams(values.get("carbohydrate_available"))
        if available is None:
            available = _grams(values.get("carbohydrate_available_monosaccharide"))
        carbohydrate = None if fibre is None or available is None else available + fibre
    if protein is None or fat is None or carbohydrate is None:
        return None
    alcohol = _grams(values.get("alcohol")) or 0.0
    return (4 * protein + 4 * carbohydrate + 9 * fat + 7 * alcohol,
            protein + fat + carbohydrate + alcohol)


def energy_and_plausibility(names, values) -> tuple[dict, dict]:
    primary = {n.food_ref: n.name for n in names if n.is_primary}
    by_pair: dict[tuple[str, str], dict] = defaultdict(dict)
    for v in values:
        by_pair[(v.food_ref, v.basis)][v.nutrient_id] = v
    sources: dict[str, dict] = defaultdict(lambda: {"pairs": 0, "general_atwater": 0, "publisher_only": 0,
                                                    "neither": 0, "ratios": [], "outliers": []})
    usda_published: list[float] = []
    implausible: list[dict] = []
    for (ref, basis), found in sorted(by_pair.items()):
        s = sources[ref.split(":", 1)[0]]
        s["pairs"] += 1
        estimate = general_atwater(found)
        published = found.get("energy_kcal")
        published_kcal = (published.amount if published is not None and published.qualifier != "below_loq"
                          else None)
        if estimate is None:
            s["publisher_only" if published_kcal is not None else "neither"] += 1
            continue
        kcal, grams = estimate
        s["general_atwater"] += 1
        if basis == "per_100g" and grams > 105:
            implausible.append({"food_ref": ref, "name": primary.get(ref, ""), "grams": round(grams, 2)})
        if published_kcal:
            s["ratios"].append(kcal / published_kcal)
            if abs(kcal - published_kcal) > max(30.0, 0.3 * published_kcal):
                s["outliers"].append({"food_ref": ref, "basis": basis, "name": primary.get(ref, ""),
                                      "general_atwater": round(kcal, 1), "published": round(published_kcal, 1)})
        if (usda := found.get("energy_general_atwater_kcal")) is not None and usda.amount is not None:
            usda_published.append(abs(kcal - usda.amount))
    energy = {}
    for ns, s in sorted(sources.items()):
        ratios = sorted(s.pop("ratios"))
        cuts = statistics.quantiles(ratios, n=20) if len(ratios) >= 20 else []
        s["ratio_general_atwater_to_published"] = (
            {"n": len(ratios), "p5": round(cuts[0], 3), "median": round(statistics.median(ratios), 3),
             "p95": round(cuts[-1], 3)} if cuts else {"n": len(ratios)})
        s["outlier_count"] = len(s["outliers"])
        s["outliers"] = sorted(s["outliers"], key=lambda o: -abs(o["general_atwater"] - o["published"]))[:EXAMPLES]
        energy[ns] = s
    if usda_published:
        energy["usda_general_atwater_agreement"] = {
            "n": len(usda_published), "median_abs_kcal": round(statistics.median(usda_published), 3),
            "over_1_kcal": sum(1 for d in usda_published if d > 1)}
    return energy, {"over_105_g": len(implausible),
                    "examples": sorted(implausible, key=lambda i: -i["grams"])[:EXAMPLES]}


# --- Report -------------------------------------------------------------------------------

def run(lake: Lake, dictionary: Dictionary) -> dict:
    union_foods, union_names, union_values, union_portions, _ = read_canonical(lake.union)
    report: dict = {"generated_at": utc_now(), "dictionary_sha256": dictionary.sha256, "sources": {}}
    for ns in sorted(p.name for p in lake.canonical_root.iterdir() if p.is_dir() and not p.name.startswith(".")):
        foods, _, values, _, manifest = read_canonical(lake.canonical(ns))
        entry = {"foods": len(foods), "values": len(values),
                 "qualifiers": dict(sorted(Counter(v.qualifier for v in values).items()))}
        if ns in READERS:
            entry["fidelity"] = fidelity(ns, *READERS[ns](lake, dictionary), foods, values, manifest)
        else:
            entry["fidelity"] = {"problems": 0, "note": "no raw file: nothing to re-read"}
        report["sources"][ns] = entry
    report["tokens"] = token_invariants(union_values)
    report["licence"] = licence(dictionary, union_foods, union_values, lake.bundle)
    report["energy"], report["plausibility"] = energy_and_plausibility(union_names, union_values)
    report["portion_fidelity"] = portion_fidelity(lake, union_portions)
    report["passed"] = (all(e["fidelity"]["problems"] == 0 for e in report["sources"].values())
                        and report["tokens"]["problems"] == 0 and report["licence"]["problems"] == 0
                        and report["portion_fidelity"]["problems"] == 0)
    with staged_directory(lake.root / "processed" / "qa") as scratch:
        write_json(scratch / "report.json", report)
        (scratch / "report.md").write_text(render(report), encoding="utf-8")
    return report


def render(report: dict) -> str:
    verdict = "PASSED" if report["passed"] else "FAILED"
    lines = [f"# Nutrition QA — {verdict}", "", f"Generated {report['generated_at']}; dictionary "
             f"`{report['dictionary_sha256'][:12]}`. Hard checks gate the bundle; soft checks are for review.",
             "", "## Hard checks", "",
             "| Source | Foods | Values | Raw cells re-read | Fidelity problems |", "|---|---:|---:|---:|---:|"]
    for ns, e in report["sources"].items():
        lines.append(f"| {ns} | {e['foods']:,} | {e['values']:,} | {e['fidelity'].get('raw_cells', 0):,} | "
                     f"{e['fidelity']['problems']} |")
    t, lic, pf = report["tokens"], report["licence"], report["portion_fidelity"]
    lines += ["", f"- Token rows: {t['token_rows']}. With an amount: **{t['tokens_with_amounts']}**. "
              f"Zeros without a raw zero: **{t['zeros_without_a_raw_zero']}**.",
              f"- Licence problems: **{lic['problems']}**. Groups in the bundle: {lic['groups_in_bundle']}.",
              f"- Portions: {pf['raw_cells']:,} raw cells re-read ({pf['raw_cells_by_kind']}), "
              f"{pf['canonical_portions']:,} canonical rows, **{pf['problems']}** fidelity problems."]
    for example in pf["examples"]:
        lines.append(f"  - portion: {example}")
    for ns, e in report["sources"].items():
        for example in e["fidelity"].get("examples", []):
            lines.append(f"  - {ns}: {example}")
    lines += ["", "## Soft checks", "", "### Energy: Almanac general Atwater vs the publisher's figure", "",
              "| Source | Food-basis pairs | General Atwater | Publisher only | Neither | Ratio p5 / median / p95 | Outliers |",
              "|---|---:|---:|---:|---:|---|---:|"]
    for ns, s in report["energy"].items():
        if ns == "usda_general_atwater_agreement":
            continue
        r = s["ratio_general_atwater_to_published"]
        ratio = f"{r['p5']} / {r['median']} / {r['p95']}" if "median" in r else "—"
        lines.append(f"| {ns} | {s['pairs']:,} | {s['general_atwater']:,} | {s['publisher_only']:,} | "
                     f"{s['neither']:,} | {ratio} | {s['outlier_count']} |")
    if agreement := report["energy"].get("usda_general_atwater_agreement"):
        lines += ["", f"USDA publishes its own general-Atwater figure (2047): Almanac's differs by a median "
                      f"{agreement['median_abs_kcal']} kcal over {agreement['n']} foods; "
                      f"{agreement['over_1_kcal']} differ by more than 1 kcal."]
    lines += ["", "Largest differences (|Δ| > 30 kcal and > 30 %):", ""]
    for ns, s in report["energy"].items():
        for o in s.get("outliers", [])[:5]:
            lines.append(f"- {o['food_ref']} {o['name']} ({o['basis']}): {o['general_atwater']} vs "
                         f"{o['published']} kcal")
    p = report["plausibility"]
    lines += ["", f"### Plausibility: {p['over_105_g']} food(s) above 105 g of macronutrients per 100 g", ""]
    lines += [f"- {i['food_ref']} {i['name']}: {i['grams']} g" for i in p["examples"]]
    return "\n".join(lines) + "\n"


def summary(report: dict) -> str:
    fidelity_problems = sum(e["fidelity"]["problems"] for e in report["sources"].values())
    return (f"qa {'PASSED' if report['passed'] else 'FAILED'}: fidelity problems {fidelity_problems}, "
            f"token problems {report['tokens']['problems']}, licence problems {report['licence']['problems']}, "
            f"portion fidelity problems {report['portion_fidelity']['problems']}; "
            f"implausible {report['plausibility']['over_105_g']}; report in processed/qa/report.md")
