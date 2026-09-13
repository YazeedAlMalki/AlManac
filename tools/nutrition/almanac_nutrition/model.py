"""Canonical rows (Processing Design v0.1 §2–§4) and the checks every stage runs on them."""
from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass
from typing import Sequence

from .dictionary import Dictionary
from .values import parse_decimal

BASES = ("per_100g", "per_100ml")
_LANGUAGE = re.compile(r"[a-z]{2,3}")


@dataclass(frozen=True)
class Food:
    namespace: str
    local_id: str
    licence_group: str
    food_group_code: str
    food_group_name: str
    source_record: str

    @property
    def food_ref(self) -> str:
        return f"{self.namespace}:{self.local_id}"


@dataclass(frozen=True)
class FoodName:
    food_ref: str
    language: str
    name: str
    is_primary: bool


@dataclass(frozen=True)
class Value:
    food_ref: str
    nutrient_id: str
    basis: str
    amount: float | None
    qualifier: str
    confidence: str
    source_value: str
    source_nutrient_id: str
    source_unit: str
    licence_group: str


def validate(foods: Sequence[Food], names: Sequence[FoodName], values: Sequence[Value],
             dictionary: Dictionary, *, namespace: str | None = None) -> list[str]:
    """Every rule a canonical row set must satisfy. An empty list means valid.

    `namespace` confines the set to one source (the canonical stage); the
    union stage passes None and every row is checked against its own source.
    """
    problems: list[str] = []

    foods_by_ref: dict[str, Food] = {}
    for f in foods:
        where = f"food {f.food_ref}"
        if namespace is not None and f.namespace != namespace:
            problems.append(f"{where}: namespace {f.namespace!r} in canonical/{namespace}")
        if f.namespace not in dictionary.sources:
            problems.append(f"{where}: namespace {f.namespace!r} is not in sources.csv")
            continue
        if not f.local_id or f.local_id != f.local_id.strip():
            problems.append(f"{where}: local_id must be non-empty and trimmed")
        if f.licence_group != dictionary.group_of(f.namespace):
            problems.append(f"{where}: licence group {f.licence_group!r}, but sources.csv says "
                            f"{dictionary.group_of(f.namespace)!r}")
        if f.food_ref in foods_by_ref:
            problems.append(f"{where}: duplicate food_ref")
        foods_by_ref[f.food_ref] = f

    primaries: Counter[str] = Counter()
    seen_names: set[tuple[str, str]] = set()
    for n in names:
        where = f"name {n.food_ref}/{n.language}"
        if n.food_ref not in foods_by_ref:
            problems.append(f"{where}: unknown food")
        if not _LANGUAGE.fullmatch(n.language):
            problems.append(f"{where}: language must be a lower-case ISO 639 code")
        if not n.name.strip():
            problems.append(f"{where}: empty name")
        if (n.food_ref, n.language) in seen_names:
            problems.append(f"{where}: two names in one language")
        seen_names.add((n.food_ref, n.language))
        primaries[n.food_ref] += n.is_primary
    for ref in foods_by_ref:
        if primaries[ref] != 1:
            problems.append(f"food {ref}: {primaries[ref]} primary names, needs exactly 1")

    seen_values: set[tuple[str, str, str]] = set()
    for v in values:
        where = f"value {v.food_ref}/{v.nutrient_id}/{v.basis}"
        food = foods_by_ref.get(v.food_ref)
        if food is None:
            problems.append(f"{where}: unknown food")
            continue
        if v.nutrient_id not in dictionary.nutrients:
            problems.append(f"{where}: unknown nutrient")
        if v.basis not in BASES:
            problems.append(f"{where}: basis must be one of {BASES}")
        qualifier = dictionary.qualifiers.get(v.qualifier)
        if qualifier is None:
            problems.append(f"{where}: unknown qualifier {v.qualifier!r}")
        elif qualifier.amount_rule == "null" and v.amount is not None:
            problems.append(f"{where}: {v.qualifier} must have no amount, got {v.amount!r} "
                            "— a token is never coerced to a number")
        elif qualifier.amount_rule == "required" and v.amount is None:
            problems.append(f"{where}: {v.qualifier} requires an amount")
        if v.amount is not None and (not math.isfinite(v.amount) or v.amount < 0):
            problems.append(f"{where}: amount {v.amount!r} is not a finite non-negative number")
        if v.qualifier == "zero_reported" and v.amount != 0:
            problems.append(f"{where}: zero_reported with amount {v.amount!r}")
        # Independent of the qualifier logic: only a cell that says zero may become 0.
        if v.amount == 0 and parse_decimal(v.source_value, decimal_comma=True) != 0:
            problems.append(f"{where}: amount 0 from source cell {v.source_value!r} "
                            "— only an explicit zero may become 0")
        if not v.source_value.strip():
            problems.append(f"{where}: source_value is empty")
        if not v.source_nutrient_id or not v.source_unit:
            problems.append(f"{where}: source_nutrient_id and source_unit are required")
        if v.licence_group != food.licence_group:
            problems.append(f"{where}: licence group {v.licence_group!r} differs from its food's "
                            f"{food.licence_group!r}")
        key = (v.food_ref, v.nutrient_id, v.basis)
        if key in seen_values:
            problems.append(f"{where}: duplicate value")
        seen_values.add(key)

    return problems
