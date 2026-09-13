"""Reading and writing canonical row sets (README "Canonical format").

The same three files describe processed/canonical/{namespace}/ and
processed/union/; only the manifest differs.
"""
from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Iterable, Sequence

from .dictionary import Dictionary
from .lake import (read_csv, read_json, sha256_file, staged_directory, tool_revision, utc_now,
                   write_csv, write_json)
from .model import Food, FoodName, Value, validate

ROW_FILES = ("foods.csv", "food_names.csv", "values.csv")
FOOD_COLUMNS = ["food_ref", "namespace", "local_id", "licence_group", "food_group_code",
                "food_group_name", "source_record"]
NAME_COLUMNS = ["food_ref", "language", "name", "is_primary"]
VALUE_COLUMNS = ["food_ref", "nutrient_id", "basis", "amount", "qualifier", "confidence",
                 "source_value", "source_nutrient_id", "source_unit", "licence_group"]


class CanonicalError(ValueError):
    """A row set breaks the contract. Nothing is written."""


def format_amount(amount: float | None) -> str:
    return "" if amount is None else repr(float(amount))


def parse_amount(text: str) -> float | None:
    return None if text == "" else float(text)


def raise_if_invalid(problems: Sequence[str], what: str) -> None:
    if problems:
        shown = "\n  ".join(problems[:30])
        more = f"\n  … and {len(problems) - 30} more" if len(problems) > 30 else ""
        raise CanonicalError(f"{what}: {len(problems)} problem(s)\n  {shown}{more}")


def counts(foods: Sequence[Food], names: Sequence[FoodName], values: Sequence[Value]) -> dict:
    return {
        "foods": len(foods),
        "names": len(names),
        "values": len(values),
        "values_by_nutrient": dict(sorted(Counter(v.nutrient_id for v in values).items())),
        "values_by_qualifier": dict(sorted(Counter(v.qualifier for v in values).items())),
        "values_by_basis": dict(sorted(Counter(v.basis for v in values).items())),
        "foods_without_values": len({f.food_ref for f in foods} - {v.food_ref for v in values}),
    }


def write_rows(directory: Path, foods: Iterable[Food], names: Iterable[FoodName],
               values: Iterable[Value]) -> dict[str, str]:
    """Writes the three row files in key order; returns their SHA-256s."""
    write_csv(directory / "foods.csv", FOOD_COLUMNS, (
        [f.food_ref, f.namespace, f.local_id, f.licence_group, f.food_group_code,
         f.food_group_name, f.source_record]
        for f in sorted(foods, key=lambda f: f.food_ref)))
    write_csv(directory / "food_names.csv", NAME_COLUMNS, (
        [n.food_ref, n.language, n.name, "1" if n.is_primary else "0"]
        for n in sorted(names, key=lambda n: (n.food_ref, n.language))))
    write_csv(directory / "values.csv", VALUE_COLUMNS, (
        [v.food_ref, v.nutrient_id, v.basis, format_amount(v.amount), v.qualifier, v.confidence,
         v.source_value, v.source_nutrient_id, v.source_unit, v.licence_group]
        for v in sorted(values, key=lambda v: (v.food_ref, v.nutrient_id, v.basis))))
    return {name: sha256_file(directory / name) for name in ROW_FILES}


def write_canonical(out_dir: Path, *, namespace: str, foods: Iterable[Food],
                    names: Iterable[FoodName], values: Iterable[Value], dictionary: Dictionary,
                    inputs: list[dict], notes: dict | None = None) -> dict:
    """Validates, then replaces `out_dir`. An invalid set leaves the old output untouched."""
    foods, names, values = list(foods), list(names), list(values)
    raise_if_invalid(validate(foods, names, values, dictionary, namespace=namespace),
                     f"canonical/{namespace}")
    source = dictionary.sources[namespace]
    with staged_directory(out_dir) as scratch:
        manifest = {
            "stage": "canonical",
            "namespace": namespace,
            "dataset_id": source.dataset_id,
            "release": source.release,
            "licence_group": source.licence_group,
            "dictionary_sha256": dictionary.sha256,
            "generated_at": utc_now(),
            "tool_revision": tool_revision(),
            "inputs": inputs,
            "outputs": write_rows(scratch, foods, names, values),
            "counts": counts(foods, names, values),
            "notes": notes or {},
        }
        write_json(scratch / "manifest.json", manifest)
    return manifest


def read_rows(directory: Path) -> tuple[list[Food], list[FoodName], list[Value]]:
    foods = []
    for r in read_csv(directory / "foods.csv"):
        food = Food(r["namespace"], r["local_id"], r["licence_group"], r["food_group_code"],
                    r["food_group_name"], r["source_record"])
        if r["food_ref"] != food.food_ref:
            raise CanonicalError(f"{directory}/foods.csv: food_ref {r['food_ref']!r} is not "
                                 f"namespace:local_id ({food.food_ref!r})")
        foods.append(food)
    names = [FoodName(r["food_ref"], r["language"], r["name"], r["is_primary"] == "1")
             for r in read_csv(directory / "food_names.csv")]
    values = [Value(r["food_ref"], r["nutrient_id"], r["basis"], parse_amount(r["amount"]),
                    r["qualifier"], r["confidence"], r["source_value"], r["source_nutrient_id"],
                    r["source_unit"], r["licence_group"])
              for r in read_csv(directory / "values.csv")]
    return foods, names, values


def read_canonical(directory: Path) -> tuple[list[Food], list[FoodName], list[Value], dict]:
    """Reads a row set and refuses it if any file changed after its manifest was written."""
    directory = Path(directory)
    manifest = read_json(directory / "manifest.json")
    for name in ROW_FILES:
        actual = sha256_file(directory / name)
        if manifest.get("outputs", {}).get(name) != actual:
            raise CanonicalError(f"{directory}/{name} does not match its manifest "
                                 "(edited after it was written?) — regenerate it")
    return (*read_rows(directory), manifest)
