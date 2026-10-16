"""Turns fetched Wikibooks Cookbook pages into the recipe bundle Kitchen ships.

Every ingredient line must resolve to a catalog food and a weight in grams,
or be a seasoning that can be set aside ("salt, to taste", "a pinch of
nutmeg"). A recipe with any other line is left out whole: the owner's rule,
"drop recipes that do not parse rather than guess"
(docs/features/recipe-sources.md).

Weights: a mass unit converts exactly. A volume or a count converts through
the USDA SR Legacy household measure named for that ingredient in
ingredients.csv ("1 cup, chopped" onion = 160 g). USDA data is public domain.
"""

from __future__ import annotations

import csv
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from . import wikitext
from .wikitext import GRAMS, ML

SIZES = ("extra large", "large", "medium", "small")
# A count of these is a count of the container or part, not of the food.
COUNT_NOUNS = {
    "can", "tin", "jar", "package", "packet", "pack", "head", "bunch", "handful",
    "sprig", "stick", "slice", "clove", "stalk", "rib", "block", "bag", "box",
    "bottle", "envelope", "sheet", "cube", "leaf", "piece", "fillet", "ear", "pod",
    "strip", "rasher", "knob", "drop", "carton", "container", "loaf", "bulb",
    "wedge", "square", "scoop", "glass", "bar", "pat", "sachet", "dollop", "splash",
}
# Words that describe how an ingredient is prepared or chosen, never what it is.
PREP = {
    "fresh", "freshly", "chopped", "finely", "coarsely", "roughly", "minced",
    "diced", "sliced", "thinly", "grated", "ground", "crushed", "peeled", "cubed",
    "shredded", "melted", "softened", "cold", "chilled", "ripe", "beaten",
    "lightly", "well", "squeezed", "juiced", "trimmed", "rinsed", "drained",
    "halved", "quartered", "seeded", "deseeded", "pitted", "cored", "sifted",
    "packed", "firmly", "loosely", "level", "heaping", "heaped", "rounded",
    "about", "approximately", "plus", "extra", "good", "quality", "organic",
    "room", "temperature", "at", "of", "the", "a", "an", "into", "cut", "very",
    "medium", "large", "small", "big", "whole", "raw", "uncooked", "dry", "dried",
    "lean", "fine", "medium-sized", "large-sized", "small-sized", "standard", "pure",
    "plain", "seedless", "unbleached", "quick-cooking", "unsweetened", "skinned",
    "shelled", "washed", "stale", "boneless", "skinless", "mild", "hot", "warm",
}
UNREADABLE = "unreadable"


@dataclass
class Ingredient:
    aliases: list[str]
    food_ref: str
    usda_fdc: str
    volume: str
    each: str
    seasoning: bool
    exclude: str = ""
    grams_per_ml: float | None = None
    each_portions: dict[str, float] = field(default_factory=dict)  # modifier → grams
    each_default: str | None = None
    each_noun: str | None = None


def singular(word: str) -> str:
    if len(word) > 4 and word.endswith("ies"):
        return word[:-3] + "y"
    if len(word) > 4 and word.endswith(("oes", "ches", "shes")):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith(("ss", "us")):
        return word[:-1]
    return word


def portion_ml(modifier: str, amount: float) -> float | None:
    """Millilitres in a USDA volume portion: "1.0" × "cup, chopped" → 236.588."""
    head = modifier.lower().replace(",", " ").split()
    if not head:
        return None
    words = {"cup": "cup", "cups": "cup", "tbsp": "tbsp", "tablespoon": "tbsp",
             "tsp": "tsp", "teaspoon": "tsp", "ml": "ml", "milliliter": "ml",
             "liter": "l", "quart": "qt", "pint": "pt"}
    if head[:2] == ["fl", "oz"]:
        return amount * ML["floz"]
    unit = words.get(head[0])
    return amount * ML[unit] if unit else None


