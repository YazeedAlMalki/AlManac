"""USDA FoodData Central: Foundation Foods, SR Legacy and FNDDS — licence group A (CC0 1.0).

The reference source module (README "Source rules"): `extract` copies the
in-scope rows in USDA's own shape; `canonicalise` applies dictionary/ and
nothing else. All three data types come from the one full download and share
the `usda` namespace (`usda:<fdc_id>`). Each food's own code (Foundation and
SR Legacy NDB number, FNDDS food code) is kept in `source_record`, where the
food de-duplication stage (`merge.py`) reads it.
"""
from __future__ import annotations

import csv
import shutil
from collections import Counter, defaultdict
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
# data_type -> (the file listing that type's current foods, the column holding its own code)
LISTINGS = {
    "foundation_food": ("foundation_food.csv", "NDB_number"),
    "sr_legacy_food": ("sr_legacy_food.csv", "NDB_number"),
    "survey_fndds_food": ("survey_fndds_food.csv", "food_code"),
}
DATA_TYPES = tuple(LISTINGS)
# FNDDS publishes no derivation code: its values are calculated from its
# ingredients' values. derivation_qualifiers.csv gives this key that meaning.
NO_CODE = {"survey_fndds_food": "<none: survey_fndds_food>"}
BASIS = "per_100g"  # FDC reports every nutrient amount per 100 g of food
SCOPED_TABLES = ("food.csv", "food_nutrient.csv", "food_portion.csv", "input_food.csv")
WHOLE_TABLES = ("foundation_food.csv", "sr_legacy_food.csv", "survey_fndds_food.csv",
                "nutrient.csv", "food_nutrient_derivation.csv", "food_category.csv",
                "wweia_food_category.csv", "measure_unit.csv")
