"""Almanac-native regional dishes — licence group N (README "Almanac-native dishes").

Authored, not published: the inputs are the three CSVs in `tools/nutrition/native/`,
kept in the repository because Almanac owns them. A dish is a recipe of reference
foods already canonicalised from another source (USDA, CIQUAL, CoFID, AFCD); its
values are that recipe reduced to per 100 g, qualifier `calculated_recipe`, never
`measured`. The reduction is AlmanacCore's `NutritionDishEditor.reduce`, restated:

- every component must resolve, or nothing is computed;
- a nutrient is summed only when every component reports it per 100 g;
  `not_analysed` makes it unknown, `trace` and `below_loq` count as 0;
- the sum is divided by the finished weight (`yield_g`), or the component sum.

`extract` copies the CSVs into the lake with their SHA-256s. `canonicalise` reads
the other namespaces' canonical output, so it runs after them (`all` orders it last),
and writes `processed/native-report.md`: the checks that do not stop the build.
"""
from __future__ import annotations

import csv
import re
import shutil
import unicodedata
from collections import defaultdict
from pathlib import Path

from ..canonical_io import CanonicalError, read_canonical, write_canonical
from ..dictionary import Dictionary
from ..lake import Lake, read_json, sha256_file, staged_directory, write_json
from ..model import Food, FoodName, Portion, Value
from ..qa import general_atwater

NAMESPACE = "almanac"
NATIVE_DIR = Path(__file__).resolve().parents[2] / "native"
FILES = {
    "dishes.csv": ["dish_id", "name_en", "name_ar", "transliteration", "state", "yield_g",
                   "retention", "benchmark_ref", "notes"],
    "components.csv": ["dish_id", "food_ref", "grams", "note"],
    "portions.csv": ["dish_id", "amount", "unit", "grams"],
}
LOCAL_PREFIX = "regional-"  # apart from Kitchen's `wikibooks-` and a person's own dish ids
FOOD_GROUP = ("regional", "Regional dishes")
STATES = ("cooked", "raw")
DEFAULT_RETENTION = "none applied: macronutrients conserved, yield_g carries the water change"
# ponytail: one tolerance for both checks; tune once real dishes show the spread.
ENERGY_TOLERANCE = 0.15
BENCHMARK_TOLERANCE = 0.20
_DISH_ID = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def extract(lake: Lake, native_dir: Path = NATIVE_DIR) -> Path:
    out = lake.extracted(NAMESPACE)
    with staged_directory(out) as scratch:
        inputs = []
        for name in FILES:
            source = Path(native_dir) / name
            if not source.is_file():
                raise CanonicalError(f"{source} is missing")
            shutil.copyfile(source, scratch / name)
            inputs.append({"file": f"native/{name}", "sha256": sha256_file(source)})
        write_json(scratch / "manifest.json", {"namespace": NAMESPACE, "inputs": inputs})
    return out


def fold(text: str) -> str:
    """Case, accents, harakat and Arabic letter variants folded, for duplicate names."""
    text = "".join(c for c in unicodedata.normalize("NFKD", text.casefold())
                   if not unicodedata.combining(c) and c != "ـ")
    for variants, plain in (("أإآٱ", "ا"), ("ة", "ه"), ("ى", "ي")):
        text = re.sub(f"[{variants}]", plain, text)
    return " ".join(re.sub(r"[^\w\s]", " ", text).split())


def _positive(text: str, where: str, problems: list[str]) -> float | None:
    try:
        number = float(text)
    except ValueError:
        problems.append(f"{where}: {text!r} is not a number")
        return None
    if not number > 0 or number == float("inf"):
        problems.append(f"{where}: {text!r} must be a positive number")
        return None
    return number


