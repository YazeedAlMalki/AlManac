"""Builds Almanac's Open Food Facts database: packaged products sold in the
Gulf, one record per real product.

Owner, 2026-10-19: "Use Open Food Facts" for packaged products and barcodes.
Open Food Facts is under the Open Database License (ODbL 1.0); its individual
contents under the Database Contents License (DbCL 1.0). Share-alike attaches
to any adapted database we publicly use, so this one is kept apart from the
nutrition reference (`almanac.sqlite`, groups A/B/N only): it is its own file,
released under the ODbL, and this script is the method that made it
(ODbL 4.6). See docs/features/open-food-facts.md.

Scope (not confirmed by the owner; CONTEXT.md): products whose countries
include a Gulf state, with a name and the four values a calorie needs
(energy, protein, fat, carbohydrate per 100 g or 100 mL). Product photos are
not used.

One record per real product (owner's step 10 rule):
- same barcode once leading zeros are dropped (UPC-A 012345678905 is EAN-13
  0012345678905): same product;
- same brand and same normalised name with matching nutrition: same;
- same brand, names overlapping by 0.75 or more, matching nutrition: unsure,
  merged too.
A merged record keeps every member's barcode and values; where members
disagree both values stay and the disagreement is logged. Nothing is matched
against the generic foods of the nutrition reference: a branded product and
"yoghurt, plain" are different things, and merging them would also put ODbL
data into that database.
"""

from __future__ import annotations

import csv
import gzip
import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
OUT_DB = REPO / "Sources/AlmanacCore/Nutrition/Resources/open-food-facts.sqlite"
MERGE_LOG = REPO / "docs/features/open-food-facts-merge-log.md"
EXPORT_URL = "https://openfoodfacts-ds.s3.eu-west-3.amazonaws.com/en.openfoodfacts.org.products.csv.gz"
EXPORT_NAME = "en.openfoodfacts.org.products.csv.gz"

GULF = {"en:saudi-arabia", "en:united-arab-emirates", "en:kuwait", "en:qatar", "en:bahrain", "en:oman"}

# OFF column → (canonical nutrient, unit). The canonical ids are the nutrition
# dictionary's (tools/nutrition/dictionary/nutrients.csv). OFF's
# `carbohydrates` is carbohydrate as EU 1169/2011 labels it: available, fibre
# excluded — so it is never total carbohydrate by difference.
NUTRIENTS = {
    "energy-kcal_100g": ("energy_kcal", "kcal"),
    # Used only when a product states no kcal; converted at 4.184 kJ/kcal,
    # as the nutrition pipeline does for AFCD (`kj_to_kcal`).
    "energy-kj_100g": ("energy_kcal", "kJ"),
    "proteins_100g": ("protein", "g"),
    "fat_100g": ("fat_total", "g"),
    "carbohydrates_100g": ("carbohydrate_available", "g"),
    "fiber_100g": ("fibre_total_dietary", "g"),
}
# `alcohol_100g` is % vol, not grams, so it is not mapped.
REQUIRED = ("proteins_100g", "fat_100g", "carbohydrates_100g")
KJ_PER_KCAL = 4.184
LIQUID = re.compile(r"\d\s*(ml|cl|l|litres?|liters?)\b", re.I)

# --- Reading -------------------------------------------------------------------


@dataclass
class Product:
    code: str
    name: str
    brands: str
    quantity: str
    serving_size: str
    serving_quantity: float | None
    countries: list[str]
    url: str
    last_modified: int
    values: dict[str, str]                 # OFF column → raw cell
    basis: str = "per_100g"
    excluded: str | None = None

    @property
    def key(self) -> str:
        return self.code

    def amount(self, column: str) -> float:
        v = float(self.values[column])
        return v / KJ_PER_KCAL if column == "energy-kj_100g" else v

    @property
    def energy_column(self) -> str | None:
        return next((c for c in ("energy-kcal_100g", "energy-kj_100g") if c in self.values), None)


def norm_code(code: str) -> str:
    return code.lstrip("0") or "0"


def check(p: Product) -> str | None:
    """Why a product cannot be used, or None. A value that is not a number, is
    negative, or cannot be true of 100 g of anything excludes the product; it
    is never clamped or guessed at."""
    if not p.name.strip():
        return "no name"
    if p.energy_column is None:
        return "no energy"
    for column in REQUIRED:
        if not p.values.get(column, "").strip():
            return f"no {column}"
    for column, raw in p.values.items():
        try:
            v = float(raw)
        except ValueError:
            return f"{column} is not a number ({raw!r})"
        if v != v or v < 0:
            return f"{column} is negative or not a number ({raw!r})"
        if column.startswith("energy") and p.amount(column) > 900:
            return f"energy above 900 kcal ({raw} {NUTRIENTS[column][1]})"
        if not column.startswith("energy") and v > 100:
            return f"{column} above 100 g ({raw})"
    grams = sum(p.amount(c) for c in ("proteins_100g", "fat_100g", "carbohydrates_100g"))
    if grams > 105:
        return f"protein + fat + carbohydrate is {grams:g} g per 100"
    return None


