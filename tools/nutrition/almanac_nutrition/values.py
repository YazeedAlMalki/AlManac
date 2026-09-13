"""Turning one source cell into (amount, qualifier) — Processing Design v0.1 §2.

The most consequential bug available in this project is a one-line type
coercion that turns CoFID's `Tr` or `N` into 0. Every source goes through
`qualify`, which has no path from a non-numeric cell to a number other than
an explicit, bounded `< x`.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any, Sequence

KJ_PER_KCAL = 4.184  # thermochemical calorie
_DECIMAL = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


class UnrecognisedValue(ValueError):
    """A cell no rule covers. The stage fails rather than guess."""


class NegativeAmount(UnrecognisedValue):
    """A published number below zero — not a quantity. Never stored, never clamped to 0.

    Source modules may catch this one case, emit no row, and record the cell in
    their manifest's notes.rejected_values (README "Qualifying a value").
    """


@dataclass(frozen=True)
class Qualified:
    amount: float | None
    qualifier: str


def parse_decimal(text: str, *, decimal_comma: bool = False) -> float | None:
    """A plain finite decimal, or None. Never NaN, never infinity, never a token."""
    s = text.strip()
    if decimal_comma and s.count(",") == 1 and "." not in s:
        s = s.replace(",", ".")
    if not _DECIMAL.fullmatch(s):
        return None
    number = float(s)
    return number if math.isfinite(number) else None


def qualify(cell: str, *, tokens: dict[str, str], numeric_override: str = "",
            derivation_qualifier: str = "", decimal_comma: bool = False,
            bound_prefix: str = "") -> Qualified:
    """The README's seven-step rule, in order. Blank cells never get here."""
    text = cell.strip()
    if not text:
        raise UnrecognisedValue("blank cell reached qualify(); a blank cell produces no row")
    if text in tokens:
        return Qualified(None, tokens[text])
    if bound_prefix and text.startswith(bound_prefix):
        bound = parse_decimal(text[len(bound_prefix):], decimal_comma=decimal_comma)
        if bound is None or bound <= 0:
            raise UnrecognisedValue(f"{cell!r}: a bound must be a positive number")
        return Qualified(bound, "below_loq")
    number = parse_decimal(text, decimal_comma=decimal_comma)
    if number is None:
        raise UnrecognisedValue(f"{cell!r} is neither a number nor a known token")
    if number < 0:
        raise NegativeAmount(f"{cell!r}: a nutrient amount cannot be negative")
    if number == 0:
        return Qualified(0.0, "zero_reported")
    if numeric_override:
        return Qualified(number, numeric_override)
    if derivation_qualifier:
        return Qualified(number, derivation_qualifier)
    return Qualified(number, "measured")


def convert(amount: float | None, conversion: str) -> float | None:
    if amount is None or not conversion:
        return amount
    if conversion == "kj_to_kcal":
        return amount / KJ_PER_KCAL
    raise ValueError(f"unknown unit conversion {conversion!r}")


def select(candidates: Sequence[tuple[int, Qualified, Any]]) -> tuple[int, Qualified, Any] | None:
    """One value where several source columns feed one canonical nutrient.

    `candidates` are (priority, Qualified, payload). The lowest priority that
    carries a quantity wins; if none does, the lowest priority's marker is
    kept rather than dropped.
    """
    ordered = sorted(candidates, key=lambda c: c[0])
    for candidate in ordered:
        if candidate[1].qualifier != "not_analysed":
            return candidate
    return ordered[0] if ordered else None
