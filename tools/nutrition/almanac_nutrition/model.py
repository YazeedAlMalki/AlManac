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


# Processing Design v0.1 §4: household-measure-to-gram conversion is solved for group A/B
# without the (group D) FAO density database — USDA's food_portion and CoFID's Factors sheet.
PORTION_KINDS = ("household_measure", "specific_gravity", "edible_proportion")
PORTION_UNITS = {"specific_gravity": "g_per_ml", "edible_proportion": "fraction"}  # fixed units; household_measure's unit is the measure name


@dataclass(frozen=True)
class Portion:
    """A fact that converts a real-world measure toward grams.

    `household_measure` (USDA `food_portion`): `amount` of `unit` (a named
    measure, e.g. "cup") weighs `value` grams. `specific_gravity` (CoFID
    "1.2 Factors"): the food's density, `value` g per mL — converts a volume
    measure to grams for any food, not just ones with a listed household
    measure. `edible_proportion` (CoFID): the fraction of a gross/purchased
    weight that is edible, for a measure reported whole (skin, core, bone).
    """
    food_ref: str
    kind: str
    unit: str
    amount: float | None
    value: float | None
    qualifier: str
    confidence: str
    source_value: str
    source_unit: str
    description: str
    modifier: str
    source_record: str
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


def validate_portions(foods: Sequence[Food], portions: Sequence[Portion], dictionary: Dictionary,
                      *, namespace: str | None = None) -> list[str]:
    """Portion rules, independent of `validate` so a source with none is unaffected."""
    problems: list[str] = []
    foods_by_ref = {f.food_ref: f for f in foods}
    seen: set[tuple[str, str, str]] = set()
    for p in portions:
        where = f"portion {p.food_ref}/{p.kind}/{p.source_record}"
        food = foods_by_ref.get(p.food_ref)
        if food is None:
            problems.append(f"{where}: unknown food")
            continue
        if namespace is not None and food.namespace != namespace:
            problems.append(f"{where}: namespace {food.namespace!r} in canonical/{namespace}")
        if p.kind not in PORTION_KINDS:
            problems.append(f"{where}: kind must be one of {PORTION_KINDS}")
        elif p.kind in PORTION_UNITS and p.unit != PORTION_UNITS[p.kind]:
            problems.append(f"{where}: unit must be {PORTION_UNITS[p.kind]!r} for {p.kind}, got {p.unit!r}")
        qualifier = dictionary.qualifiers.get(p.qualifier)
        if qualifier is None:
            problems.append(f"{where}: unknown qualifier {p.qualifier!r}")
        elif qualifier.amount_rule == "null" and p.value is not None:
            problems.append(f"{where}: {p.qualifier} must have no value, got {p.value!r} "
                            "— a token is never coerced to a number")
        elif qualifier.amount_rule == "required" and p.value is None:
            problems.append(f"{where}: {p.qualifier} requires a value")
        if p.value is not None and not math.isfinite(p.value):
            problems.append(f"{where}: value {p.value!r} is not finite")
        if p.value is not None and p.kind != "edible_proportion" and p.value < 0:
            problems.append(f"{where}: value {p.value!r} is not a finite non-negative number")
        if p.kind == "edible_proportion" and p.value is not None and not (0 < p.value <= 1):
            problems.append(f"{where}: edible_proportion {p.value!r} must be in (0, 1]")
        if p.qualifier == "zero_reported" and p.value != 0:
            problems.append(f"{where}: zero_reported with value {p.value!r}")
        if p.value == 0 and parse_decimal(p.source_value, decimal_comma=True) != 0:
            problems.append(f"{where}: value 0 from source cell {p.source_value!r} "
                            "— only an explicit zero may become 0")
        if p.kind == "household_measure":
            if p.amount is None or p.amount <= 0:
                problems.append(f"{where}: household_measure requires a positive amount")
            if not p.unit.strip():
                problems.append(f"{where}: household_measure requires a unit")
        elif p.amount is not None:
            problems.append(f"{where}: {p.kind} must have no amount — it is a food-level factor, "
                            "not a quantity of a unit")
        if not p.source_value.strip():
            problems.append(f"{where}: source_value is empty")
        if p.licence_group != food.licence_group:
            problems.append(f"{where}: licence group {p.licence_group!r} differs from its food's "
                            f"{food.licence_group!r}")
        key = (p.food_ref, p.kind, p.source_record)
        if key in seen:
            problems.append(f"{where}: duplicate portion")
        seen.add(key)
    return problems