def _read(directory: Path) -> dict[str, list[dict[str, str]]]:
    tables = {}
    for name, columns in FILES.items():
        with open(directory / name, newline="", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            rows = [{k: (v or "").strip() for k, v in row.items()} for row in reader]
            if missing := [c for c in columns if c not in (reader.fieldnames or [])]:
                raise CanonicalError(f"native/{name}: missing column(s) {', '.join(missing)}")
        tables[name] = rows
    return tables


def _reference_values(lake: Lake, refs: set[str], dictionary: Dictionary,
                      problems: list[str]) -> dict[str, dict[str, Value]]:
    """per_100g values of each referenced food, from its own namespace's canonical output."""
    found: dict[str, dict[str, Value]] = {}
    shippable = dictionary.shippable_groups
    by_namespace: dict[str, set[str]] = defaultdict(set)
    for ref in refs:
        namespace = ref.split(":", 1)[0]
        if namespace == NAMESPACE or namespace not in dictionary.sources:
            problems.append(f"{ref}: not a reference food (namespace {namespace!r})")
        elif dictionary.group_of(namespace) not in shippable:
            problems.append(f"{ref}: licence group {dictionary.group_of(namespace)} may not be "
                            "used, not even as a benchmark")
        else:
            by_namespace[namespace].add(ref)
    for namespace, wanted in sorted(by_namespace.items()):
        if not lake.canonical(namespace).is_dir():
            problems.append(f"canonical/{namespace} is missing: canonicalise {namespace} first")
            continue
        foods, _, values, _, _ = read_canonical(lake.canonical(namespace))
        present = {f.food_ref for f in foods} & wanted
        problems += [f"{ref}: no such food in canonical/{namespace}" for ref in sorted(wanted - present)]
        for ref in present:
            found[ref] = {}
        for v in values:
            if v.food_ref in present and v.basis == "per_100g":
                found[v.food_ref][v.nutrient_id] = v
    return found


def reduce(components: list[tuple[str, float]], total_grams: float,
           reference: dict[str, dict[str, Value]]) -> dict[str, float]:
    """Per 100 g of the finished dish, for every nutrient all components report."""
    nutrients = set.intersection(*(set(reference[ref]) for ref, _ in components))
    reduced = {}
    for nutrient in sorted(nutrients):
        total = 0.0
        for ref, grams in components:
            v = reference[ref][nutrient]
            if v.qualifier == "not_analysed":
                break
            total += 0.0 if v.qualifier in ("trace", "below_loq") else v.amount * grams / 100
        else:
            reduced[nutrient] = round(total / total_grams * 100, 4)
    return reduced


def _as_values(reduced: dict[str, float]) -> dict:
    """`qa.general_atwater` reads Value-like rows; native amounts are plain numbers."""
    return {n: Value("", n, "per_100g", a, "calculated_recipe", "", "", "", "", "")
            for n, a in reduced.items()}


def canonicalise(lake: Lake, dictionary: Dictionary) -> dict:
    extracted = lake.extracted(NAMESPACE)
    tables = _read(extracted)
    dishes, components, portion_rows = (tables[n] for n in FILES)
    problems: list[str] = []

    seen: set[str] = set()
    for i, d in enumerate(dishes, start=2):
        where = f"dishes.csv row {i}"
        if not _DISH_ID.fullmatch(d["dish_id"]):
            problems.append(f"{where}: dish_id {d['dish_id']!r} must be lower-case letters, digits "
                            "and single hyphens")
        if d["dish_id"] in seen:
            problems.append(f"{where}: dish_id {d['dish_id']!r} appears twice")
        seen.add(d["dish_id"])
        if not d["name_en"]:
            problems.append(f"{where}: name_en is required")
        if d["state"] not in STATES:
            problems.append(f"{where}: state must be one of {STATES}, got {d['state']!r}")
        if d["yield_g"]:
            _positive(d["yield_g"], f"{where} yield_g", problems)

    recipe: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for i, c in enumerate(components, start=2):
        where = f"components.csv row {i}"
        if c["dish_id"] not in seen:
            problems.append(f"{where}: unknown dish {c['dish_id']!r}")
        grams = _positive(c["grams"], f"{where} grams", problems)
        if grams is not None:
            recipe[c["dish_id"]].append((c["food_ref"], grams))
    problems += [f"dish {d['dish_id']!r}: no components" for d in dishes if not recipe[d["dish_id"]]]

    portions_of: dict[str, list[tuple[int, float, str, float]]] = defaultdict(list)
    for i, p in enumerate(portion_rows, start=2):
        where = f"portions.csv row {i}"
        if p["dish_id"] not in seen:
            problems.append(f"{where}: unknown dish {p['dish_id']!r}")
        if not p["unit"]:
            problems.append(f"{where}: unit is required")
        amount = _positive(p["amount"], f"{where} amount", problems)
        grams = _positive(p["grams"], f"{where} grams", problems)
        if amount is not None and grams is not None:
            portions_of[p["dish_id"]].append((i, amount, p["unit"], grams))

    refs = {ref for parts in recipe.values() for ref, _ in parts}
    refs |= {d["benchmark_ref"] for d in dishes if d["benchmark_ref"]}
    reference = _reference_values(lake, refs, dictionary, problems)
    if problems:
        raise CanonicalError(f"canonical/{NAMESPACE}: {len(problems)} problem(s)\n  " + "\n  ".join(problems))

    group = dictionary.group_of(NAMESPACE)
    units = {n: row.unit for n, row in dictionary.nutrients.items()}
    foods, names, values, portions, findings = [], [], [], [], []
    for d in dishes:
        dish_id, parts = d["dish_id"], recipe[d["dish_id"]]
        ref = f"{NAMESPACE}:{LOCAL_PREFIX}{dish_id}"
        component_grams = sum(g for _, g in parts)
        total = float(d["yield_g"]) if d["yield_g"] else component_grams
        reduced = reduce(parts, total, reference)
        benchmark = d["benchmark_ref"] or "none"
        foods.append(Food(NAMESPACE, LOCAL_PREFIX + dish_id, group, *FOOD_GROUP,
                          f"native/dishes.csv {dish_id}; {d['state']}; {len(parts)} components; "
                          f"benchmarked against {benchmark}"))
        english = d["name_en"]
        if d["transliteration"] and fold(d["transliteration"]) not in fold(english):
            # ponytail: the transliteration rides in the English name so search finds it;
            # a script-tagged name row when the name table admits one.
            english = f"{english} ({d['transliteration']})"
        names.append(FoodName(ref, "en", english, True))
        if d["name_ar"]:
            names.append(FoodName(ref, "ar", d["name_ar"], False))
        for nutrient, amount in reduced.items():
            values.append(Value(ref, nutrient, "per_100g", amount, "calculated_recipe", "",
                                repr(amount), nutrient, units[nutrient], group))
        for row, amount, unit, grams in portions_of[dish_id]:
            portions.append(Portion(ref, "household_measure", unit, amount, grams, "borrowed", "",
                                    repr(grams), "g", f"{amount:g} {unit}", "",
                                    f"native/portions.csv row {row}", group))
        findings.append(_check(d, ref, english, reduced, total, component_grams,
                               portions_of[dish_id], reference))

    _duplicate_names(dishes, findings)
    report_path = lake.root / "processed" / "native-report.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(render(findings), encoding="utf-8")
    inputs = read_json(extracted / "manifest.json")["inputs"]
    notes = {"dishes": len(dishes), "findings": sum(len(f["findings"]) for f in findings),
             "report": "processed/native-report.md",
             "retention": {d["dish_id"]: d["retention"] or DEFAULT_RETENTION for d in dishes}}
    return write_canonical(lake.canonical(NAMESPACE), namespace=NAMESPACE, foods=foods, names=names,
                           values=values, portions=portions, dictionary=dictionary,
                           inputs=inputs, notes=notes)


def _check(d, ref, english, reduced, total, component_grams, portions, reference) -> dict:
    """The soft checks for one dish: they go in the report and do not stop the build."""
    findings = []
    if not d["name_ar"]:
        findings.append("no Arabic name")
    if not portions:
        findings.append("no household measure (portions.csv)")
    if d["state"] == "cooked" and not d["yield_g"]:
        findings.append("cooked, but no yield_g: values assume no water was lost")
    atwater = general_atwater(_as_values(reduced))
    kcal = round(atwater[0], 1) if atwater else None
    summed = reduced.get("energy_kcal")
    if kcal is None:
        findings.append("general Atwater cannot be computed: the components share no protein, fat "
                        "and total-carbohydrate basis (draw them from one source)")
    elif summed is not None and abs(kcal - summed) > ENERGY_TOLERANCE * max(summed, 1):
        findings.append(f"general Atwater {kcal} kcal vs the components' own energy {summed} kcal "
                        f"per 100 g (over {ENERGY_TOLERANCE:.0%} apart)")
    bench = None
    if d["benchmark_ref"]:
        found = general_atwater(reference[d["benchmark_ref"]])
        bench = round(found[0], 1) if found else None
        if bench is None:
            findings.append(f"benchmark {d['benchmark_ref']} has no general-Atwater figure")
        elif kcal is not None and abs(kcal - bench) > BENCHMARK_TOLERANCE * max(bench, 1):
            findings.append(f"{kcal} kcal per 100 g vs benchmark {d['benchmark_ref']} {bench} kcal "
                            f"(over {BENCHMARK_TOLERANCE:.0%} apart)")
    else:
        findings.append("no benchmark_ref")
    return {"ref": ref, "dish_id": d["dish_id"], "name": english, "state": d["state"],
            "kcal": kcal, "benchmark_kcal": bench, "total_grams": total,
            "component_grams": component_grams, "findings": findings}


def _duplicate_names(dishes, findings) -> None:
    holders = defaultdict(list)
    for d in dishes:
        for language in ("name_en", "name_ar", "transliteration"):
            if d[language]:
                holders[fold(d[language])].append(d["dish_id"])
    by_id = {f["dish_id"]: f for f in findings}
    for name, ids in holders.items():
        for dish_id in sorted(set(ids)) if len(set(ids)) > 1 else ():
            others = ", ".join(i for i in sorted(set(ids)) if i != dish_id)
            by_id[dish_id]["findings"].append(f"name {name!r} also used by {others}")


def render(findings: list[dict]) -> str:
    flagged = sum(1 for f in findings if f["findings"])
    lines = ["# Native dishes — validation report", "",
             f"{len(findings)} dish(es); {flagged} with findings. These checks do not stop the build; "
             "the ones that do are raised by `canonicalise almanac`.", "",
             "| Dish | State | Grams (yield / components) | kcal per 100 g (general Atwater) | Benchmark kcal | Findings |",
             "|---|---|---:|---:|---:|---|"]
    for f in findings:
        lines.append(f"| `{f['ref']}` {f['name']} | {f['state']} | {f['total_grams']:g} / "
                     f"{f['component_grams']:g} | {f['kcal'] if f['kcal'] is not None else '—'} | "
                     f"{f['benchmark_kcal'] if f['benchmark_kcal'] is not None else '—'} | "
                     f"{'; '.join(f['findings']) or 'none'} |")
    return "\n".join(lines) + "\n"