def read(path: Path) -> list[Product]:
    csv.field_size_limit(1 << 30)
    products = []
    with gzip.open(path, "rt", encoding="utf-8", newline="") as f:
        rows = csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
        header = next(rows)
        col = {k: i for i, k in enumerate(header)}
        for row in rows:
            if len(row) != len(header):
                continue
            countries = row[col["countries_tags"]].split(",")
            if not GULF.intersection(countries):
                continue
            values = {c: row[col[c]].strip() for c in NUTRIENTS if row[col[c]].strip()}
            if "energy-kcal_100g" in values:
                values.pop("energy-kj_100g", None)  # the published kcal wins
            serving = row[col["serving_quantity"]].strip()
            try:
                serving_quantity = float(serving) if serving else None
            except ValueError:
                serving_quantity = None
            quantity = row[col["quantity"]].strip()
            p = Product(
                code=row[col["code"]].strip(), name=row[col["product_name"]].strip(),
                brands=row[col["brands"]].strip(), quantity=quantity,
                serving_size=row[col["serving_size"]].strip(),
                serving_quantity=serving_quantity if serving_quantity and serving_quantity > 0 else None,
                countries=sorted(GULF.intersection(countries)),
                url=f"https://world.openfoodfacts.org/product/{row[col['code']].strip()}",
                last_modified=int(row[col["last_modified_t"]] or 0), values=values,
                # OFF's `_100g` fields are per 100 mL for a liquid, whose pack
                # or serving is given in mL.
                basis="per_100ml" if LIQUID.search(f"{quantity} {row[col['serving_size']]}") else "per_100g")
            p.excluded = check(p)
            products.append(p)
    return products


# --- Matching -------------------------------------------------------------------

STOP = {"the", "a", "an", "and", "with", "of", "in", "&"}


def tokens(text: str) -> frozenset[str]:
    words = re.sub(r"[^\w ]+", " ", text.lower()).split()
    return frozenset(w for w in words if w not in STOP)


def brand_key(brands: str) -> str:
    return " ".join(sorted(tokens(brands.split(",")[0]))) if brands else ""


def profile_matches(a: Product, b: Product) -> bool:
    """The four required values agree within 10 % or 1 unit, whichever is wider."""
    if a.energy_column is None or b.energy_column is None:
        return False
    for column in ("energy",) + REQUIRED:
        x, y = ((a.amount(a.energy_column), b.amount(b.energy_column)) if column == "energy"
                else (a.amount(column), b.amount(column)))
        if abs(x - y) > max(1.0, 0.1 * max(x, y)):
            return False
    return a.basis == b.basis


UNSURE = 0.75


