"""The bundle's licence assertion — Processing Design v0.1 §1 and §5.

Putting a food row in the bundle is redistributing it to every user who
installs the app. So the build does not filter restricted rows out; it fails.
"""
from __future__ import annotations

from typing import Collection, Iterable


class LicenceViolation(RuntimeError):
    """BUILD FAILURE: a row outside the shippable licence groups reached the bundle step."""


def assert_shippable(rows: Iterable[tuple[str, str]], shippable: Collection[str]) -> int:
    """Raises unless every (identifier, licence group) is shippable. Returns rows checked."""
    offenders: list[tuple[str, str]] = []
    checked = 0
    for identifier, group in rows:
        checked += 1
        if group not in shippable:
            offenders.append((identifier, group))
    if offenders:
        sample = ", ".join(f"{identifier} (group {group})" for identifier, group in offenders[:10])
        raise LicenceViolation(
            f"BUILD FAILURE: {len(offenders)} row(s) outside licence groups "
            f"{', '.join(sorted(shippable))} must never enter the bundle: {sample}")
    return checked