def pick(rows: list[tuple[float, str, float]]) -> list[tuple[float, str, float]]:
    """One USDA measure from several with the same wording: "1 tsp" over
    "0.5 tsp". Still several when they disagree at amount 1."""
    if len(rows) <= 1:
        return rows
    ones = [r for r in rows if r[0] == 1.0]
    return ones[:1] if len({r[2] for r in ones}) == 1 else ones


def load_ingredients(csv_path: Path, portions: dict[str, list[tuple[float, str, float]]],
                     food_names: dict[str, str]) -> tuple[dict[str, Ingredient], list[str]]:
    """The curated table, with each row's conversions worked out. Returns the
    alias index and the problems found; a problem fails the build."""
    index: dict[str, Ingredient] = {}
    problems: list[str] = []
    for row in csv.DictReader(open(csv_path, encoding="utf-8")):
        ing = Ingredient(aliases=[a.strip().lower() for a in row["aliases"].split(";") if a.strip()],
                         food_ref=row["food_ref"].strip(), usda_fdc=row["usda_fdc"].strip(),
                         volume=row["volume"].strip(), each=row["each"].strip(),
                         seasoning=row["seasoning"].strip() == "y",
                         exclude=(row.get("exclude") or "").strip())
        label = ing.aliases[0]
        if ing.food_ref not in food_names:
            problems.append(f"{label}: {ing.food_ref} is not in the nutrition bundle")
        rows = portions.get(ing.usda_fdc, []) if ing.usda_fdc else []
        if ing.usda_fdc and not rows:
            problems.append(f"{label}: USDA {ing.usda_fdc} has no household measures")
        if ing.volume:
            match = pick([(a, m, g) for a, m, g in rows if m.lower() == ing.volume.lower()])
            ml = portion_ml(match[0][1], match[0][0]) if len(match) == 1 else None
            if ml is None:
                problems.append(f"{label}: volume portion '{ing.volume}' not found once in USDA {ing.usda_fdc}")
            else:
                ing.grams_per_ml = match[0][2] / ml
        if ing.each:
            match = pick([(a, m, g) for a, m, g in rows if m.lower() == ing.each.lower()]) or \
                [(a, m, g) for a, m, g in rows if m.lower().startswith(ing.each.lower())]
            if len(match) != 1:
                problems.append(f"{label}: count portion '{ing.each}' matches {len(match)} USDA measures")
            else:
                a, m, g = match[0]
                ing.each_default = m
                ing.each_noun = singular(m.lower().replace(",", " ").split()[0])
                for a2, m2, g2 in rows:
                    first = m2.lower()
                    for size in SIZES:
                        if first.startswith(size) and size not in ing.each_portions:
                            ing.each_portions[size] = g2 / a2
                ing.each_portions["default"] = g / a
        for alias in ing.aliases:
            if alias in index:
                problems.append(f"alias '{alias}' is listed twice")
            index[alias] = ing
    return index, problems


def cleaned_words(text: str) -> list[str]:
    head = re.split(r"[,(;]| - | – | for | or ", text.lower(), maxsplit=1)[0]
    return [w for w in re.findall(r"[a-zà-ÿ'\-]+", head)]


def resolve_name(line: wikitext.Line, index: dict[str, Ingredient]) -> tuple[Ingredient | None, str | None, str | None]:
    """The ingredient a line names, the size word it gave, and the count noun
    it began with. By the line's own words first ("egg yolks" is not "egg"),
    then by its link when the words add nothing but preparation."""
    words = cleaned_words(line.ingredient_text)
    size = next((s for s in SIZES if " ".join(words[:len(s.split())]) == s), None)
    noun = None
    rest = list(words)
    if size:
        rest = rest[len(size.split()):]
    if rest and singular(rest[0]) in COUNT_NOUNS:
        noun = singular(rest[0])
        rest = rest[1:]
        if rest and rest[0] == "of":
            rest = rest[1:]
    core = [w for w in rest if w not in PREP]
    for candidate in (" ".join(core), " ".join(singular(w) for w in core)):
        if candidate in index:
            return index[candidate], size, noun
    # "1 garlic clove": the noun can come last.
    if core and singular(core[-1]) in COUNT_NOUNS and " ".join(core) in index:
        return index[" ".join(core)], size, singular(core[-1])
    if line.ingredient and line.ingredient in index:
        label = set(re.findall(r"[a-z'\-]+", line.ingredient)) | {singular(w) for w in re.findall(r"[a-z'\-]+", line.ingredient)}
        if all(w in label or singular(w) in label for w in core):
            return index[line.ingredient], size, noun
    return None, size, noun


