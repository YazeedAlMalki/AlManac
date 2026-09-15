"""USDA FoodData Central, Foundation Foods — licence group A (CC0 1.0).

The reference source module (README "Source rules"): `extract` copies the
in-scope rows in USDA's own shape; `canonicalise` applies dictionary/ and
nothing else.
"""
from __future__ import annotations

import csv
import shutil
from collections import defaultdict
from pathlib import Path

from ..canonical_io import CanonicalError, write_canonical
from ..dictionary import Dictionary
from ..lake import (Lake, read_csv, read_json, sha256_file, staged_directory, tool_revision,
                    utc_now, write_json)
from ..model import Food, FoodName, Portion, Value
from ..values import NegativeAmount, UnrecognisedValue, convert, qualify, select

NAMESPACE = "usda"
MANIFEST = "usda"
RELEASE_FOLDER = "FoodData_Central_csv_2026-04-30"
DATA_TYPES = ("foundation_food",)
BASIS = "per_100g"  # FDC reports every nutrient amount per 100 g of food
SCOPED_TABLES = ("food.csv", "food_nutrient.csv", "food_portion.csv")
WHOLE_TABLES = ("foundation_food.csv", "nutrient.csv", "food_nutrient_derivation.csv",
                "food_category.csv", "measure_unit.csv")
CANONICAL_INPUTS = ("food.csv", "foundation_food.csv", "food_nutrient.csv", "nutrient.csv",
                    "food_nutrient_derivation.csv", "food_category.csv", "food_portion.csv",
                    "measure_unit.csv")


def _filter_rows(src: Path, dst: Path, keep) -> int:
    """Copies the header and every row `keep(row, column_index)` accepts. Cells untouched."""
    kept = 0
    with open(src, newline="", encoding="utf-8-sig") as fin, \
            open(dst, "w", newline="", encoding="utf-8") as fout:
        reader = csv.reader(fin)
        writer = csv.writer(fout, lineterminator="\n", quoting=csv.QUOTE_ALL)
        header = next(reader)
        writer.writerow(header)
        column = {name: i for i, name in enumerate(header)}
        for row in reader:
            if keep(row, column):
                writer.writerow(row)
                kept += 1
    return kept


def extract(lake: Lake) -> Path:
    inputs = lake.verify_inputs(MANIFEST, [f"{RELEASE_FOLDER}/{t}" for t in SCOPED_TABLES + WHOLE_TABLES])
    source = lake.source_dir(MANIFEST) / RELEASE_FOLDER
    out = lake.extracted(NAMESPACE)
    with staged_directory(out) as scratch:
        in_scope: set[str] = set()

        def foundation(row, column):
            if row[column["data_type"]] in DATA_TYPES:
                in_scope.add(row[column["fdc_id"]])
                return True
            return False

        rows = {"food.csv": _filter_rows(source / "food.csv", scratch / "food.csv", foundation)}
        for table in SCOPED_TABLES[1:]:
            rows[table] = _filter_rows(source / table, scratch / table,
                                       lambda row, column: row[column["fdc_id"]] in in_scope)
        for table in WHOLE_TABLES:
            shutil.copyfile(source / table, scratch / table)
        write_json(scratch / "manifest.json", {
            "stage": "extract",
            "namespace": NAMESPACE,
            "release": lake.manifest(MANIFEST)["release"],
            "data_types": list(DATA_TYPES),
            "generated_at": utc_now(),
            "tool_revision": tool_revision(),
            "inputs": inputs,
            "rows_kept": rows,
            "outputs": {p.name: sha256_file(p) for p in sorted(scratch.iterdir())},
        })
    return out