def cluster(products: list[Product]) -> tuple[list[list[Product]], list[dict]]:
    parent = list(range(len(products)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    matches = []

    def union(i: int, j: int, kind: str, why: str) -> None:
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[rj] = ri
            matches.append({"a": products[i].code, "b": products[j].code, "kind": kind, "why": why})

    by_code: dict[str, int] = {}
    for i, p in enumerate(products):
        k = norm_code(p.code)
        if k in by_code:
            union(by_code[k], i, "same", "barcode")
        else:
            by_code[k] = i

    by_brand: dict[str, list[int]] = {}
    for i, p in enumerate(products):
        by_brand.setdefault(brand_key(p.brands), []).append(i)
    for brand, members in by_brand.items():
        if not brand:
            continue  # no brand: a name alone does not identify a product
        toks = {i: tokens(products[i].name) for i in members}
        for x, i in enumerate(members):
            for j in members[x + 1:]:
                a, b = toks[i], toks[j]
                if not (a and b) or not profile_matches(products[i], products[j]):
                    continue
                if a == b:
                    union(i, j, "same", "brand + name + nutrition")
                elif len(a & b) / len(a | b) >= UNSURE:
                    union(i, j, "unsure", f"brand + name overlap {len(a & b) / len(a | b):.2f} + nutrition")

    groups: dict[int, list[Product]] = {}
    for i, p in enumerate(products):
        groups.setdefault(find(i), []).append(p)
    return list(groups.values()), matches


def qualifier(column: str, raw: str) -> str:
    if float(raw) == 0:
        return "zero_reported"
    # A label's energy is calculated from the other values; the rest are the
    # manufacturer's declared figures, which the dictionary calls borrowed.
    return "calculated_factor" if column.startswith("energy") else "borrowed"


def value_rows(p: Product) -> dict:
    return {NUTRIENTS[c][0]: {"amount": p.amount(c), "qualifier": qualifier(c, raw),
                              "sourceValue": raw, "sourceField": c, "unit": NUTRIENTS[c][1]}
            for c, raw in sorted(p.values.items())}


def conflicts(members: list[Product]) -> list[dict]:
    out = []
    for nutrient in sorted({NUTRIENTS[c][0] for m in members for c in m.values}):
        seen: dict[float, list[str]] = {}
        for m in members:
            column = next((c for c in m.values if NUTRIENTS[c][0] == nutrient), None)
            if column:
                seen.setdefault(round(m.amount(column), 2), []).append(m.code)
        if len(seen) > 1:
            out.append({"field": nutrient, "values": [
                {"value": f"{v:g}", "codes": codes} for v, codes in sorted(seen.items())]})
    return out


def build_records(products: list[Product]) -> tuple[list[dict], list[dict], list[Product]]:
    usable = [p for p in products if p.excluded is None]
    groups, matches = cluster(usable)
    records = []
    for members in groups:
        # The record shows its most recently edited member — a fixed rule, not
        # a choice per conflict; every member's values stay below it.
        members.sort(key=lambda m: (-m.last_modified, m.code))
        base = members[0]
        records.append({
            "ref": f"off:{base.code}",
            "codes": sorted({m.code for m in members}),
            "name": base.name, "brands": base.brands, "quantity": base.quantity,
            "basis": base.basis,
            "servingText": base.serving_size or None,
            "servingGrams": base.serving_quantity if base.basis == "per_100g" else None,
            "countries": sorted({c for m in members for c in m.countries}),
            "url": base.url, "lastModified": base.last_modified,
            "values": value_rows(base),
            "members": [{"code": m.code, "name": m.name, "brands": m.brands,
                         "lastModified": m.last_modified, "values": value_rows(m)}
                        for m in members[1:]],
            "conflicts": conflicts(members),
        })
    records.sort(key=lambda r: r["ref"])
    return records, matches, [p for p in products if p.excluded]


# --- Output ---------------------------------------------------------------------


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while block := f.read(1 << 20):
            h.update(block)
    return h.hexdigest()


SCHEMA = """
CREATE TABLE off_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE off_product (
    food_ref TEXT PRIMARY KEY, name TEXT NOT NULL, brands TEXT NOT NULL, quantity_text TEXT NOT NULL,
    serving_text TEXT, serving_grams REAL, basis TEXT NOT NULL CHECK (basis IN ('per_100g', 'per_100ml')),
    url TEXT NOT NULL, last_modified INTEGER NOT NULL, licence_group TEXT NOT NULL CHECK (licence_group = 'C'));
CREATE TABLE off_barcode (code TEXT PRIMARY KEY, food_ref TEXT NOT NULL REFERENCES off_product (food_ref));
CREATE INDEX idx_off_barcode_trimmed ON off_barcode (ltrim(code, '0'));
CREATE TABLE off_value (
    food_ref TEXT NOT NULL REFERENCES off_product (food_ref), nutrient_id TEXT NOT NULL, amount REAL NOT NULL,
    qualifier TEXT NOT NULL, source_value TEXT NOT NULL, source_field TEXT NOT NULL, source_unit TEXT NOT NULL,
    PRIMARY KEY (food_ref, nutrient_id));
-- Every merged member's own name and values, so where members disagree both values are kept.
CREATE TABLE off_member (
    code TEXT PRIMARY KEY, food_ref TEXT NOT NULL REFERENCES off_product (food_ref), name TEXT NOT NULL,
    brands TEXT NOT NULL, last_modified INTEGER NOT NULL, values_json TEXT NOT NULL);
"""

NOTICE = ("Contains information from Open Food Facts (https://openfoodfacts.org), which is made available "
          "here under the Open Database License (ODbL) 1.0 (https://opendatacommons.org/licenses/odbl/1-0/). "
          "Individual contents are under the Database Contents License (DbCL) 1.0 "
          "(https://opendatacommons.org/licenses/dbcl/1-0/).")


def write_db(records: list[dict], export_sha: str, target: Path = None) -> None:
    """The adapted database, released under the ODbL: the app reads it in place,
    read-only, so it is never copied into a person's own database or backups."""
    import sqlite3
    target = target or OUT_DB
    tmp = target.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    con = sqlite3.connect(tmp)
    con.executescript(SCHEMA)
    con.executemany("INSERT INTO off_meta VALUES (?, ?)", [
        ("licence", "ODbL-1.0"), ("contents_licence", "DbCL-1.0"), ("notice", NOTICE),
        ("source_url", EXPORT_URL), ("source_sha256", export_sha),
        ("scope", "Products sold in Saudi Arabia, the UAE, Kuwait, Qatar, Bahrain or Oman, with a name "
                  "and energy, protein, fat and carbohydrate."),
        ("method", "tools/openfoodfacts in the Almanac repository")])
    for r in records:
        con.execute("INSERT INTO off_product VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'C')",
                    (r["ref"], r["name"], r["brands"], r["quantity"], r["servingText"], r["servingGrams"],
                     r["basis"], r["url"], r["lastModified"]))
        con.executemany("INSERT INTO off_barcode VALUES (?, ?)", [(c, r["ref"]) for c in r["codes"]])
        con.executemany("INSERT INTO off_value VALUES (?, ?, ?, ?, ?, ?, ?)", [
            (r["ref"], n, v["amount"], v["qualifier"], v["sourceValue"], v["sourceField"], v["unit"])
            for n, v in sorted(r["values"].items())])
        con.executemany("INSERT INTO off_member VALUES (?, ?, ?, ?, ?, ?)", [
            (m["code"], r["ref"], m["name"], m["brands"], m["lastModified"],
             json.dumps(m["values"], sort_keys=True, ensure_ascii=False)) for m in r["members"]])
    con.commit()
    con.execute("VACUUM")
    con.close()
    tmp.replace(target)


def write(records, matches, excluded, total: int, export: Path, export_sha: str) -> dict:
    write_db(records, export_sha)
    counts = {
        "Gulf products in the export": total,
        "excluded (see below)": len(excluded),
        "records shipped": len(records),
        "records with more than one member": sum(bool(r["members"]) for r in records),
        "merges, same": sum(m["kind"] == "same" for m in matches),
        "merges, unsure": sum(m["kind"] == "unsure" for m in matches),
        "records with a conflict": sum(bool(r["conflicts"]) for r in records),
    }
    reasons: dict[str, int] = {}
    for p in excluded:
        reasons[re.sub(r" \(.*", "", p.excluded)] = reasons.get(re.sub(r" \(.*", "", p.excluded), 0) + 1
    lines = [
        "# Open Food Facts merge log", "",
        "Written by `tools/openfoodfacts` (`python3 -m almanac_off build`); do not edit by hand.",
        f"Export: `{export.name}`, SHA-256 `{export_sha}`.", "",
        "Rule (owner, 2026-10-19): one record per real product. Same barcode without leading zeros is "
        "**same**; same brand and name with nutrition within 10 % (or 1 unit) is **same**; same brand, "
        f"names overlapping {UNSURE} or more, matching nutrition is **unsure** and merged too. Every member's "
        "barcode and values are kept; disagreements keep both values and are listed under Conflicts. The "
        "record shows its most recently edited member.", "",
        "| | Count |", "|---|---:|", *[f"| {k} | {v} |" for k, v in counts.items()], "",
        "## Excluded", "", "| Reason | Products |", "|---|---:|",
        *[f"| {k} | {v} |" for k, v in sorted(reasons.items(), key=lambda kv: -kv[1])], "",
        "## Conflicts", "", "| Record | Field | Values (barcodes) |", "|---|---|---|",
    ]
    for r in records:
        for c in r["conflicts"]:
            vals = "; ".join(f"{v['value']} ({', '.join(v['codes'])})" for v in c["values"])
            lines.append(f"| `{r['ref']}` {r['name']} | {c['field']} | {vals} |")
    lines += ["", "## Merges", "", "| Record | Members | How |", "|---|---|---|"]
    by_code = {}
    for m in matches:
        by_code.setdefault(m["a"], []).append(m)
        by_code.setdefault(m["b"], []).append(m)
    for r in records:
        if not r["members"]:
            continue
        names = "<br>".join([f"`{r['ref'][4:]}` {r['name']}"] + [f"`{m['code']}` {m['name']}" for m in r["members"]])
        seen = {id(m): m for c in r["codes"] for m in by_code.get(c, [])}
        how = "<br>".join(f"{m['kind']}: {m['why']}" for m in seen.values())
        lines.append(f"| `{r['ref']}` | {names} | {how} |")
    MERGE_LOG.write_text("\n".join(lines) + "\n")
    return counts


def build(lake: Path) -> dict:
    export = lake / "raw/off" / EXPORT_NAME
    export_sha = sha256(export)
    recorded = (lake / "raw/off/SHA256SUMS").read_text().split()[0]
    if recorded != export_sha:
        raise SystemExit(f"{export} does not match SHA256SUMS ({export_sha} != {recorded})")
    products = read(export)
    records, matches, excluded = build_records(products)
    return write(records, matches, excluded, len(products), export, export_sha)


def fetch(lake: Path) -> None:
    import urllib.request
    target = lake / "raw/off" / EXPORT_NAME
    target.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(EXPORT_URL, target)
    (target.parent / "SHA256SUMS").write_text(f"{sha256(target)}  {EXPORT_NAME}\n")
