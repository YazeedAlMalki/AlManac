"""Wikibooks Cookbook → Kitchen recipe bundle.

    python3 -m almanac_recipes fetch            # pages into the food-data lake
    python3 -m almanac_recipes build            # lake → Sources/.../wikibooks-recipes.json
    python3 -m almanac_recipes review           # what each ingredient row converts to

The lake is ~/ALManac-food-data (override with ALMANAC_FOOD_DATA), the same
one tools/nutrition reads. Fetched pages stay there, never in the repository.
"""

from __future__ import annotations

import argparse
import collections
import csv
import datetime
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from . import build

REPO = Path(__file__).resolve().parents[3]
BUNDLE_DB = REPO / "Sources/AlmanacCore/Nutrition/Resources/almanac.sqlite"
OUTPUT = REPO / "Sources/AlmanacCore/Kitchen/Resources/wikibooks-recipes.json"
TABLE = Path(__file__).resolve().parents[1] / "ingredients.csv"
USDA = "raw/usda/FoodData_Central_csv_2026-04-30"
API = "https://en.wikibooks.org/w/api.php"
USER_AGENT = "AlmanacRecipeImport/1.0 (one-off import of CC BY-SA recipes; python urllib)"


def lake() -> Path:
    return Path(os.environ.get("ALMANAC_FOOD_DATA") or Path.home() / "ALManac-food-data")


def fetch(out: Path) -> None:
    """Every page in Category:Recipes with its current wikitext and revision
    id, through the MediaWiki API, paced and backing off on 429."""
    out.mkdir(parents=True, exist_ok=True)
    params = {"action": "query", "format": "json", "formatversion": "2",
              "generator": "categorymembers", "gcmtitle": "Category:Recipes",
              "gcmnamespace": "102", "gcmlimit": "50", "prop": "revisions",
              "rvprop": "ids|timestamp|content", "rvslots": "main", "maxlag": "5"}
    cont: dict = {}
    pages: dict[int, dict] = {}
    while True:
        query = dict(params, **cont)
        request = urllib.request.Request(API + "?" + urllib.parse.urlencode(query),
                                         headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                data = json.load(response)
        except urllib.error.HTTPError as error:
            wait = max(int(error.headers.get("Retry-After") or 30), 30)
            print(f"HTTP {error.code}; waiting {wait} s", flush=True)
            time.sleep(wait)
            continue
        for page in data.get("query", {}).get("pages", []):
            if page.get("revisions"):
                pages[page["pageid"]] = page
        print(f"{len(pages)} pages", flush=True)
        if "continue" not in data:
            break
        cont = data["continue"]
        time.sleep(4)
    (out / "pages.json").write_text(json.dumps(sorted(pages.values(), key=lambda p: p["pageid"])))


def usda_portions(root: Path) -> tuple[dict[str, list[tuple[float, str, float]]], dict[str, str]]:
    folder = root / USDA
    names = {r["fdc_id"]: r["description"] for r in csv.DictReader(open(folder / "food.csv"))
             if r["data_type"] == "sr_legacy_food"}
    portions: dict[str, list] = collections.defaultdict(list)
    for r in csv.DictReader(open(folder / "food_portion.csv")):
        if r["fdc_id"] in names and r["modifier"]:
            portions[r["fdc_id"]].append((float(r["amount"]), r["modifier"], float(r["gram_weight"])))
    return portions, names


def bundle_names() -> dict[str, str]:
    with sqlite3.connect(f"file:{BUNDLE_DB}?mode=ro", uri=True) as db:
        return dict(db.execute("SELECT food_ref, name FROM nutrition_food_name WHERE is_primary = 1"))


def load(root: Path):
    portions, usda_names = usda_portions(root)
    foods = bundle_names()
    index, problems = build.load_ingredients(TABLE, portions, foods)
    return index, problems, foods, usda_names


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="almanac_recipes")
    parser.add_argument("command", choices=["fetch", "build", "review"])
    parser.add_argument("--snapshot", default="2026-10-16", help="lake folder under raw/wikibooks/")
    parser.add_argument("--allow-excluded", action="store_true",
                        help="keep recipes with pork or alcohol (CONTEXT.md, Kitchen recipes)")
    args = parser.parse_args(argv)
    root = lake()
    snapshot = root / "raw/wikibooks" / args.snapshot
    if args.command == "fetch":
        fetch(snapshot)
        return 0
    index, problems, foods, usda_names = load(root)
    if args.command == "review":
        seen = set()
        for ing in index.values():
            if id(ing) in seen:
                continue
            seen.add(id(ing))
            per_cup = f"{ing.grams_per_ml * 236.588:.0f} g/cup" if ing.grams_per_ml else "-"
            each = f"{ing.each_portions['default']:.0f} g each ({ing.each_default})" if ing.each_portions else "-"
            print(f"{ing.aliases[0]:28} {foods.get(ing.food_ref, '??')[:45]:45} | "
                  f"{usda_names.get(ing.usda_fdc, '-')[:40]:40} | {per_cup} | {each}")
    for problem in problems:
        print("PROBLEM:", problem, file=sys.stderr)
    if problems:
        return 1
    if args.command == "build":
        pages = json.loads((snapshot / "pages.json").read_text())
        bundle, stats = build.build(pages, index, args.snapshot, args.allow_excluded)
        build.write(bundle, OUTPUT)
        print(json.dumps(stats))
        print(f"wrote {len(bundle['recipes'])} recipes to {OUTPUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
