"""ANSES-CIQUAL 2025 — licence group B (CC BY 4.0 and Etalab Open Licence 2.0).

README "Source rules": `extract` turns each XML table into a CSV, one column
per element; `canonicalise` applies dictionary/ and nothing else.
"""
from __future__ import annotations

import csv
import re
from collections import defaultdict
from pathlib import Path
from typing import Iterator

from lxml import etree

from ..canonical_io import CanonicalError, write_canonical
from ..dictionary import Dictionary
from ..lake import (Lake, read_csv, read_json, sha256_file, staged_directory, tool_revision,
                    utc_now, write_json)
from ..model import Food, FoodName, Value
from ..values import NegativeAmount, UnrecognisedValue, convert, qualify, select

NAMESPACE = "ciqual"
MANIFEST = "ciqual"
BASIS = "per_100g"  # every CIQUAL constituent is expressed per 100 g
TABLES = {f"{table}_2025_11_03.xml": f"{table}.csv"
          for table in ("alim", "alim_grp", "compo", "const", "sources")}
CANONICAL_INPUTS = ("alim.csv", "alim_grp.csv", "compo.csv", "const.csv")
GROUP_LEVELS = ("alim_ssssgrp", "alim_ssgrp", "alim_grp")  # most specific first
UNUSED_GROUP = re.compile(r"0+")  # CIQUAL fills an unused group level with zeros ("000000")
UNIT = re.compile(r"\(([^()/]+)/100 ?g\)$")  # "(kcal/100g)", "(µg/100 g)"


def records(path: Path) -> Iterator[dict[str, str]]:
    """Each record of a CIQUAL XML table, in file order: element -> trimmed text.

    An element carrying missing=" " is an absent value and becomes "".
    """
    depth = 0
    for event, element in etree.iterparse(str(path), events=("start", "end")):
        if event == "start":
            depth += 1
            continue
        depth -= 1
        if depth != 1:
            continue
        yield {child.tag: "" if child.get("missing") is not None else (child.text or "").strip()
               for child in element}
        element.clear()
        while element.getprevious() is not None:
            del element.getparent()[0]


