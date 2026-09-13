"""The nutrient dictionary, qualifier vocabulary and licence registry — as data.

Processing Design v0.1 §6: the mapping "will be wrong in places on the first
pass. Keeping it as data means fixing it is an update, not a re-extraction."
Nothing in the pipeline hard-codes a nutrient, a qualifier or a licence group;
it all comes from ../dictionary/, cross-checked here.
"""
from __future__ import annotations

import csv
import hashlib
from dataclasses import dataclass
from pathlib import Path

DICTIONARY_DIR = Path(__file__).resolve().parent.parent / "dictionary"
FILES = ("nutrients.csv", "qualifiers.csv", "licence_groups.csv", "sources.csv",
         "nutrient_map.csv", "derivation_qualifiers.csv", "value_tokens.csv")

# unit_conversion name -> (source unit, canonical unit), compared case-insensitively.
# The empty name is the identity: the two units must already agree.
UNIT_CONVERSIONS: dict[str, tuple[str, str] | None] = {"": None, "kj_to_kcal": ("kj", "kcal")}


class DictionaryError(ValueError):
    """The dictionary contradicts itself. The message lists every problem."""


@dataclass(frozen=True)
class Nutrient:
    nutrient_id: str
    infoods_tag: str
    name: str
    unit: str
    description: str


@dataclass(frozen=True)
class Qualifier:
    qualifier: str
    has_quantity: bool
    directly_observed: bool
    amount_rule: str  # "null": amount is always empty; "required": amount is always present
    description: str


@dataclass(frozen=True)
class LicenceGroup:
    licence_group: str
    name: str
    shippable: bool
    description: str


@dataclass(frozen=True)
class Source:
    namespace: str
    dataset_id: str
    name: str
    release: str
    licence: str
    licence_group: str
    attribution: str
    url: str


@dataclass(frozen=True)
class Mapping:
    source: str
    source_nutrient_id: str
    source_nutrient_name: str
    source_unit: str
    nutrient_id: str
    priority: int
    unit_conversion: str
    numeric_qualifier_override: str
    notes: str


@dataclass(frozen=True)
class Dictionary:
    nutrients: dict[str, Nutrient]
    qualifiers: dict[str, Qualifier]
    licence_groups: dict[str, LicenceGroup]
    sources: dict[str, Source]
    mappings: tuple[Mapping, ...]
    derivations: dict[tuple[str, str], str]  # (source, code) -> qualifier
    tokens: dict[tuple[str, str], str]  # (source, exact cell text) -> qualifier
    sha256: str

    @property
    def shippable_groups(self) -> frozenset[str]:
        return frozenset(g for g, row in self.licence_groups.items() if row.shippable)

    def group_of(self, namespace: str) -> str:
        return self.sources[namespace].licence_group

    def mappings_for(self, source: str) -> dict[str, list[Mapping]]:
        """Canonical nutrient -> the source's mappings for it, highest priority first."""
        grouped: dict[str, list[Mapping]] = {}
        for mapping in self.mappings:
            if mapping.source == source:
                grouped.setdefault(mapping.nutrient_id, []).append(mapping)
        return {n: sorted(ms, key=lambda m: m.priority) for n, ms in sorted(grouped.items())}

    def tokens_for(self, source: str) -> dict[str, str]:
        return {token: q for (src, token), q in self.tokens.items() if src == source}

    def derivations_for(self, source: str) -> dict[str, str]:
        return {code: q for (src, code), q in self.derivations.items() if src == source}