CANONICAL_INPUTS = ("food.csv", "foundation_food.csv", "sr_legacy_food.csv", "survey_fndds_food.csv",
                    "food_nutrient.csv", "nutrient.csv", "food_nutrient_derivation.csv",
                    "food_category.csv", "wweia_food_category.csv", "food_portion.csv",
                    "input_food.csv", "measure_unit.csv")


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

        def in_data_types(row, column):
            if row[column["data_type"]] in DATA_TYPES:
                in_scope.add(row[column["fdc_id"]])
                return True
            return False

        rows = {"food.csv": _filter_rows(source / "food.csv", scratch / "food.csv", in_data_types)}
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
    # data_type -> fdc_id -> the food's own code
    listed = {data_type: {r["fdc_id"]: _column(r, file, column) for r in read_csv(ext / file)}
              for data_type, (file, column) in LISTINGS.items()}
    categories = {r["id"]: r for r in read_csv(ext / "food_category.csv")}
    wweia = {_column(r, "wweia_food_category.csv", "wweia_food_category"):
             _column(r, "wweia_food_category.csv", "wweia_food_category_description")
             for r in read_csv(ext / "wweia_food_category.csv")}
    survey_categories = {r["fdc_id"]: _column(r, "survey_fndds_food.csv", "wweia_category_number")
                         for r in read_csv(ext / "survey_fndds_food.csv")}
    inputs_by_food: dict[str, list[dict]] = defaultdict(list)
    for r in read_csv(ext / "input_food.csv"):
        inputs_by_food[r["fdc_id"]].append(r)
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
    data_type_of: dict[str, str] = {}
    for row in read_csv(ext / "food.csv"):
        fdc_id, data_type = row["fdc_id"], row["data_type"]
        file, code_column = LISTINGS[data_type]
        if fdc_id not in listed[data_type]:
            excluded.append({"fdc_id": fdc_id, "description": row["description"],
                             "publication_date": row["publication_date"],
                             "reason": f"data_type {data_type} but not listed in "
                                       f"{file} (superseded or withdrawn record)"})
            continue
        record = f"food.csv fdc_id={fdc_id}; {file} {code_column}={listed[data_type][fdc_id]}"
        if data_type == "survey_fndds_food":
            group_code = survey_categories[fdc_id]
            group_name = wweia.get(group_code, "")
            # One ingredient and nothing else: the FNDDS food is that ingredient as eaten.
            ingredients = inputs_by_food.get(fdc_id, [])
            if len(ingredients) == 1:
                sole = ingredients[0]
                record += (f"; input_food.csv sole input fdc_id={sole['fdc_id_of_input_food'].strip()}"
                           f" sr_code={sole['sr_code'].strip()}")
        else:
            category = categories.get(row["food_category_id"], {})
            group_code, group_name = category.get("code", ""), category.get("description", "")
        food = Food(NAMESPACE, fdc_id, group, group_code, group_name, record)
        foods.append(food)
        data_type_of[fdc_id] = data_type
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
                code = (derivation_codes.get(row["derivation_id"]) if row["derivation_id"]
                        else NO_CODE.get(data_type_of[food.local_id], ""))
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
                                # The publisher's code verbatim; none when it published none.
                                code if row["derivation_id"] else "", row["amount"].strip(),
                                m.source_nutrient_id,
                                units[m.source_nutrient_id], group))

    # Portions (README "Units — two traps"): food_portion maps fdc_id + measure_unit -> gram_weight
    # directly, CC0, so household measures are solved for USDA without the FAO density database.
    portions: list[Portion] = []
    unnamed_portions: list[str] = []
    for row in read_csv(ext / "food_portion.csv"):
        if row["fdc_id"] not in kept or not row["gram_weight"].strip():
            continue
        unit_name = measure_units.get(row["measure_unit_id"])
        if unit_name is None:
            raise CanonicalError(f"usda:{row['fdc_id']} food_portion.csv id={row['id']}: measure_unit_id "
                                 f"{row['measure_unit_id']!r} is not in measure_unit.csv")
        data_type = data_type_of[row["fdc_id"]]
        if unit_name == "undetermined" and data_type != "foundation_food":
            # SR Legacy names its measure in `modifier` ("cup, chopped"), FNDDS in
            # `portion_description` ("1 cup"): the publisher's own words are the unit.
            unit_name = row["portion_description"].strip() or row["modifier"].strip()
            if not unit_name:
                unnamed_portions.append(f"food_portion.csv id={row['id']}")
                continue
        amount_text = row["amount"].strip()
        if not amount_text and data_type == "survey_fndds_food":
            # FNDDS states the count inside its description ("1 cup"): one of that portion.
            amount_text = "1"
        try:
            qualified = qualify(row["gram_weight"], tokens={})
            amount = float(amount_text)
        except (UnrecognisedValue, ValueError) as error:
            raise CanonicalError(f"usda:{row['fdc_id']} food_portion.csv id={row['id']}: {error}") from error
        portions.append(Portion(f"usda:{row['fdc_id']}", "household_measure", unit_name, amount,
                                qualified.amount, qualified.qualifier, row["data_points"].strip(),
                                row["gram_weight"].strip(), "g", row["portion_description"].strip(),
                                row["modifier"].strip(), f"food_portion.csv id={row['id']}", group))

    return write_canonical(lake.canonical(NAMESPACE), namespace=NAMESPACE, foods=foods, names=names,
                           values=values, portions=portions, dictionary=dictionary, inputs=inputs,
                           notes={"data_types": list(DATA_TYPES), "excluded": excluded,
                                  "foods_by_data_type": dict(sorted(Counter(data_type_of.values()).items())),
                                  "rejected_values": rejected,
                                  "unmapped_duplicates": unmapped_duplicates,
                                  "portions_with_no_measure_name": unnamed_portions})


def _column(row: dict, file: str, column: str) -> str:
    """A named column, or a stage failure naming the file: never a silent blank."""
    if column not in row:
        raise CanonicalError(f"{file} has no column {column!r}")
    return row[column].strip()
