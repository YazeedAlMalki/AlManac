"""Reads a Wikibooks Cookbook page's wikitext into a recipe: its name, the
servings it states, and its ingredient lines as amount + unit + ingredient.

Nothing here guesses. A line this module cannot read is returned as
unreadable, and the build drops the whole recipe rather than a line of it
(docs/features/recipe-sources.md, "If the owner picks Wikibooks").
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass, field
from fractions import Fraction

# Wikibooks links its units to their own Cookbook pages. Both spellings — the
# page and what authors type — fold to one unit key.
UNIT_PAGES = {
    "cup": "cup", "teaspoon": "tsp", "tablespoon": "tbsp", "gram": "g",
    "kilogram": "kg", "ounce": "oz", "pound": "lb", "milliliter": "ml",
    "millilitre": "ml", "liter": "l", "litre": "l", "quart": "qt", "pint": "pt",
    "fluid ounce": "floz", "deciliter": "dl", "centiliter": "cl",
    "pinch": "pinch", "dash": "dash", "each": "each",
}
UNIT_WORDS = {
    "cup": "cup", "cups": "cup", "c": "cup", "c.": "cup",
    "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp", "tsp.": "tsp", "t": "tsp",
    "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp", "tbsp.": "tbsp",
    "tbs": "tbsp", "tbl": "tbsp", "tbls": "tbsp", "T": "tbsp",
    "g": "g", "gram": "g", "grams": "g", "gm": "g", "gms": "g", "gr": "g",
    "kg": "kg", "kilogram": "kg", "kilograms": "kg", "kilo": "kg", "kilos": "kg",
    "oz": "oz", "oz.": "oz", "ounce": "oz", "ounces": "oz",
    "lb": "lb", "lb.": "lb", "lbs": "lb", "lbs.": "lb", "pound": "lb", "pounds": "lb",
    "ml": "ml", "mL": "ml", "milliliter": "ml", "milliliters": "ml",
    "millilitre": "ml", "millilitres": "ml",
    "l": "l", "L": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
    "dl": "dl", "cl": "cl",
    "quart": "qt", "quarts": "qt", "qt": "qt", "pint": "pt", "pints": "pt", "pt": "pt",
    "fl oz": "floz", "fluid ounce": "floz", "fluid ounces": "floz",
    "pinch": "pinch", "pinches": "pinch", "dash": "dash", "dashes": "dash",
    "ea": "each", "ea.": "each", "each": "each",
}
# Millilitres in one, for the volume units. US customary, which is what the
# Cookbook's own unit pages define.
ML = {"cup": 236.588, "tsp": 4.92892, "tbsp": 14.7868, "ml": 1.0, "l": 1000.0,
      "dl": 100.0, "cl": 10.0, "qt": 946.353, "pt": 473.176, "floz": 29.5735}
GRAMS = {"g": 1.0, "kg": 1000.0, "oz": 28.3495, "lb": 453.592}

# Linked pages that are techniques or equipment, not ingredients.
NOT_INGREDIENTS = {
    "chopping", "chop", "slicing", "slice", "mince", "mincing", "dice", "dicing",
    "grating", "grate", "cube", "cubing", "garnish", "julienne", "peeling",
    "inch", "centimetre", "centimeter", "mm", "cm", "boiling", "melting",
    "whisk", "sifting", "beating", "zest", "crushing", "crush", "shred",
    "shredding", "mashing", "puree", "purée", "softening", "room temperature",
    "blanching", "toasting", "roasting", "frying", "sautéing", "julienning",
    "dicing#", "brunoise", "chiffonade", "quartering", "halving", "seed",
    "seeding", "rinse", "rinsing", "drain", "draining", "soaking", "soak",
    "beat", "temperature", "fahrenheit", "celsius", "gallon", "g", "ml", "kg",
    "tsp", "tbsp", "oz", "lb", "l", "grater", "oil and fat", "meat and poultry",
} | set(UNIT_PAGES)

# Words that make an unmeasured line a seasoning the build may set aside
# rather than a missing amount: "salt, to taste".
UNMEASURED_MARKERS = ("to taste", "as needed", "as required", "for garnish",
                      "to garnish", "for serving", "to serve", "for dusting",
                      "for greasing", "for frying", "optional", "if desired",
                      "as desired", "for decoration")

LINK = re.compile(r"\[\[(?:Cookbook:)?([^|\]#]*)(?:#[^|\]]*)?(?:\|([^\]]*))?\]\]")
UNICODE_FRACTIONS = {"½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
                     "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6",
                     "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"}
NUMBER = r"(?:\d+(?:\.\d+)?(?:\s+\d+/\d+)?|\d+/\d+)"
QUANTITY = re.compile(rf"^\s*(?P<a>{NUMBER})(?:\s*(?:-|–|—|to|or)\s*(?P<b>{NUMBER}))?(?![\d/])")


# "1 can (400 grams) tomatoes", "2 ea. (250 g / 8.8 oz) carrots": a count
# whose bracket states what one weighs. The bracket is the amount.
STATED = re.compile(r"^(?:[a-z.]+\s+)?\(\s*(?P<n>\d+(?:\.\d+)?)[\s-]*(?P<u>g|grams?|kg|oz|ounces?|lbs?|pounds?|ml|mL)\b[^)]*\)\s*", re.I)
STATED_UNITS = {"g": "g", "gram": "g", "grams": "g", "kg": "kg", "oz": "oz", "ounce": "oz",
                "ounces": "oz", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb", "ml": "ml"}


@dataclass
class Line:
    text: str                       # the line as a reader sees it, links resolved
    amount: float | None = None     # None: no amount given
    unit: str | None = None         # a key of ML / GRAMS, "each", "pinch", "dash"
    ingredient: str | None = None   # the linked Cookbook page, folded
    ingredient_text: str = ""       # what follows the amount, for unlinked lines
    unmeasured_ok: bool = False     # "to taste" and its kin
    is_range: bool = False


@dataclass
class Page:
    title: str
    name: str
    servings: int | None
    lines: list[Line] = field(default_factory=list)
    categories: list[str] = field(default_factory=list)


def fold(name: str) -> str:
    name = re.sub(r"\s+", " ", name.replace("_", " ")).strip().lower()
    while name.startswith("cookbook:"):
        name = name[len("cookbook:"):].strip()
    return name


def plain(text: str) -> str:
    """Wikitext to what the page shows: links to their labels, templates and
    markup removed."""
    text = re.sub(r"<ref[^>]*/>|<ref[^>]*>.*?</ref>", "", text, flags=re.S)
    text = re.sub(r"<[^>]+>", "", text)
    text = LINK.sub(lambda m: (m.group(2) or m.group(1)).strip(), text)
    text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = text.replace("'''", "").replace("''", "")
    return re.sub(r"\s+", " ", text).strip()


def number(text: str) -> float:
    total = Fraction(0)
    for part in text.split():
        total += Fraction(part)
    return float(total)


def servings(wikitext: str) -> int | None:
    m = re.search(r"\|\s*Servings\s*=\s*([^\n|]*)", wikitext, re.I)
    if not m:
        return None
    value = plain(m.group(1))
    # Only a single whole number is a count; "4–6" or "1 loaf" is not.
    return int(value) if re.fullmatch(r"\d{1,2}", value) and int(value) > 0 else None


def ingredient_section(wikitext: str) -> str | None:
    m = re.search(r"^==\s*Ingredients\s*==[ \t]*\n(.*?)(?=^==[^=]|\Z)", wikitext, re.S | re.M | re.I)
    return m.group(1) if m else None


def parse_line(raw: str) -> Line:
    body = html.unescape(raw.lstrip("*#:; ").strip())
    # "About 2 tbsp", "~1 can": an approximate amount is still the amount.
    body = re.sub(r"^(?:about|approximately|approx\.?|roughly|~)\s*", "", body, flags=re.I)
    for glyph, ascii_ in UNICODE_FRACTIONS.items():
        body = re.sub(rf"(\d)\s*{glyph}", rf"\1 {ascii_}", body).replace(glyph, ascii_)
    body = body.replace("⁄", "/")
    links = [(fold(t), (label or t).strip()) for t, label in LINK.findall(body)]
    text = plain(body)
    line = Line(text=text)
    lowered = text.lower()
    line.unmeasured_ok = any(marker in lowered for marker in UNMEASURED_MARKERS)

    # "A pinch of nutmeg", "a dash of hot sauce": an amount too small to weigh.
    if re.match(r"^(?:an?\s+)?(?:small\s+)?(?:pinch|dash)(?:es)?\b", text, re.I):
        line.unit = "pinch"
    m = QUANTITY.match(text)
    rest = text
    if m:
        a = number(m.group("a"))
        if m.group("b"):
            line.is_range = True
            a = (a + number(m.group("b"))) / 2
        line.amount = a
        rest = text[m.end():].strip()
    if line.amount is not None:
        unit = None
        for words in (3, 2, 1):
            head = " ".join(rest.split()[:words])
            key = UNIT_WORDS.get(head) or UNIT_WORDS.get(head.lower())
            # A lone "T" or "t" is only a unit in its own case.
            if key and not (head in ("t", "T", "c") and len(rest.split()) < 2):
                unit = key
                rest = " ".join(rest.split()[words:])
                break
        line.unit = unit or "each"
        if line.unit == "each":
            stated = STATED.match(rest)
            if stated:
                line.amount *= float(stated.group("n"))
                line.unit = STATED_UNITS[stated.group("u").lower()]
                rest = rest[stated.end():]
        # "10 g (2 tsp) salt": the alternative in brackets is not an ingredient.
        rest = re.sub(r"^\([^)]*\)\s*", "", rest)
    line.ingredient_text = rest.strip(" ,")

    for target, _ in links:
        if target and target not in NOT_INGREDIENTS and not target.startswith(("category:", "file:", "image:")):
            line.ingredient = target
            break
    return line


def parse(title: str, wikitext: str) -> Page:
    name = title.split(":", 1)[1] if title.startswith("Cookbook:") else title
    page = Page(title=title, name=name.strip(), servings=servings(wikitext))
    page.categories = [fold(c) for c in re.findall(r"\[\[Category:([^|\]]+)", wikitext)]
    section = ingredient_section(wikitext)
    if section is None:
        return page
    for raw in section.splitlines():
        if raw.startswith("*"):
            line = parse_line(raw)
            if line.text:
                page.lines.append(line)
    return page
