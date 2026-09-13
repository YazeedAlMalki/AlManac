"""python3 -m almanac_nutrition <command> — see ../README.md."""
from __future__ import annotations

import argparse
import json
import sys

from . import bundle, fixture, qa
from .canonical_io import CanonicalError
from .dictionary import DictionaryError, load
from .lake import InputVerificationError, Lake
from .licence import LicenceViolation
from .sources import load_sources

FAILURES = (CanonicalError, DictionaryError, InputVerificationError, LicenceViolation)


def _summary(manifest: dict) -> str:
    c = manifest["counts"]
    return (f"{c['foods']} foods, {c['names']} names, {c['values']} values; "
            f"qualifiers {json.dumps(c['values_by_qualifier'])}")


def main(argv: list[str] | None = None) -> int:
    sources = load_sources()
    parser = argparse.ArgumentParser(prog="almanac_nutrition", description=__doc__)
    parser.add_argument("--lake", help="food-data lake root "
                                       "(default: $ALMANAC_FOOD_DATA or ~/ALManac-food-data)")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("extract", "canonicalise"):
        commands.add_parser(name).add_argument("source", choices=sorted(sources))
    commands.add_parser("union")
    commands.add_parser("bundle")
    commands.add_parser("all", help="extract and canonicalise every source, then union and bundle")
    commands.add_parser("qa", help="re-read every raw cell and check the canonical, union and bundle stages")
    commands.add_parser("fixture", help="regenerate fixtures/bundle_v1.sql for AlmanacCore's tests")
    args = parser.parse_args(argv)

    lake = Lake(args.lake)
    try:
        dictionary = load()
        if args.command == "extract":
            print(f"extracted {args.source} -> {sources[args.source].extract(lake)}")
        elif args.command == "canonicalise":
            print(f"canonical {args.source}: {_summary(sources[args.source].canonicalise(lake, dictionary))}")
        elif args.command == "union":
            print(f"union: {_summary(bundle.union(lake, dictionary))}")
        elif args.command == "fixture":
            print(f"fixture -> {fixture.write(dictionary)}")
        elif args.command == "qa":
            report = qa.run(lake, dictionary)
            print(qa.summary(report))
            return 0 if report["passed"] else 1
        elif args.command == "bundle":
            report = bundle.build(lake, dictionary)
            print(f"bundle {report['path']} ({', '.join(report['namespaces'])}): "
                  f"{report['rows_checked']} rows passed the licence assertion; sha256 {report['sha256']}")
        else:
            for namespace, module in sources.items():
                module.extract(lake)
                print(f"canonical {namespace}: {_summary(module.canonicalise(lake, dictionary))}")
            print(f"union: {_summary(bundle.union(lake, dictionary))}")
            report = bundle.build(lake, dictionary)
            print(f"bundle {report['path']}: {report['rows_checked']} rows passed the licence "
                  f"assertion; sha256 {report['sha256']}")
    except FAILURES as error:
        print(f"FAILED: {error}", file=sys.stderr)
        return 1
    return 0
