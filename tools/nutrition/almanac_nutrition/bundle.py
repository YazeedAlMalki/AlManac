"""union and bundle — Processing Design v0.1 §5.

union   Every canonical source present, re-validated and licence-tagged. It
        may one day hold Group C or D rows: it is a local research artefact.
bundle  The only filter, and it filters by asserting. Every row's licence
        group must be shippable (A, B or N) and must agree with sources.csv,
        or the build fails before a byte of output exists.
"""
from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path

from .canonical_io import (CanonicalError, counts, raise_if_invalid, read_canonical, write_rows)
from .dictionary import Dictionary
from .lake import Lake, sha256_file, staged_directory, tool_revision, utc_now, write_json
from .licence import LicenceViolation, assert_shippable
from .model import BASES, validate

SCHEMA_VERSION = 1


def _sql_list(items) -> str:
    return ", ".join(f"'{item}'" for item in sorted(items))


def schema_sql(dictionary: Dictionary) -> str:
    """Bundle schema v1. AlmanacCore's Migration008 mirrors these tables."""
    groups = _sql_list(dictionary.shippable_groups)
    no_amount = _sql_list(q for q, row in dictionary.qualifiers.items() if row.amount_rule == "null")
    return f"""
CREATE TABLE bundle_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;
CREATE TABLE nutrition_source (
    namespace     TEXT PRIMARY KEY,
    dataset_id    TEXT NOT NULL,
    name          TEXT NOT NULL,
    release       TEXT NOT NULL,
    licence       TEXT NOT NULL,
    licence_group TEXT NOT NULL CHECK (licence_group IN ({groups})),
    attribution   TEXT NOT NULL,
    url           TEXT NOT NULL
) STRICT;
CREATE TABLE nutrition_nutrient (
    nutrient_id TEXT PRIMARY KEY,
    infoods_tag TEXT NOT NULL,
    name        TEXT NOT NULL,
    unit        TEXT NOT NULL,
    description TEXT NOT NULL
) STRICT;
CREATE TABLE nutrition_qualifier (
    qualifier         TEXT PRIMARY KEY,
    has_quantity      INTEGER NOT NULL CHECK (has_quantity IN (0, 1)),
    directly_observed INTEGER NOT NULL CHECK (directly_observed IN (0, 1)),
    amount_rule       TEXT NOT NULL CHECK (amount_rule IN ('null', 'required')),
    description       TEXT NOT NULL
) STRICT;
CREATE TABLE nutrition_food (
    food_ref        TEXT PRIMARY KEY,
    namespace       TEXT NOT NULL REFERENCES nutrition_source (namespace),
    local_id        TEXT NOT NULL,
    licence_group   TEXT NOT NULL CHECK (licence_group IN ({groups})),
    food_group_code TEXT NOT NULL,
    food_group_name TEXT NOT NULL,
    source_record   TEXT NOT NULL,
    UNIQUE (namespace, local_id),
    CHECK (food_ref = namespace || ':' || local_id)
) STRICT;
CREATE TABLE nutrition_food_name (
    food_ref   TEXT NOT NULL REFERENCES nutrition_food (food_ref),
    language   TEXT NOT NULL,
    name       TEXT NOT NULL CHECK (name <> ''),
    is_primary INTEGER NOT NULL CHECK (is_primary IN (0, 1)),
    PRIMARY KEY (food_ref, language)
) STRICT;
CREATE TABLE nutrition_value (
    food_ref           TEXT NOT NULL REFERENCES nutrition_food (food_ref),
    nutrient_id        TEXT NOT NULL REFERENCES nutrition_nutrient (nutrient_id),
    basis              TEXT NOT NULL CHECK (basis IN ({_sql_list(BASES)})),
    amount             REAL CHECK (amount IS NULL OR amount >= 0),
    qualifier          TEXT NOT NULL REFERENCES nutrition_qualifier (qualifier),
    confidence         TEXT,
    source_value       TEXT NOT NULL CHECK (source_value <> ''),
    source_nutrient_id TEXT NOT NULL,
    source_unit        TEXT NOT NULL,
    licence_group      TEXT NOT NULL CHECK (licence_group IN ({groups})),
    PRIMARY KEY (food_ref, nutrient_id, basis),
    CHECK ((qualifier IN ({no_amount})) = (amount IS NULL)),
    CHECK (qualifier <> 'zero_reported' OR amount = 0)
) STRICT;
"""


def union(lake: Lake, dictionary: Dictionary) -> dict:
    """Concatenates every canonical/{namespace}/ present. Deleting one removes that source."""
    root = lake.canonical_root
    present = sorted(p.name for p in root.iterdir()
                     if p.is_dir() and not p.name.startswith(".")) if root.is_dir() else []
    if not present:
        raise CanonicalError(f"{root}: no canonical sources to union")
    foods, names, values, sources = [], [], [], {}
    for namespace in present:
        if namespace not in dictionary.sources:
            raise CanonicalError(f"canonical/{namespace}: namespace is not in dictionary/sources.csv")
        f, n, v, manifest = read_canonical(root / namespace)
        if manifest.get("namespace") != namespace:
            raise CanonicalError(f"canonical/{namespace}: manifest names {manifest.get('namespace')!r}")
        if manifest.get("dictionary_sha256") != dictionary.sha256:
            raise CanonicalError(f"canonical/{namespace} was built against a different dictionary; "
                                 f"re-run `canonicalise {namespace}`")
        raise_if_invalid(validate(f, n, v, dictionary, namespace=namespace), f"canonical/{namespace}")
        foods += f
        names += n
        values += v
        sources[namespace] = {"release": manifest["release"],
                              "manifest_sha256": sha256_file(root / namespace / "manifest.json"),
                              "counts": manifest["counts"]}
    raise_if_invalid(validate(foods, names, values, dictionary), "union")
    with staged_directory(lake.union) as scratch:
        manifest = {
            "stage": "union",
            "sources": sources,
            "dictionary_sha256": dictionary.sha256,
            "generated_at": utc_now(),
            "tool_revision": tool_revision(),
            "outputs": write_rows(scratch, foods, names, values),
            "counts": counts(foods, names, values),
        }
        write_json(scratch / "manifest.json", manifest)
    return manifest


