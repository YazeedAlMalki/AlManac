"""Australian Food Composition Database, Release 3 (FSANZ) — licence group B (CC BY 4.0).

README "Source rules": `extract` writes every sheet of the six workbooks to
CSV, cell for cell; `canonicalise` reads the two nutrient-profile sheets and
applies dictionary/ and nothing else.
"""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from ..canonical_io import CanonicalError, write_canonical
from ..dictionary import Dictionary
from ..lake import Lake, read_json, sha256_file, staged_directory, tool_revision, utc_now, write_json
from ..model import Food, FoodName, Value
from ..values import NegativeAmount, UnrecognisedValue, convert, qualify, select
from ..xlsx import cell, extract_workbooks, read_sheet

NAMESPACE = "afcd"
MANIFEST = "ausnut"
PROFILES = "AFCD Release 3 - Nutrient profiles.xlsx"
GROUPS = "AFCD Release 3 - Food group information.xlsx"
WORKBOOKS = ("AFCD Release 3 - Food Details.xlsx", PROFILES, "AFCD Release 3 - Nutrient details.xlsx",
             "AFCD Release 3 - Recipes.xlsx", GROUPS, "AFCD Release 3 - Reference List.xlsx")
# Solids and liquids per 100 g; the liquids again per 100 mL. Two bases, never merged (§4).
PER_100G, PER_100ML = "All solids & liquids per 100 g", "Liquids only per 100 mL"
GROUP_SHEET = "Food group information"
HEADER_ROW = 3  # row 1 title, row 2 blank, row 3 headings; foods from row 4
KEY, CLASSIFICATION, DERIVATION, NAME = "Public Food Key", "Classification", "Derivation", "Food Name"
SUBGROUP = re.compile(r"(\d{3})\s*-\s*(.+)")  # "111 - Tea" in the Inclusions column


def heading(text: str) -> str:
    """AFCD headings carry line breaks and doubled spaces ("Protein \\n(g)"); collapse them."""
    return " ".join(text.split())


def _columns(row: list[str], sheet: str) -> dict[str, int]:
    columns: dict[str, int] = {}
    for i, text in enumerate(row):
        name = heading(text)
        if not name:
            continue
        if name in columns:
            raise CanonicalError(f"{sheet}: heading {name!r} appears twice")
        columns[name] = i
    return columns


def _group_names(rows: list[list[str]]) -> dict[str, str]:
    """2-digit food groups by ID and name, and their 3-digit sub-groups from Inclusions."""
    at = next((i for i, row in enumerate(rows) if cell(row, 0).strip() == "Food group ID"), None)
    if at is None:
        raise CanonicalError(f"{GROUPS}: no 'Food group ID' heading")
    columns = _columns(rows[at], GROUP_SHEET)
    names: dict[str, str] = {}
    for row in rows[at + 1:]:
        group_id = cell(row, columns["Food group ID"]).strip()
        if group_id:
            names[group_id] = cell(row, columns["Food group name"]).strip()
        for line in cell(row, columns["Inclusions"]).splitlines():
            if match := SUBGROUP.fullmatch(line.strip()):
                names[match.group(1)] = match.group(2).strip()
    return names


def extract(lake: Lake) -> Path:
    inputs = lake.verify_inputs(MANIFEST, WORKBOOKS)
    out = lake.extracted(NAMESPACE)
    with staged_directory(out) as scratch:
        sheets = extract_workbooks(lake.source_dir(MANIFEST), WORKBOOKS, scratch)
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


