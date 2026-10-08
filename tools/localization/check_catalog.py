#!/usr/bin/env python3
"""Every string the compiler extracted from the app and the widget, checked
against their String Catalogs for an Arabic value (#4).

The keys come from the compiler, not from reading the source: built with
SWIFT_EMIT_LOC_STRINGS=YES, Xcode writes a .stringsdata file per Swift file
listing each localizable literal exactly as SwiftUI will look it up, with
interpolations already turned into %lld / %@ / %lf by their real types. A key
guessed by hand from the source gets those wrong, and a wrong key is a string
that silently stays English.

    check_catalog.py DERIVED_DATA [--strict]

Prints one line per untranslated key, `MISSING<TAB>catalog<TAB>key<TAB>file:line`,
as JSON-escaped strings so a key with a tab or newline stays on its line, and
one `SPECIFIERS` line per Arabic value whose format specifiers differ from its
key's, then a summary. A specifier mismatch always exits 1; with --strict, so
does anything missing.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Source directory -> the catalog its target ships. A widget extension reads
# its own bundle, never the app's, so it needs a catalog of its own.
CATALOGS = {
    "Native/Almanac/": "Native/Almanac/Localizable.xcstrings",
    "Native/AlmanacWidgets/": "Native/AlmanacWidgets/Localizable.xcstrings",
}
LANGUAGE = "ar"


def translated(catalog_path):
    path = os.path.join(ROOT, catalog_path)
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        strings = json.load(f).get("strings", {})
    done = set()
    for key, entry in strings.items():
        unit = entry.get("localizations", {}).get(LANGUAGE, {}).get("stringUnit", {})
        if unit.get("value", "").strip():
            done.add(key)
        # A plural or device variation counts when any of its forms is filled.
        elif entry.get("localizations", {}).get(LANGUAGE, {}).get("variations"):
            done.add(key)
    return done


SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcs%]")


def specifiers(text):
    """Format specifiers without positions: a translation may reorder them."""
    return sorted(re.sub(r"\d+\$", "", s) for s in SPECIFIER.findall(text) if s != "%%")


def mismatched(catalog_path):
    """Arabic values whose specifiers differ from their key's. A %lld turned
    into %@ is a crash, and a dropped one a wrong sentence, so these fail the
    build whatever the mode. Plural forms are exempt: "one" may say the
    number in words."""
    path = os.path.join(ROOT, catalog_path)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        strings = json.load(f).get("strings", {})
    bad = []
    for key, entry in strings.items():
        value = entry.get("localizations", {}).get(LANGUAGE, {}).get("stringUnit", {}).get("value")
        if value is not None and specifiers(value) != specifiers(key):
            bad.append((catalog_path, key, value))
    return bad


def extracted(derived_data):
    """(catalog, key, where) for every literal in a Localizable table."""
    seen = set()
    for directory, _, files in os.walk(derived_data):
        for name in files:
            if not name.endswith(".stringsdata"):
                continue
            with open(os.path.join(directory, name), encoding="utf-8") as f:
                try:
                    data = json.load(f)
                except ValueError:
                    continue
            source = data.get("source", "")
            catalog = next((c for d, c in CATALOGS.items() if "/" + d in source), None)
            if catalog is None:
                continue
            relative = source[source.find("Native/"):]
            for table, entries in data.get("tables", {}).items():
                if table != "Localizable":
                    continue
                for entry in entries:
                    key = entry.get("key")
                    if key is None:
                        continue
                    line = entry.get("location", {}).get("startingLine", 0)
                    seen.add((catalog, key, f"{relative}:{line}"))
    return seen


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    strict = "--strict" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    found = extracted(args[0])
    if not found:
        sys.exit("no .stringsdata found: was the build run with SWIFT_EMIT_LOC_STRINGS=YES?")
    done = {catalog: translated(catalog) for catalog in set(CATALOGS.values())}
    missing = sorted((c, k, w) for c, k, w in found if k not in done[c])
    for catalog, key, where in missing:
        print("MISSING\t%s\t%s\t%s" % (catalog, json.dumps(key, ensure_ascii=False), where))
    keys = {(c, k) for c, k, _ in found}
    untranslated = {(c, k) for c, k, _ in missing}
    bad = [b for catalog in sorted(set(CATALOGS.values())) for b in mismatched(catalog)]
    for catalog, key, value in bad:
        print("SPECIFIERS\t%s\t%s\t%s" % (catalog, json.dumps(key, ensure_ascii=False),
                                          json.dumps(value, ensure_ascii=False)))
    print(f"localizable keys: {len(keys)}; without Arabic: {len(untranslated)}; "
          f"specifier mismatches: {len(bad)}")
    if bad or (strict and missing):
        sys.exit(1)


if __name__ == "__main__":
    main()