def _read(directory: Path, name: str) -> list[dict[str, str]]:
    with open(directory / name, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _flag(text: str, where: str, problems: list[str]) -> bool:
    if text not in ("true", "false"):
        problems.append(f"{where}: expected true or false, got {text!r}")
    return text == "true"


def _digest(directory: Path) -> str:
    digest = hashlib.sha256()
    for name in FILES:
        digest.update(name.encode() + b"\0" + (directory / name).read_bytes() + b"\0")
    return digest.hexdigest()


def load(directory: Path | str = DICTIONARY_DIR) -> Dictionary:
    directory = Path(directory)
    problems: list[str] = []

    nutrients: dict[str, Nutrient] = {}
    for r in _read(directory, "nutrients.csv"):
        if r["nutrient_id"] in nutrients:
            problems.append(f"nutrients.csv: duplicate nutrient_id {r['nutrient_id']}")
        if not r["unit"]:
            problems.append(f"nutrients.csv[{r['nutrient_id']}]: unit is empty")
        nutrients[r["nutrient_id"]] = Nutrient(r["nutrient_id"], r["infoods_tag"], r["name"],
                                               r["unit"], r["description"])

    qualifiers: dict[str, Qualifier] = {}
    for r in _read(directory, "qualifiers.csv"):
        where = f"qualifiers.csv[{r['qualifier']}]"
        if r["qualifier"] in qualifiers:
            problems.append(f"{where}: duplicate")
        if r["amount_rule"] not in ("null", "required"):
            problems.append(f"{where}: amount_rule must be null or required")
        qualifiers[r["qualifier"]] = Qualifier(
            r["qualifier"], _flag(r["has_quantity"], where, problems),
            _flag(r["directly_observed"], where, problems), r["amount_rule"], r["description"])

    groups: dict[str, LicenceGroup] = {}
    for r in _read(directory, "licence_groups.csv"):
        where = f"licence_groups.csv[{r['licence_group']}]"
        if r["licence_group"] in groups:
            problems.append(f"{where}: duplicate")
        groups[r["licence_group"]] = LicenceGroup(r["licence_group"], r["name"],
                                                  _flag(r["shippable"], where, problems),
                                                  r["description"])

    sources: dict[str, Source] = {}
    for r in _read(directory, "sources.csv"):
        where = f"sources.csv[{r['namespace']}]"
        if r["namespace"] in sources:
            problems.append(f"{where}: duplicate")
        if r["licence_group"] not in groups:
            problems.append(f"{where}: unknown licence group {r['licence_group']!r}")
        sources[r["namespace"]] = Source(r["namespace"], r["dataset_id"], r["name"], r["release"],
                                         r["licence"], r["licence_group"], r["attribution"], r["url"])

    mappings: list[Mapping] = []
    seen_ids: set[tuple[str, str]] = set()
    seen_priorities: set[tuple[str, str, int]] = set()
    for r in _read(directory, "nutrient_map.csv"):
        where = f"nutrient_map.csv[{r['source']} {r['source_nutrient_id']}]"
        try:
            priority = int(r["priority"])
        except ValueError:
            problems.append(f"{where}: priority {r['priority']!r} is not an integer")
            continue
        m = Mapping(r["source"], r["source_nutrient_id"], r["source_nutrient_name"], r["source_unit"],
                    r["nutrient_id"], priority, r["unit_conversion"],
                    r["numeric_qualifier_override"], r["notes"])
        if m.source not in sources:
            problems.append(f"{where}: unknown source")
        nutrient = nutrients.get(m.nutrient_id)
        if nutrient is None:
            problems.append(f"{where}: unknown nutrient {m.nutrient_id!r}")
        if (m.source, m.source_nutrient_id) in seen_ids:
            problems.append(f"{where}: mapped twice")
        seen_ids.add((m.source, m.source_nutrient_id))
        if (m.source, m.nutrient_id, m.priority) in seen_priorities:
            problems.append(f"{where}: priority {priority} repeated for {m.nutrient_id}")
        seen_priorities.add((m.source, m.nutrient_id, m.priority))
        if priority < 1:
            problems.append(f"{where}: priority must be 1 or more")
        if m.numeric_qualifier_override and m.numeric_qualifier_override not in qualifiers:
            problems.append(f"{where}: unknown override qualifier {m.numeric_qualifier_override!r}")
        if m.unit_conversion not in UNIT_CONVERSIONS:
            problems.append(f"{where}: unknown unit_conversion {m.unit_conversion!r}")
        elif nutrient is not None:
            conversion = UNIT_CONVERSIONS[m.unit_conversion]
            source_unit, canonical_unit = m.source_unit.lower(), nutrient.unit.lower()
            if conversion is None and source_unit != canonical_unit:
                problems.append(f"{where}: source unit {m.source_unit!r} is not {nutrient.unit!r} "
                                "and no unit_conversion is given")
            if conversion is not None and conversion != (source_unit, canonical_unit):
                problems.append(f"{where}: {m.unit_conversion} converts {conversion[0]} to "
                                f"{conversion[1]}, not {source_unit} to {canonical_unit}")
        mappings.append(m)

    derivations: dict[tuple[str, str], str] = {}
    for r in _read(directory, "derivation_qualifiers.csv"):
        where = f"derivation_qualifiers.csv[{r['source']} {r['code']!r}]"
        if r["source"] not in sources:
            problems.append(f"{where}: unknown source")
        if r["qualifier"] not in qualifiers:
            problems.append(f"{where}: unknown qualifier {r['qualifier']!r}")
        if (r["source"], r["code"]) in derivations:
            problems.append(f"{where}: duplicate")
        derivations[(r["source"], r["code"])] = r["qualifier"]

    tokens: dict[tuple[str, str], str] = {}
    for r in _read(directory, "value_tokens.csv"):
        where = f"value_tokens.csv[{r['source']} {r['token']!r}]"
        if r["source"] not in sources:
            problems.append(f"{where}: unknown source")
        qualifier = qualifiers.get(r["qualifier"])
        if qualifier is None:
            problems.append(f"{where}: unknown qualifier {r['qualifier']!r}")
        elif qualifier.amount_rule != "null":
            # A token carries no number. Mapping one to a qualifier that needs an
            # amount would force the pipeline to invent one — which is the bug.
            problems.append(f"{where}: a token may only map to a qualifier with no amount, "
                            f"not {r['qualifier']!r}")
        if r["token"] != r["token"].strip() or not r["token"]:
            problems.append(f"{where}: token must be non-empty and trimmed")
        if (r["source"], r["token"]) in tokens:
            problems.append(f"{where}: duplicate")
        tokens[(r["source"], r["token"])] = r["qualifier"]

    if problems:
        raise DictionaryError(f"{len(problems)} problem(s) in {directory}:\n  " + "\n  ".join(problems))
    return Dictionary(nutrients, qualifiers, groups, sources, tuple(mappings), derivations, tokens,
                      _digest(directory))
