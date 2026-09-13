"""Synthetic lakes and row sets. No test here reads the real lake unless it says so."""
from __future__ import annotations

import csv
import json
import os
import tempfile
import unittest
from pathlib import Path

from almanac_nutrition.dictionary import load
from almanac_nutrition.lake import Lake, sha256_file
from almanac_nutrition.model import Food, FoodName, Value

DICTIONARY = load()
INTEGRATION = os.environ.get("ALMANAC_NUTRITION_INTEGRATION") == "1"
REAL_LAKE = Lake()

integration = unittest.skipUnless(INTEGRATION and REAL_LAKE.root.is_dir(),
                                  "set ALMANAC_NUTRITION_INTEGRATION=1 to run against the real lake")


def temp_lake(case: unittest.TestCase) -> Lake:
    directory = tempfile.TemporaryDirectory()
    case.addCleanup(directory.cleanup)
    root = Path(directory.name)
    (root / "manifests").mkdir()
    return Lake(root)


def write_table(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n", quoting=csv.QUOTE_ALL)
        writer.writerow(header)
        writer.writerows(rows)


def register(lake: Lake, name: str, local_path: str, files: list[str], release: str = "test") -> None:
    """Writes manifests/{name}.json recording the files' current checksums."""
    base = lake.root / local_path
    lake.manifests.joinpath(f"{name}.json").write_text(json.dumps({
        "source_id": name, "release": release, "local_path": local_path,
        "files": [{"filename": f, "sha256": sha256_file(base / f)} for f in files]}))


def canonical_set(namespace: str = "cofid", count: int = 2, dictionary=DICTIONARY, group=None):
    """A valid row set exercising every qualifier the model distinguishes."""
    group = group or dictionary.group_of(namespace)
    foods = [Food(namespace, f"1-{i}", group, "G", "Group", f"test row {i}") for i in range(1, count + 1)]
    names = [FoodName(f.food_ref, "en", f"Food {f.local_id}", True) for f in foods]
    values = []
    for f in foods:
        ref = f.food_ref
        values += [
            Value(ref, "energy_kcal", "per_100g", 151.0, "calculated_factor", "", "151", "KCALS", "kcal", group),
            Value(ref, "protein", "per_100g", None, "trace", "", "Tr", "PROT", "g", group),
            Value(ref, "fibre_total_dietary", "per_100g", None, "not_analysed", "", "N", "AOACFIB", "g", group),
            Value(ref, "fat_total", "per_100g", 0.0, "zero_reported", "", "0", "FAT", "g", group),
            Value(ref, "carbohydrate_available_monosaccharide", "per_100g", 0.8, "measured", "", "0.8",
                  "CHO", "g", group),
        ]
    return foods, names, values