def canonicalise(lake: Lake, dictionary: Dictionary) -> dict:
    ext = lake.extracted(NAMESPACE)
    extracted = read_json(ext / "manifest.json")
    for name in CANONICAL_INPUTS:
        if extracted["outputs"].get(name) != sha256_file(ext / name):
            raise CanonicalError(f"{ext / name} changed after extraction; re-run `extract usda`")
    inputs = [{"file": f"processed/extracted/{NAMESPACE}/{name}", "sha256": extracted["outputs"][name]}
              for name in CANONICAL_INPUTS]

    group = dictionary.group_of(NAMESPACE)
    listed = {r["fdc_id"] for r in read_csv(ext / "foundation_food.csv")}
    categories = {r["id"]: r for r in read_csv(ext / "food_category.csv")}
    derivation_codes = {r["id"]: r["code"] for r in read_csv(ext / "food_nutrient_derivation.csv")}
    units = {r["id"]: r["unit_name"] for r in read_csv(ext / "nutrient.csv")}
    measure_units = {r["id"]: r["name"] for r in read_csv(ext / "measure_unit.csv")}
    mappings = dictionary.mappings_for(NAMESPACE)
    for maps in mappings.values():
        for m in maps:
            if units.get(m.source_nutrient_id) != m.source_unit:
                raise CanonicalError(f"nutrient_map.csv gives usda {m.source_nutrient_id} unit "
                                     f"{m.source_unit!r}; nutrient.csv says "
                                     f"{units.get(m.source_nutrient_id)!r}")
    tokens = dictionary.tokens_for(NAMESPACE)
    derivations = dictionary.derivations_for(NAMESPACE)

    foods: list[Food] = []
    names: list[FoodName] = []
    excluded: list[dict] = []
    for row in read_csv(ext / "food.csv"):
        fdc_id = row["fdc_id"]
        if fdc_id not in listed:
            excluded.append({"fdc_id": fdc_id, "description": row["description"],
                             "publication_date": row["publication_date"],
                             "reason": "data_type foundation_food but not listed in "
                                       "foundation_food.csv (superseded or withdrawn record)"})
            continue
        category = categories.get(row["food_category_id"], {})
        food = Food(NAMESPACE, fdc_id, group, category.get("code", ""),
                    category.get("description", ""), f"food.csv fdc_id={fdc_id}")
        foods.append(food)
        names.append(FoodName(food.food_ref, "en", row["description"].strip(), True))

    kept = {f.local_id for f in foods}
    mapped = {m.source_nutrient_id for maps in mappings.values() for m in maps}
    by_food: dict[str, dict[str, dict]] = defaultdict(dict)
    unmapped_duplicates: list[dict] = []
    for row in read_csv(ext / "food_nutrient.csv"):
        if row["fdc_id"] not in kept:
            continue
        if row["nutrient_id"] in by_food[row["fdc_id"]]:
            if row["nutrient_id"] in mapped:
                raise CanonicalError(f"usda:{row['fdc_id']} has two food_nutrient rows for nutrient "
                                     f"{row['nutrient_id']}; refusing to pick one")
            # Not canonicalised in this phase, so nothing is picked — but a reviewer should know.
            unmapped_duplicates.append({"fdc_id": row["fdc_id"], "nutrient_id": row["nutrient_id"],
                                        "food_nutrient_ids": [by_food[row["fdc_id"]][row["nutrient_id"]]["id"],
                                                              row["id"]]})
            continue
        by_food[row["fdc_id"]][row["nutrient_id"]] = row

    values: list[Value] = []
    rejected: list[dict] = []
    for food in foods:
        published = by_food.get(food.local_id, {})
        for nutrient_id, maps in mappings.items():
            candidates = []
            for m in maps:
                row = published.get(m.source_nutrient_id)
                if row is None or not row["amount"].strip():
                    continue
                code = derivation_codes.get(row["derivation_id"]) if row["derivation_id"] else ""
                if code is None:
                    raise CanonicalError(f"{food.food_ref}: derivation_id {row['derivation_id']!r} "
                                         "is not in food_nutrient_derivation.csv")
                if code not in derivations:
                    raise CanonicalError(f"USDA derivation code {code!r} has no row in "
                                         "dictionary/derivation_qualifiers.csv")
                try:
                    qualified = qualify(row["amount"], tokens=tokens,
                                        numeric_override=m.numeric_qualifier_override,
                                        derivation_qualifier=derivations[code])
                except NegativeAmount:
                    # USDA publishes a negative "carbohydrate, by difference" where the other
                    # proximates sum past 100 g. Not a quantity: no row, and it is recorded.
                    rejected.append({"food_ref": food.food_ref, "source_nutrient_id": m.source_nutrient_id,
                                     "source_value": row["amount"], "reason": "negative amount"})
                    continue
                except UnrecognisedValue as error:
                    raise CanonicalError(f"{food.food_ref} nutrient {m.source_nutrient_id}: {error}") from error
                candidates.append((m.priority, qualified, (m, row, code)))
            chosen = select(candidates)
            if chosen is None:
                continue
            _, qualified, (m, row, code) = chosen
            values.append(Value(food.food_ref, nutrient_id, BASIS,
                                convert(qualified.amount, m.unit_conversion), qualified.qualifier,
                                code, row["amount"].strip(), m.source_nutrient_id,
                                units[m.source_nutrient_id], group))

    # Portions (README "Units — two traps"): food_portion maps fdc_id + measure_unit -> gram_weight
    # directly, CC0, so household measures are solved for USDA without the FAO density database.
    portions: list[Portion] = []
    for row in read_csv(ext / "food_portion.csv"):
        if row["fdc_id"] not in kept or not row["gram_weight"].strip():
            continue
        unit_name = measure_units.get(row["measure_unit_id"])
        if unit_name is None:
            raise CanonicalError(f"usda:{row['fdc_id']} food_portion.csv id={row['id']}: measure_unit_id "
                                 f"{row['measure_unit_id']!r} is not in measure_unit.csv")
        try:
            qualified = qualify(row["gram_weight"], tokens={})
            amount = float(row["amount"].strip())
        except (UnrecognisedValue, ValueError) as error:
            raise CanonicalError(f"usda:{row['fdc_id']} food_portion.csv id={row['id']}: {error}") from error
        portions.append(Portion(f"usda:{row['fdc_id']}", "household_measure", unit_name, amount,
                                qualified.amount, qualified.qualifier, row["data_points"].strip(),
                                row["gram_weight"].strip(), "g", row["portion_description"].strip(),
                                row["modifier"].strip(), f"food_portion.csv id={row['id']}", group))

    return write_canonical(lake.canonical(NAMESPACE), namespace=NAMESPACE, foods=foods, names=names,
                           values=values, portions=portions, dictionary=dictionary, inputs=inputs,
                           notes={"data_types": list(DATA_TYPES), "excluded": excluded,
                                  "rejected_values": rejected,
                                  "unmapped_duplicates": unmapped_duplicates})