def _xml_to_csv(source: Path, target: Path) -> int:
    count = 0
    header: list[str] = []
    with open(target, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        for record in records(source):
            if not header:
                header = list(record)
                writer.writerow(header)
            elif set(record) != set(header):
                raise CanonicalError(f"{source.name} record {count + 1} has elements "
                                     f"{sorted(record)}, not {sorted(header)}")
            writer.writerow([record[element] for element in header])
            count += 1
    return count


def extract(lake: Lake) -> Path:
    inputs = lake.verify_inputs(MANIFEST, list(TABLES))
    source = lake.source_dir(MANIFEST)
    out = lake.extracted(NAMESPACE)
    with staged_directory(out) as scratch:
        counts = {table: _xml_to_csv(source / xml, scratch / table) for xml, table in TABLES.items()}
        write_json(scratch / "manifest.json", {
            "stage": "extract",
            "namespace": NAMESPACE,
            "release": lake.manifest(MANIFEST)["release"],
            "generated_at": utc_now(),
            "tool_revision": tool_revision(),
            "inputs": inputs,
            "records": counts,
            "outputs": {p.name: sha256_file(p) for p in sorted(scratch.iterdir())},
        })
    return out


def _group_names(rows: list[dict[str, str]]) -> dict[str, str]:
    """Group code -> English name, across all three levels (their codes differ in length)."""
    names: dict[str, str] = {}
    for row in rows:
        for level in GROUP_LEVELS:
            code, name = row[f"{level}_code"], row[f"{level}_nom_eng"]
            if code and not UNUSED_GROUP.fullmatch(code):
                if names.setdefault(code, name) != name:
                    raise CanonicalError(f"alim_grp.csv names group {code} both {names[code]!r} "
                                         f"and {name!r}")
    return names


def _food_group(row: dict[str, str], names: dict[str, str]) -> tuple[str, str]:
    for level in GROUP_LEVELS:
        code = row[f"{level}_code"]
        if code and not UNUSED_GROUP.fullmatch(code):
            return code, names.get(code, "")
    return "", ""


def canonicalise(lake: Lake, dictionary: Dictionary) -> dict:
    ext = lake.extracted(NAMESPACE)
    extracted = read_json(ext / "manifest.json")
    for name in CANONICAL_INPUTS:
        if extracted["outputs"].get(name) != sha256_file(ext / name):
            raise CanonicalError(f"{ext / name} changed after extraction; re-run `extract ciqual`")
    inputs = [{"file": f"processed/extracted/{NAMESPACE}/{name}", "sha256": extracted["outputs"][name]}
              for name in CANONICAL_INPUTS]

    group = dictionary.group_of(NAMESPACE)
    tokens = dictionary.tokens_for(NAMESPACE)
    mapping_of = {m.source_nutrient_id: m
                  for maps in dictionary.mappings_for(NAMESPACE).values() for m in maps}
    const_names = {r["const_code"]: r["const_nom_eng"] for r in read_csv(ext / "const.csv")}
    for code, m in mapping_of.items():
        unit = UNIT.search(const_names.get(code, ""))
        if unit is None or unit.group(1) != m.source_unit:
            raise CanonicalError(f"nutrient_map.csv gives ciqual {code} unit {m.source_unit!r}; "
                                 f"const.csv names it {const_names.get(code)!r}")

    group_names = _group_names(read_csv(ext / "alim_grp.csv"))
    foods: list[Food] = []
    names: list[FoodName] = []
    unnamed_groups: set[str] = set()
    for row in read_csv(ext / "alim.csv"):
        code, group_name = _food_group(row, group_names)
        if code and not group_name:
            unnamed_groups.add(code)
        food = Food(NAMESPACE, row["alim_code"], group, code, group_name,
                    f"alim_2025_11_03.xml alim_code={row['alim_code']}")
        foods.append(food)
        english, french = row["alim_nom_eng"], row["alim_nom_fr"]
        if english:
            names.append(FoodName(food.food_ref, "en", english, True))
        if french:
            names.append(FoodName(food.food_ref, "fr", french, not english))

    known = {f.local_id for f in foods}
    seen: set[tuple[str, str]] = set()
    candidates: dict[tuple[str, str], list] = defaultdict(list)
    rejected: list[dict] = []
    for row in read_csv(ext / "compo.csv"):
        m = mapping_of.get(row["const_code"])
        if m is None:
            continue
        key = (row["alim_code"], row["const_code"])
        if key in seen:
            raise CanonicalError(f"compo.csv has two rows for alim_code {key[0]}, const_code {key[1]}; "
                                 "refusing to pick one")
        seen.add(key)
        if row["alim_code"] not in known:
            raise CanonicalError(f"compo.csv: alim_code {row['alim_code']} is not in alim.csv")
        ref = f"{NAMESPACE}:{row['alim_code']}"
        teneur = row["teneur"]
        if not teneur.strip():
            continue  # blank: CIQUAL says nothing, so there is no row
        try:
            qualified = qualify(teneur, tokens=tokens, numeric_override=m.numeric_qualifier_override,
                                decimal_comma=True, bound_prefix="<")
        except NegativeAmount:
            rejected.append({"food_ref": ref, "source_nutrient_id": m.source_nutrient_id,
                             "source_value": teneur.strip(), "reason": "negative amount"})
            continue
        except UnrecognisedValue as error:
            raise CanonicalError(f"{ref} const_code {row['const_code']}: {error}") from error
        candidates[(ref, m.nutrient_id)].append(
            (m.priority, qualified, (m, teneur.strip(), row["code_confiance"])))

    values = []
    for (ref, nutrient_id), found in sorted(candidates.items()):
        _, qualified, (m, source_value, confidence) = select(found)
        values.append(Value(ref, nutrient_id, BASIS, convert(qualified.amount, m.unit_conversion),
                            qualified.qualifier, confidence, source_value, m.source_nutrient_id,
                            m.source_unit, group))

    return write_canonical(lake.canonical(NAMESPACE), namespace=NAMESPACE, foods=foods, names=names,
                           values=values, dictionary=dictionary, inputs=inputs,
                           notes={"basis_rule": "every CIQUAL value is per 100 g",
                                  "food_groups_without_names": sorted(unnamed_groups),
                                  "rejected_values": rejected})