def canonicalise(lake: Lake, dictionary: Dictionary) -> dict:
    ext = lake.extracted(NAMESPACE)
    extracted = read_json(ext / "manifest.json")
    grams, grams_input = read_sheet(ext, extracted, PROFILES, PER_100G)
    millilitres, millilitres_input = read_sheet(ext, extracted, PROFILES, PER_100ML)
    group_rows, group_input = read_sheet(ext, extracted, GROUPS, GROUP_SHEET)

    group = dictionary.group_of(NAMESPACE)
    tokens = dictionary.tokens_for(NAMESPACE)
    derivations = dictionary.derivations_for(NAMESPACE)
    mappings = dictionary.mappings_for(NAMESPACE)
    for maps in mappings.values():
        for m in maps:
            if not m.source_nutrient_id.endswith(f"({m.source_unit})"):
                raise CanonicalError(f"nutrient_map.csv gives afcd {m.source_nutrient_id!r} unit "
                                     f"{m.source_unit!r}, which its heading does not state")
    group_names = _group_names(group_rows)

    columns = _columns(grams[HEADER_ROW - 1], PER_100G)
    body = [(n, row) for n, row in enumerate(grams[HEADER_ROW:], start=HEADER_ROW + 1)
            if cell(row, columns[KEY]).strip()]
    occurrences = Counter(cell(row, columns[KEY]).strip() for _, row in body)
    foods: dict[str, Food] = {}  # by Public Food Key; a repeated key maps to None
    derivation_of: dict[str, str] = {}
    names: list[FoodName] = []
    collisions: list[dict] = []
    for n, row in body:
        key = cell(row, columns[KEY]).strip()
        local_id = key if occurrences[key] == 1 else f"{key}@row{n}"  # README: repeated ids
        classification = cell(row, columns[CLASSIFICATION]).strip()
        food = Food(NAMESPACE, local_id, group, classification,
                    group_names.get(classification) or group_names.get(classification[:3])
                    or group_names.get(classification[:2], ""), f"{PER_100G}!row {n}")
        foods.setdefault(food.food_ref, food)
        derivation_of[food.food_ref] = cell(row, columns[DERIVATION]).strip()
        names.append(FoodName(food.food_ref, "en", cell(row, columns[NAME]).strip(), True))
        if occurrences[key] > 1:
            collisions.append({"public_food_key": key, "row": n, "local_id": local_id})

    values: list[Value] = []
    rejected: list[dict] = []

    def read_values(rows: list[list[str]], sheet: str, basis: str) -> None:
        cols = _columns(rows[HEADER_ROW - 1], sheet)
        for maps in mappings.values():
            for m in maps:
                if m.source_nutrient_id not in cols:
                    raise CanonicalError(f"{sheet}: no heading {m.source_nutrient_id!r}")
        for n, row in enumerate(rows[HEADER_ROW:], start=HEADER_ROW + 1):
            key = cell(row, cols[KEY]).strip()
            if not key:
                continue
            ref = f"{NAMESPACE}:{key}"
            if occurrences[key] != 1 or ref not in foods:
                raise CanonicalError(f"{sheet}!row {n}: Public Food Key {key!r} does not name exactly "
                                     f"one food in {PER_100G}")
            derivation = cell(row, cols[DERIVATION]).strip()
            if derivation != derivation_of[ref]:
                raise CanonicalError(f"{ref}: Derivation {derivation!r} in {sheet} but "
                                     f"{derivation_of[ref]!r} in {PER_100G}")
            if derivation not in derivations:
                raise CanonicalError(f"{ref}: Derivation {derivation!r} has no row in "
                                     "dictionary/derivation_qualifiers.csv")
            for nutrient_id, maps in mappings.items():
                candidates = []
                for m in maps:
                    text = cell(row, cols[m.source_nutrient_id])
                    if not text.strip():
                        continue  # blank: FSANZ says nothing, so there is no row
                    try:
                        qualified = qualify(text, tokens=tokens,
                                            numeric_override=m.numeric_qualifier_override,
                                            derivation_qualifier=derivations[derivation])
                    except NegativeAmount:
                        rejected.append({"food_ref": ref, "basis": basis,
                                         "source_nutrient_id": m.source_nutrient_id,
                                         "source_value": text.strip(), "reason": "negative amount"})
                        continue
                    except UnrecognisedValue as error:
                        raise CanonicalError(f"{ref} ({sheet}!row {n}) {m.source_nutrient_id}: "
                                             f"{error}") from error
                    candidates.append((m.priority, qualified, (m, text.strip())))
                chosen = select(candidates)
                if chosen is None:
                    continue
                _, qualified, (m, source_value) = chosen
                values.append(Value(ref, nutrient_id, basis, convert(qualified.amount, m.unit_conversion),
                                    qualified.qualifier, derivation, source_value,
                                    m.source_nutrient_id, m.source_unit, group))

    read_values(grams, PER_100G, "per_100g")
    read_values(millilitres, PER_100ML, "per_100ml")
    per_100ml = sorted({v.food_ref for v in values if v.basis == "per_100ml"})
    return write_canonical(
        lake.canonical(NAMESPACE), namespace=NAMESPACE, foods=list(foods.values()), names=names,
        values=values, dictionary=dictionary, inputs=[grams_input, millilitres_input, group_input],
        notes={"basis_rule": f"per_100g from {PER_100G!r}; per_100ml from {PER_100ML!r}",
               "per_100ml_foods": len(per_100ml),
               "confidence": "the food-level Derivation, which FSANZ says describes the majority "
                             "of a food's data; individual nutrients may differ (Sampling Details)",
               "food_groups_without_names": sorted({f.food_group_code for f in foods.values()
                                                    if not f.food_group_name}),
               "collisions": collisions, "rejected_values": rejected})