def grams_for(line: wikitext.Line, ing: Ingredient, size: str | None, noun: str | None) -> float | None:
    if line.unit in GRAMS:
        return line.amount * GRAMS[line.unit]
    if line.unit in ML:
        return line.amount * ML[line.unit] * ing.grams_per_ml if ing.grams_per_ml else None
    if line.unit == "each":
        if not ing.each_portions:
            return None
        if noun and noun != ing.each_noun:
            return None
        grams = ing.each_portions.get(size or "default", ing.each_portions["default"]) if size else ing.each_portions["default"]
        return line.amount * grams
    return None


@dataclass
class Outcome:
    components: list[dict] = field(default_factory=list)
    set_aside: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)
    excluded: set[str] = field(default_factory=set)


def build_recipe(page: wikitext.Page, index: dict[str, Ingredient]) -> Outcome:
    out = Outcome()
    for line in page.lines:
        ing, size, noun = resolve_name(line, index)
        negligible = (line.unit in ("pinch", "dash")
                      or (line.amount is None and (line.unmeasured_ok or (ing is not None and ing.seasoning)))
                      or (ing is not None and ing.seasoning and line.unit == "each" and not ing.each_portions))
        if ing and ing.exclude:
            out.excluded.add(ing.exclude)
        if negligible:
            out.set_aside.append(line.text)
            continue
        if ing is None or line.amount is None:
            out.failures.append(line.text)
            continue
        grams = grams_for(line, ing, size, noun)
        if grams is None or grams <= 0:
            out.failures.append(line.text)
            continue
        out.components.append({"ref": ing.food_ref, "grams": round(grams, 1), "line": line.text})
    return out


def page_url(title: str) -> str:
    from urllib.parse import quote
    return "https://en.wikibooks.org/wiki/" + quote(title.replace(" ", "_"), safe=":_()',-.!")


def build(pages: list[dict], index: dict[str, Ingredient], fetched: str,
          allow_excluded: bool = False) -> tuple[dict, dict]:
    recipes = []
    stats = {"pages": 0, "no_ingredients": 0, "unreadable": 0, "too_few": 0, "excluded": 0, "kept": 0}
    for raw in sorted(pages, key=lambda p: p["pageid"]):
        stats["pages"] += 1
        rev = raw["revisions"][0]
        page = wikitext.parse(raw["title"], rev["slots"]["main"]["content"])
        if not page.lines:
            stats["no_ingredients"] += 1
            continue
        out = build_recipe(page, index)
        if out.failures:
            stats["unreadable"] += 1
            continue
        if len(out.components) < 2:
            stats["too_few"] += 1
            continue
        if out.excluded and not allow_excluded:
            stats["excluded"] += 1
            continue
        stats["kept"] += 1
        recipes.append({
            "id": str(raw["pageid"]),
            "name": page.name,
            "title": raw["title"],
            "revision": rev["revid"],
            "url": page_url(raw["title"]),
            "servings": page.servings,
            "components": out.components,
            "setAside": out.set_aside,
        })
    bundle = {
        "source": "Wikibooks Cookbook",
        "sourceURL": "https://en.wikibooks.org/wiki/Cookbook:Table_of_Contents",
        "licence": "CC BY-SA 4.0",
        "licenceURL": "https://creativecommons.org/licenses/by-sa/4.0/",
        "fetched": fetched,
        "recipes": recipes,
    }
    return bundle, stats


def write(bundle: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(bundle, ensure_ascii=False, indent=0, sort_keys=False) + "\n", encoding="utf-8")
