"""McCance and Widdowson's CoFID 2021 — licence group B (Open Government Licence v3.0).

README "Source rules": `extract` writes every sheet of both workbooks to CSV,
cell for cell, all three header rows kept; `canonicalise` reads
`1.3 Proximates` only and applies dictionary/ and nothing else.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path

from ..canonical_io import CanonicalError, write_canonical
from ..dictionary import Dictionary
from ..lake import Lake, read_json, sha256_file, staged_directory, tool_revision, utc_now, write_json
from ..model import Food, FoodName, Value
from ..values import NegativeAmount, UnrecognisedValue, convert, qualify, select
from ..xlsx import cell, extract_workbooks, read_sheet

NAMESPACE = "cofid"
MANIFEST = "cofid"
WORKBOOK = "McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx"
OLD_FOODS = "CoFID_oldFoods.xlsx"  # superseded analyses (fibre fractions, Southgate fibre, sulphur): extracted only
INPUTS = (WORKBOOK, OLD_FOODS)
FOOD_SHEET = "1.3 Proximates"
HEADER_ROWS = 3  # row 1 heading, row 2 nutrient code, row 3 description; foods from row 4
CODE_ROW = 2
FOOD_CODE, FOOD_NAME, GROUP = "Food Code", "Food Name", "Group"

# "Nutrient values are expressed per 100g of the food except in the case of
# alcoholic beverages which are presented per 100ml" (user guide p.7; sheet
# 1.1 Notes). Alcoholic beverages are food group Q and its sub-groups
# (Appendix B): QA beers, QC ciders, QE wines, QF fortified wines,
# QG vermouths, QI liqueurs, QK spirits, and Q itself (pre-mixed drinks).
ALCOHOLIC_GROUP_PREFIX = "Q"

# Food group names: Appendix B "Food sub-group codes" (pp.23-26) of the user
# guide below, transcribed with `pdftotext -layout`. The guide is not a
# pipeline input (the pipeline needs no PDF tooling); the integration test
# re-reads the guide and fails if this table ever differs from it.
GUIDE = "McCance_and_Widdowsons_Composition_of_Foods_integrated_dataset_2021_user_guide.pdf"
GUIDE_SHA256 = "cbac83af403531f1db260a15de058ceca1c1bae6707a8748ee3788fee7f945ec"
APPENDIX_B = dict((
    ("A", "Cereals and cereal products"), ("AA", "Flours, grains and starches"), ("AB", "Sandwiches"),
    ("AC", "Rice"), ("AD", "Pasta"), ("AE", "Pizzas"), ("AF", "Breads"), ("AG", "Rolls"),
    ("AI", "Breakfast cereals"), ("AK", "Infant cereal foods"), ("AM", "Biscuits"), ("AN", "Cakes"),
    ("AO", "Pastry"), ("AP", "Buns and pastries"), ("AS", "Puddings"), ("AT", "Savouries"),
    ("B", "Milk and milk products"), ("BA", "Cows milk"), ("BAB", "Breakfast milk"),
    ("BAE", "Skimmed milk"), ("BAH", "Semi-skimmed milk"), ("BAK", "Whole milk"),
    ("BAN", "Channel Island milk"), ("BAR", "Processed milks"), ("BC", "Other milks"),
    ("BF", "Infant formulas"), ("BFD", "Whey-based modified milks"),
    ("BFG", "Non-whey-based modified milks"), ("BFJ", "Soya-based modified milks"),
    ("BFP", "Follow-on formulas"), ("BH", "Milk-based drinks"), ("BJ", "Creams"),
    ("BJC", "Fresh creams (pasteurised)"), ("BJF", "Frozen creams (pasteurised)"),
    ("BJL", "Sterilised creams"), ("BJP", "UHT creams"), ("BJS", "Imitation creams"),
    ("BL", "Cheeses"), ("BN", "Yogurts"), ("BNE", "Whole milk yogurts"), ("BNH", "Low fat yogurts"),
    ("BNS", "Other yogurts"), ("BP", "Ice creams"), ("BR", "Puddings and chilled desserts"),
    ("BV", "Savoury dishes and sauces"),
    ("C", "Eggs"), ("CA", "Eggs"), ("CD", "Egg dishes"), ("CDE", "Savoury egg dishes"),
    ("CDH", "Sweet egg dishes"),
    ("D", "Vegetables"), ("DA", "Potatoes"), ("DAE", "Early potatoes"), ("DAM", "Main crop potatoes"),
    ("DAP", "Chipped old potatoes"), ("DAR", "Potato products"), ("DB", "Beans and lentils"),
    ("DF", "Peas"), ("DG", "Vegetables, general"), ("DI", "Vegetables, dried"),
    ("DR", "Vegetable dishes"),
    ("F", "Fruit"), ("FA", "Fruit, general"), ("FC", "Fruit juices"),
    ("G", "Nuts and seeds"), ("GA", "Nuts and seeds, general"),
    ("H", "Herbs and spices"),
    ("J", "Fish and fish products"), ("JA", "White fish"), ("JC", "Fatty fish"), ("JK", "Crustacea"),
    ("JM", "Molluscs"), ("JR", "Fish products and dishes"),
    ("M", "Meat and meat products"), ("MA", "Meat"), ("MAA", "Bacon"), ("MAC", "Beef"),
    ("MAE", "Lamb"), ("MAG", "Pork"), ("MAI", "Veal"), ("MC", "Poultry"), ("MCA", "Chicken"),
    ("MCC", "Duck"), ("MCE", "Goose"), ("MCG", "Grouse"), ("MCI", "Partridge"), ("MCK", "Pheasant"),
    ("MCM", "Pigeon"), ("MCO", "Turkey"), ("ME", "Game"), ("MEA", "Hare"), ("MEC", "Rabbit"),
    ("MEE", "Venison"), ("MG", "Offal"), ("MBG", "Burgers and grillsteaks"), ("MI", "Meat products"),
    ("MIG", "Other meat products"), ("MR", "Meat dishes"),
    ("O", "Fats and oils"), ("OA", "Spreading fats"), ("OB", "Animal fats"), ("OC", "Oils"),
    ("OE", "Non-animal fats"), ("OF", "Cooking fats"),
    ("P", "Beverages"), ("PA", "Powdered drinks, essences and infusions"),
    ("PAA", "Powdered drinks and essences"), ("PAC", "Infusions"), ("PC", "Soft drinks"),
    ("PCA", "Carbonated drinks"), ("PCC", "Squash and cordials"), ("PE", "Juices"),
    ("Q", "Alcoholic beverages"), ("QA", "Beers"), ("QC", "Ciders"), ("QE", "Wines"),
    ("QF", "Fortified wines"), ("QG", "Vermouths"), ("QI", "Liqueurs"), ("QK", "Spirits"),
    ("S", "Sugars, preserves and snacks"), ("SC", "Sugars, syrups and preserves"),
    ("SE", "Confectionery"), ("SEA", "Chocolate confectionery"), ("SEC", "Non-chocolate confectionery"),
    ("SN", "Savoury snacks"), ("SNA", "Potato-based snacks"), ("SNB", "Potato and mixed cereal snacks"),
    ("SNC", "Non-potato snacks"),
    ("W", "Soups, sauces and miscellaneous foods"), ("WA", "Soups"), ("WAA", "Homemade soups"),
    ("WAC", "Canned soups"), ("WAE", "Packet soups"), ("WC", "Sauces"), ("WCD", "Dairy sauces"),
    ("WCG", "Salad sauces, dressings and pickles"), ("WCN", "Non-salad sauces"),
    ("WE", "Pickles and chutneys"), ("WY", "Miscellaneous foods"),
))


def basis_of(food_group_code: str) -> str:
    return "per_100ml" if food_group_code.startswith(ALCOHOLIC_GROUP_PREFIX) else "per_100g"


def extract(lake: Lake) -> Path:
    inputs = lake.verify_inputs(MANIFEST, INPUTS)
    out = lake.extracted(NAMESPACE)
    with staged_directory(out) as scratch:
        sheets = extract_workbooks(lake.source_dir(MANIFEST), INPUTS, scratch)
        write_json(scratch / "manifest.json", {
            "stage": "extract",
            "namespace": NAMESPACE,
            "release": lake.manifest(MANIFEST)["release"],
            "generated_at": utc_now(),
            "tool_revision": tool_revision(),
            "inputs": inputs,
            "sheets": sheets,
            "outputs": {p.name: sha256_file(p) for p in sorted(scratch.iterdir())},
        })
    return out


def _column(cells: list[str], text: str, where: str) -> int:
    found = [i for i, c in enumerate(cells) if c.strip() == text]
    if len(found) != 1:
        raise CanonicalError(f"{FOOD_SHEET} {where}: {text!r} is in {len(found)} columns, expected 1")
    return found[0]


def canonicalise(lake: Lake, dictionary: Dictionary) -> dict:
    ext = lake.extracted(NAMESPACE)
    rows, food_input = read_sheet(ext, read_json(ext / "manifest.json"), WORKBOOK, FOOD_SHEET)
    if len(rows) < HEADER_ROWS:
        raise CanonicalError(f"{FOOD_SHEET}: {len(rows)} rows, fewer than its {HEADER_ROWS} header rows")
    headings, codes = rows[0], rows[CODE_ROW - 1]
    code_col = _column(headings, FOOD_CODE, "row 1")
    name_col = _column(headings, FOOD_NAME, "row 1")
    group_col = _column(headings, GROUP, "row 1")

    group = dictionary.group_of(NAMESPACE)
    tokens = dictionary.tokens_for(NAMESPACE)
    mappings = dictionary.mappings_for(NAMESPACE)
    columns: dict[str, int] = {}
    for maps in mappings.values():
        for m in maps:
            col = _column(codes, m.source_nutrient_id, f"row {CODE_ROW} (nutrient codes)")
            if not headings[col].strip().endswith(f"({m.source_unit})"):
                raise CanonicalError(f"nutrient_map.csv gives {NAMESPACE} {m.source_nutrient_id} unit "
                                     f"{m.source_unit!r}; {FOOD_SHEET} row 1 says {headings[col]!r}")
            columns[m.source_nutrient_id] = col

    body = list(enumerate(rows[HEADER_ROWS:], start=HEADER_ROWS + 1))
    coded = [(n, row) for n, row in body if cell(row, code_col).strip()]
    excluded = [{"row": n, "cells": [c for c in row if c.strip()],
                 "reason": f"no {FOOD_CODE}; README takes foods from rows with one"}
                for n, row in body if not cell(row, code_col).strip() and any(c.strip() for c in row)]
    occurrences = Counter(cell(row, code_col).strip() for _, row in coded)

    foods: list[tuple[Food, int, list[str]]] = []
    names: list[FoodName] = []
    collisions: dict[str, dict] = {}
    unlisted_groups: dict[str, list[str]] = {}
    for n, row in coded:
        code = cell(row, code_col).strip()
        local_id = code
        if occurrences[code] > 1:
            # README: every occurrence of a repeated publisher code becomes {code}@row{n}.
            local_id = f"{code}@row{n}"
            entry = collisions.setdefault(code, {"food_code": code, "rows": [], "local_ids": [],
                                                 "names": []})
            entry["rows"].append(n)
            entry["local_ids"].append(local_id)
            entry["names"].append(cell(row, name_col).strip())
        group_code = cell(row, group_col).strip()
        if group_code not in APPENDIX_B:
            unlisted_groups.setdefault(group_code, []).append(f"{NAMESPACE}:{local_id}")
        food = Food(NAMESPACE, local_id, group, group_code, APPENDIX_B.get(group_code, ""),
                    f"{FOOD_SHEET}!row {n}")
        foods.append((food, n, row))
        names.append(FoodName(food.food_ref, "en", cell(row, name_col).strip(), True))

    values: list[Value] = []
    rejected: list[dict] = []
    for food, n, row in foods:
        basis = basis_of(food.food_group_code)
        for nutrient_id, maps in mappings.items():
            candidates = []
            for m in maps:
                text = cell(row, columns[m.source_nutrient_id])
                if not text.strip():
                    continue  # blank: CoFID says nothing, so there is no row
                try:
                    qualified = qualify(text, tokens=tokens, numeric_override=m.numeric_qualifier_override)
                except NegativeAmount:
                    rejected.append({"food_ref": food.food_ref, "source_nutrient_id": m.source_nutrient_id,
                                     "source_value": text.strip(), "reason": "negative amount"})
                    continue
                except UnrecognisedValue as error:
                    raise CanonicalError(f"{food.food_ref} ({FOOD_SHEET}!row {n}) "
                                         f"{m.source_nutrient_id}: {error}") from error
                candidates.append((m.priority, qualified, (m, text.strip())))
            chosen = select(candidates)
            if chosen is None:
                continue
            _, qualified, (m, source_value) = chosen
            values.append(Value(food.food_ref, nutrient_id, basis,
                                convert(qualified.amount, m.unit_conversion), qualified.qualifier,
                                "", source_value, m.source_nutrient_id, m.source_unit, group))

    by_ref = {food.food_ref: (food, names[i].name) for i, (food, _, _) in enumerate(foods)}
    notes = {
        "sheet": FOOD_SHEET,
        "not_canonicalised": [f"{WORKBOOK}: every sheet but {FOOD_SHEET}",
                              f"{OLD_FOODS}: every sheet (superseded analyses)"],
        "basis_rule": f"per_100ml for food groups starting {ALCOHOLIC_GROUP_PREFIX!r} (alcoholic "
                      "beverages: user guide p.7, sheet 1.1 Notes); per_100g for every other food",
        "per_100ml_foods": [{"food_ref": f.food_ref, "food_group_code": f.food_group_code,
                             "name": by_ref[f.food_ref][1]}
                            for f, _, _ in foods if basis_of(f.food_group_code) == "per_100ml"],
        # Alcohol in a food outside group Q: per_100g by the rule above. Listed so that a
        # reviewer can see every such food (dishes cooked with wine, and Irish coffee).
        "alcohol_outside_alcoholic_groups": [
            {"food_ref": v.food_ref, "food_group_code": by_ref[v.food_ref][0].food_group_code,
             "name": by_ref[v.food_ref][1], "source_value": v.source_value, "basis": v.basis}
            for v in values if v.nutrient_id == "alcohol" and v.amount and v.basis == "per_100g"],
        "food_group_names": f"user guide {GUIDE} (sha256 {GUIDE_SHA256}) Appendix B",
        "food_groups_not_in_appendix_b": unlisted_groups,
        "collisions": list(collisions.values()),
        "excluded": excluded,
        "rejected_values": rejected,
    }
    return write_canonical(lake.canonical(NAMESPACE), namespace=NAMESPACE,
                           foods=[food for food, _, _ in foods], names=names, values=values,
                           dictionary=dictionary, inputs=[food_input], notes=notes)