def _verify_written(con: sqlite3.Connection, shippable: frozenset[str]) -> None:
    """Second assertion, against what is actually in the file."""
    for table in ("nutrition_source", "nutrition_food", "nutrition_value"):
        for (group,) in con.execute(f"SELECT DISTINCT licence_group FROM {table}"):
            if group not in shippable:
                raise LicenceViolation(f"BUILD FAILURE: {table} contains licence group {group!r}")
    if (result := con.execute("PRAGMA integrity_check").fetchone()[0]) != "ok":
        raise CanonicalError(f"bundle integrity_check: {result}")
    if violations := con.execute("PRAGMA foreign_key_check").fetchall():
        raise CanonicalError(f"bundle foreign_key_check: {violations[:5]}")


def build(lake: Lake, dictionary: Dictionary, out_path: Path | None = None) -> dict:
    out_path = Path(out_path or lake.bundle)
    foods, names, values, union_manifest = read_canonical(lake.union)
    if union_manifest.get("dictionary_sha256") != dictionary.sha256:
        raise CanonicalError("processed/union was built against a different dictionary; re-run union")
    raise_if_invalid(validate(foods, names, values, dictionary), "union")

    # The assertion. Nothing has been written yet.
    shippable = dictionary.shippable_groups
    checked = assert_shippable(((f.food_ref, f.licence_group) for f in foods), shippable)
    checked += assert_shippable((("/".join((v.food_ref, v.nutrient_id, v.basis)), v.licence_group)
                                 for v in values), shippable)
    namespaces = sorted({f.namespace for f in foods})
    assert_shippable(((ns, dictionary.group_of(ns)) for ns in namespaces), shippable)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    scratch = out_path.with_name(f".{out_path.name}.partial")
    scratch.unlink(missing_ok=True)
    built_at = utc_now()
    meta = {
        "schema_version": str(SCHEMA_VERSION),
        "dictionary_sha256": dictionary.sha256,
        "built_at": built_at,
        "tool_revision": tool_revision(),
        "union_manifest_sha256": sha256_file(lake.union / "manifest.json"),
        "sources": json.dumps({ns: dictionary.sources[ns].release for ns in namespaces},
                              sort_keys=True),
    }
    try:
        con = sqlite3.connect(scratch)
        try:
            con.execute("PRAGMA foreign_keys = ON")
            con.executescript(schema_sql(dictionary))
            with con:
                con.executemany("INSERT INTO bundle_meta VALUES (?, ?)", sorted(meta.items()))
                con.executemany("INSERT INTO nutrition_source VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
                    (s.namespace, s.dataset_id, s.name, s.release, s.licence, s.licence_group,
                     s.attribution, s.url)
                    for s in (dictionary.sources[ns] for ns in namespaces)])
                con.executemany("INSERT INTO nutrition_nutrient VALUES (?, ?, ?, ?, ?)", [
                    (n.nutrient_id, n.infoods_tag, n.name, n.unit, n.description)
                    for n in dictionary.nutrients.values()])
                con.executemany("INSERT INTO nutrition_qualifier VALUES (?, ?, ?, ?, ?)", [
                    (q.qualifier, int(q.has_quantity), int(q.directly_observed), q.amount_rule,
                     q.description)
                    for q in dictionary.qualifiers.values()])
                con.executemany("INSERT INTO nutrition_food VALUES (?, ?, ?, ?, ?, ?, ?)", [
                    (f.food_ref, f.namespace, f.local_id, f.licence_group, f.food_group_code,
                     f.food_group_name, f.source_record)
                    for f in sorted(foods, key=lambda f: f.food_ref)])
                con.executemany("INSERT INTO nutrition_food_name VALUES (?, ?, ?, ?)", [
                    (n.food_ref, n.language, n.name, int(n.is_primary))
                    for n in sorted(names, key=lambda n: (n.food_ref, n.language))])
                con.executemany("INSERT INTO nutrition_value VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
                    (v.food_ref, v.nutrient_id, v.basis, v.amount, v.qualifier, v.confidence or None,
                     v.source_value, v.source_nutrient_id, v.source_unit, v.licence_group)
                    for v in sorted(values, key=lambda v: (v.food_ref, v.nutrient_id, v.basis))])
            _verify_written(con, shippable)
            con.execute("VACUUM")
        finally:
            con.close()
        os.replace(scratch, out_path)
    except BaseException:
        scratch.unlink(missing_ok=True)
        raise
    return {
        "path": str(out_path),
        "sha256": sha256_file(out_path),
        "schema_version": SCHEMA_VERSION,
        "built_at": built_at,
        "namespaces": namespaces,
        "rows_checked": checked,
        "counts": counts(foods, names, values),
    }
