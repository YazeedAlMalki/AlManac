"""Builds the exercise library Almanac ships on top of workout-guide.

Sources, in the owner's order (2026-10-19): free-exercise-db (primary), wger
(secondary). workout-guide's 302 rows are already in every install and logged
bouts point at them, so they are matched against but never rewritten.

One record per real exercise: rows from any source that are the same movement,
or might be, are merged into one record. Every member's fields are kept,
tagged with its source; where members disagree both values stay and the
disagreement is logged for the owner to review. Nothing here picks a winner:
the record shows its base row's values (workout-guide, else free-exercise-db,
else wger), which is a fixed rule, not a judgement per conflict.

Every shipped record needs a demonstration graphic. A merged record carries
its base row's graphic. A record with no graphic in any member is held and
listed in the log, not shipped.
"""

from __future__ import annotations

import json
import re
import subprocess
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

FEDB_REPO = "https://github.com/yuhonas/free-exercise-db.git"
FEDB_COMMIT = "f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5"
WGER_COMMIT = "8f72cb2feba9f5f1cc40aa9855b185ab315a3cd8"
WGER_RAW = f"https://raw.githubusercontent.com/wger-project/wger/{WGER_COMMIT}/wger"
WGER_FIXTURES = {
    "exercise-base-data.json": "exercises/fixtures/exercise-base-data.json",
    "translations.json": "exercises/fixtures/translations.json",
}

REPO = Path(__file__).resolve().parents[3]
RESOURCES = REPO / "Sources/AlmanacCore/Training/Resources"
WORKOUT_GUIDE = RESOURCES / "workout-guide/manifest.json"
GRAPHICS_DIR = "free-exercise-db"
LIBRARY_JSON = RESOURCES / "exercise-library.json"
MERGE_LOG = REPO / "docs/features/exercise-merge-log.md"

# --- Vocabulary: every source onto workout-guide's display words -------------

FEDB_MUSCLE = {
    "quadriceps": "Quads", "shoulders": "Shoulders", "abdominals": "Core", "chest": "Chest",
    "hamstrings": "Hamstrings", "triceps": "Triceps", "biceps": "Biceps", "lats": "Lats",
    "middle back": "Upper Back", "calves": "Calves", "lower back": "Lower Back",
    "forearms": "Forearms", "glutes": "Glutes", "traps": "Traps", "adductors": "Adductors",
    "neck": "Neck", "abductors": "Abductors",
}
FEDB_EQUIPMENT = {
    "body only": "Bodyweight", "barbell": "Barbell", "dumbbell": "Dumbbell", "cable": "Cable",
    "machine": "Machine", "kettlebells": "Kettlebell", "bands": "Resistance Band",
    "medicine ball": "Medicine Ball", "exercise ball": "Stability Ball",
    "foam roll": "Foam Roller", "e-z curl bar": "EZ Bar", "other": "Other",
}
# wger muscle pk → display word (fixture muscles.json, pinned commit).
WGER_MUSCLE = {1: "Biceps", 2: "Shoulders", 3: "Core", 4: "Chest", 5: "Triceps", 6: "Core",
               7: "Calves", 8: "Glutes", 9: "Traps", 10: "Quads", 11: "Hamstrings", 12: "Lats",
               13: "Biceps", 14: "Core", 15: "Calves", 16: "Lower Back"}
WGER_CATEGORY = {8: "Arms", 9: "Legs", 10: "Core", 11: "Chest", 12: "Back", 13: "Shoulders",
                 14: "Calves", 15: "Cardio"}
# wger equipment pk → display word; None marks support kit (mat, bench, bar to hang from).
WGER_EQUIPMENT = {1: "Barbell", 2: "EZ Bar", 3: "Dumbbell", 4: None, 5: "Stability Ball",
                  6: None, 7: "Bodyweight", 8: None, 9: None, 10: "Kettlebell",
                  11: "Resistance Band", 12: "Cable"}
WGER_LICENCE = {1: "cc_by_sa_3", 2: "cc_by_sa_4", 3: "cc0", 4: "cc_by_4"}

# Display word → muscle groups it can match. "Lower Back" and "Posterior Chain"
# sit between back and legs (a deadlift is filed under either); None matches any.
MUSCLE_GROUPS = {
    "Chest": {"chest"}, "Shoulders": {"shoulders"}, "Rear Delts": {"shoulders"},
    "Biceps": {"arms"}, "Triceps": {"arms"}, "Forearms": {"arms"}, "Arms": {"arms"},
    "Back": {"back"}, "Lats": {"back"}, "Upper Back": {"back"}, "Traps": {"back"},
    "Lower Back": {"back", "legs"}, "Posterior Chain": {"back", "legs"},
    "Core": {"core"}, "Quads": {"legs"}, "Glutes": {"legs"}, "Hamstrings": {"legs"},
    "Legs": {"legs"}, "Calves": {"legs"}, "Adductors": {"legs"}, "Abductors": {"legs"},
    "Hips": {"legs"}, "Neck": {"neck"},
}
SUPPORT = {"Bodyweight", "Pull-up Bar", "Wall", "Towel", "Doorway", "Chair", "Box", "Bench"}
WILD_EQUIPMENT = {None, "Other"}


def muscle_groups(display: str | None) -> set[str] | None:
    return MUSCLE_GROUPS.get(display) if display else None


def equipment_class(display: str | None) -> str | None:
    if display in WILD_EQUIPMENT:
        return None
    return "bodyweight" if display in SUPPORT else display.lower()


# A row that states no equipment often names it ("Biceps Curl With Cable").
# The name words are dropped before names are compared, so without this a cable
# curl would match a dumbbell curl.
NAMED_EQUIPMENT = [
    (r"\b(cables?|rope attachment|pulley)\b", "cable"), (r"\b(dumbbells?|db)\b", "dumbbell"),
    (r"\b(barbells?|bb)\b", "barbell"), (r"\b(e-?z|sz)\b", "ez bar"),
    (r"\b(kettlebells?|kb)\b", "kettlebell"), (r"\b(bands?|banded)\b", "resistance band"),
    (r"\b(machine|leverage|smith|hammerstrength|legend|pec deck)\b", "machine"),
]


def row_equipment(row: Row) -> str | None:
    stated = equipment_class(row.equipment)
    if stated is not None:
        return stated
    named = {cls for pattern, cls in NAMED_EQUIPMENT if re.search(pattern, row.name.lower())}
    return named.pop() if len(named) == 1 else None


# --- Names --------------------------------------------------------------------

DROP_WORDS = {
    "barbell", "dumbbell", "db", "bb", "kettlebell", "kb", "cable", "machine", "band",
    "resistance", "with", "the", "a", "an", "on", "and", "to", "of", "using", "exercise",
}
# Words that make a different variation of a movement, not a different way of
# naming it: "Incline Bench Press" is not "Bench Press", "Weighted Push-up" is
# not "Push-up". Two names that differ by one of these are not merged.
VARIATION = {
    "incline", "decline", "reverse", "close", "wide", "narrow", "one", "single", "alternating",
    "alternate", "power", "hang", "front", "back", "side", "rear", "lateral", "overhead",
    "lying", "seated", "standing", "kneeling", "sumo", "romanian", "stiff", "bulgarian",
    "jump", "split", "hammer", "preacher", "concentration", "spider", "pause", "deficit",
    "box", "smith", "elevated", "supinated", "pronated", "neutral", "behind", "neck", "high",
    "low", "upright", "bent", "straight", "twisting", "oblique", "weighted", "assisted",
    "partial", "isometric", "explosive", "clap", "diamond", "pike", "archer", "negative",
    "hack", "goblet", "zercher", "landmine", "leg", "arm", "knee", "floor", "bench",
    "stability", "ball", "medicine", "plate", "sled", "rope", "bar", "trap", "hex", "push",
    "pull", "full", "half", "quarter", "double", "inverted", "frog", "crossover", "cross",
    "thruster", "snatch", "clean", "jerk", "swing", "stretch", "hold", "walk", "run",
    "sprint", "stepup", "pistol", "wall", "toe", "heel", "inner", "outer", "upper", "lower",
    "up", "down", "in", "out", "palm", "grip", "underhand", "overhand", "supino", "rocking",
    # A different body part is a different exercise ("Seated Calf Stretch" is
    # not "Seated Hamstring and Calf Stretch").
    "hamstring", "calf", "quad", "glute", "chest", "shoulder", "bicep", "tricep", "lat", "ab",
    "hip", "flexor", "achille", "soleus", "gastrocnemius", "groin", "adductor", "abductor",
    "it", "wrist", "ankle", "trap", "delt", "pec", "core", "spine",
}
# Words that name nothing about the movement: a label, a brand, a filler.
NEUTRAL = {
    "medium", "standard", "regular", "basic", "classic", "traditional", "conventional",
    "version", "variation", "nb", "mp", "hd", "legend", "hammerstrength", "flat", "simple",
    "normal", "movement", "technique", "style", "bilateral",
}
JOIN = [(r"\bpush[ -]?ups?\b", "pushup"), (r"\bpull[ -]?ups?\b", "pullup"),
        (r"\bchin[ -]?ups?\b", "chinup"), (r"\bsit[ -]?ups?\b", "situp"),
        (r"\bstep[ -]?ups?\b", "stepup"), (r"\b(?:e-?z|s-?z)[ -]?(?:curl )?bar\b", " "),
        (r"\bmedium grip\b", " "), (r"\bfl(?:yes|ys|ies|ye)\b", "fly")]


def singular(word: str) -> str:
    if len(word) <= 3 or word.endswith("ss"):
        return word
    if re.search(r"(ss|sh|ch|x)es$", word):
        return word[:-2]
    return word[:-1] if word.endswith("s") else word


def tokens(name: str) -> frozenset[str]:
    text = name.lower()
    for pattern, repl in JOIN:
        text = re.sub(pattern, repl, text)
    words = re.sub(r"[^a-z0-9 ]+", " ", text).split()
    return frozenset(singular(w) for w in words if w not in DROP_WORDS)


def similarity(a: frozenset[str], b: frozenset[str]) -> float:
    return len(a & b) / len(a | b) if a | b else 0.0


# Equal token sets are the same exercise. Names that differ only by neutral
# words ("Bench Press - NB"), or overlap at least this much without a variation
# word between them ("Leg Press Calf Raise" / "Calf Press on the Leg Press"),
# might be, and the owner's rule is to merge when unsure, and log it. A named
# variant ("Zottman Curl", "Pendlay Row") overlaps less and stays apart.
UNSURE = 0.75


def name_match(a: frozenset[str], b: frozenset[str]) -> float | None:
    """1.0 for the same name, the overlap for an unsure match, None for apart."""
    if a == b:
        return 1.0
    diff, s = a ^ b, similarity(a, b)
    if (a & b) and diff <= NEUTRAL:
        return s
    return s if s >= UNSURE and not diff & VARIATION else None

# --- Records -------------------------------------------------------------------


@dataclass
class Row:
    source: str
    id: str
    name: str
    muscle: str | None
    equipment: str | None
    secondary: list[str] = field(default_factory=list)
    force: str | None = None
    category: str | None = None
    graphic: str | None = None          # source-relative path of the image to ship
    licence_group: str = ""
    licence_author: str | None = None
    prescription: str | None = None     # workout-guide's own rows carry none here

    @property
    def key(self) -> str:
        return f"{self.source}:{self.id}"

    def fields(self) -> dict:
        return {k: v for k, v in {
            "name": self.name, "primaryMuscle": self.muscle, "equipment": self.equipment,
            "secondaryMuscles": self.secondary or None, "force": self.force,
        }.items() if v is not None}


def workout_guide_rows(manifest: list[dict]) -> list[Row]:
    return [Row("workout-guide", r["id"], r["name"], r.get("primaryMuscle"), r.get("equipment"),
                graphic=r["graphic"], licence_group="cc_by_sa_4",
                licence_author=r.get("licenseAuthor")) for r in manifest]


def fedb_rows(exercises: list[dict]) -> list[Row]:
    rows = []
    for e in exercises:
        muscles = [FEDB_MUSCLE[m] for m in e.get("primaryMuscles", [])]
        rows.append(Row(
            "free-exercise-db", e["id"], e["name"], muscles[0] if muscles else None,
            FEDB_EQUIPMENT.get(e.get("equipment")),
            secondary=[FEDB_MUSCLE[m] for m in e.get("secondaryMuscles", [])],
            force=e.get("force"), category=e.get("category"),
            graphic=e["images"][0] if e.get("images") else None, licence_group="unlicense"))
    return rows


def wger_rows(base: list[dict], translations: list[dict]) -> list[Row]:
    english = {t["fields"]["exercise"]: t["fields"] for t in translations
               if t["model"] == "exercises.translation" and t["fields"]["language"] == 2}
    rows = []
    for b in base:
        f, name = b["fields"], english.get(b["pk"])
        if name is None:
            continue
        muscles = [WGER_MUSCLE[m] for m in f["muscles"]]
        kit = [WGER_EQUIPMENT[e] for e in f["equipment"]]
        load = [k for k in kit if k and k != "Bodyweight"]
        equipment = load[0] if load else ("Bodyweight" if f["equipment"] else None)
        authors = list(dict.fromkeys(a for a in (f["license_author"], name["license_author"]) if a))
        rows.append(Row(
            "wger", str(b["pk"]), name["name"].strip(),
            muscles[0] if muscles else WGER_CATEGORY.get(f["category"]), equipment,
            secondary=list(dict.fromkeys(WGER_MUSCLE[m] for m in f["muscles_secondary"])),
            licence_group=WGER_LICENCE[f["license"]], licence_author=", ".join(authors) or None))
    return rows


def prescription(row: Row) -> str:
    """free-exercise-db's category onto Almanac's prescription types, by the
    same rule `WorkoutGuideSeed.prescriptionType` applies to workout-guide."""
    if row.equipment == "Foam Roller":
        return "release"
    if row.category == "stretching":
        return "hold_stretch"
    if row.category == "cardio":
        return "duration"
    if row.equipment in (None, "Bodyweight", "Other"):
        held = any(w in row.name.lower() for w in ("hold", "plank", "hang", "wall sit"))
        return "time_under_load" if held else "reps_bodyweight"
    return "reps_load"


# --- Matching ------------------------------------------------------------------


def join(a: tuple, b: tuple) -> tuple | None:
    """Two (muscle groups, equipment class) profiles merged, or None when they
    disagree. None inside a profile is "not stated" and agrees with anything.
    Checked per cluster, not per pair, so a row that states no equipment cannot
    chain a dumbbell curl to a machine curl."""
    (ma, ea), (mb, eb) = a, b
    if ea is not None and eb is not None and ea != eb:
        return None
    muscles = ma & mb if ma is not None and mb is not None else (ma if mb is None else mb)
    if muscles is not None and not muscles:
        return None
    return muscles, ea if ea is not None else eb


def cluster(rows: list[Row]) -> tuple[list[list[Row]], list[dict], list[tuple[Row, Row, float]]]:
    """Union-find over every compatible pair whose names are the same or might
    be. Returns the clusters, the match behind each merge, and the pairs left
    apart because joining them would merge two workout-guide rows (those are
    already in people's logs; merging them is an owner call, not a build step)."""
    toks = [tokens(r.name) for r in rows]
    profile = [(muscle_groups(r.muscle), row_equipment(r)) for r in rows]
    pairs = []
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            s = name_match(toks[i], toks[j])
            if s is not None and join(profile[i], profile[j]) is not None:
                pairs.append((s, i, j))
    pairs.sort(key=lambda p: (-p[0], p[1], p[2]))

    parent = list(range(len(rows)))
    guides = [{i} if rows[i].source == "workout-guide" else set() for i in range(len(rows))]

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    matches, kept_apart = [], []
    for s, i, j in pairs:
        ri, rj = find(i), find(j)
        if ri == rj:
            continue
        joined = join(profile[ri], profile[rj])
        if joined is None:
            continue
        if guides[ri] and guides[rj]:
            kept_apart.append((rows[i], rows[j], s))
            continue
        parent[rj] = ri
        profile[ri] = joined
        guides[ri] |= guides[rj]
        matches.append({"a": rows[i].key, "b": rows[j].key,
                        "kind": "same" if s == 1.0 else "unsure", "score": round(s, 2)})

    groups: dict[int, list[Row]] = {}
    for i, r in enumerate(rows):
        groups.setdefault(find(i), []).append(r)
    return list(groups.values()), matches, kept_apart


GENERAL = {"Arms", "Legs", "Back"}
SOURCE_ORDER = {"workout-guide": 0, "free-exercise-db": 1, "wger": 2}


def base_row(members: list[Row]) -> Row | None:
    """The row whose values and graphic the record shows: workout-guide's (it is
    already shipped), else the first free-exercise-db row with an image."""
    for r in sorted(members, key=lambda r: (SOURCE_ORDER[r.source], r.id)):
        if r.graphic:
            return r
    return None


def conflicts(members: list[Row]) -> list[dict]:
    """Fields two or more members state differently. Names are not compared:
    differently worded names are what a merge is. A source that says nothing
    about a field does not conflict with one that does, and nor does a general
    word ("Legs", wger's category when it names no muscle) with a narrower one."""
    out = []
    for name in ("primaryMuscle", "equipment"):
        values = {}
        for r in members:
            v = r.fields().get(name)
            if v is not None and v != "Other":
                values.setdefault(v, []).append(r.key)
        if set(values) - GENERAL:
            values = {v: k for v, k in values.items() if v not in GENERAL}
        if len(values) > 1:
            out.append({"field": name, "values": [{"value": v, "sources": k}
                                                   for v, k in sorted(values.items())]})
    return out


def build_library(guide: list[Row], fedb: list[Row], wger: list[Row]):
    groups, matches, kept_apart = cluster(guide + fedb + wger)
    records, held = [], []
    for members in sorted(groups, key=lambda m: min(r.key for r in m)):
        base = base_row(members)
        if base is None:
            held.append(members)
            continue
        if len(members) == 1 and base.source == "workout-guide":
            continue  # unchanged, already shipped
        record = {
            "sourceId": base.source, "exerciseId": base.id,
            "sources": [{"sourceId": r.source, "exerciseId": r.id,
                         "licenseGroup": r.licence_group, "licenseAuthor": r.licence_author,
                         "fields": r.fields()} for r in sorted(members, key=lambda r: r.key)],
            "conflicts": conflicts(members),
        }
        if base.source != "workout-guide":
            record["insert"] = {
                "name": base.name, "category": base.muscle, "equipment": base.equipment,
                "force": base.force, "secondaryMuscles": base.secondary,
                "prescriptionType": prescription(base), "licenseGroup": base.licence_group,
                "licenseAuthor": base.licence_author,
                "graphicPath": f"{GRAPHICS_DIR}/{base.id}.jpg",
            }
        records.append(record)
    return records, matches, held, kept_apart


# --- I/O -----------------------------------------------------------------------


def fetch(lake: Path) -> None:
    fedb = lake / "free-exercise-db"
    if not fedb.exists():
        subprocess.run(["git", "init", "-q", str(fedb)], check=True)
        subprocess.run(["git", "-C", str(fedb), "fetch", "-q", "--depth", "1", FEDB_REPO,
                        FEDB_COMMIT], check=True)
        subprocess.run(["git", "-C", str(fedb), "checkout", "-q", "FETCH_HEAD"], check=True)
    (lake / "wger").mkdir(parents=True, exist_ok=True)
    for name, path in WGER_FIXTURES.items():
        target = lake / "wger" / name
        if not target.exists():
            urllib.request.urlretrieve(f"{WGER_RAW}/{path}", target)


def load(lake: Path):
    guide = workout_guide_rows(json.loads(WORKOUT_GUIDE.read_text()))
    fedb = fedb_rows(json.loads((lake / "free-exercise-db/dist/exercises.json").read_text()))
    wger = wger_rows(json.loads((lake / "wger/exercise-base-data.json").read_text()),
                     json.loads((lake / "wger/translations.json").read_text()))
    return guide, fedb, wger


def write_graphics(lake: Path, records: list[dict], fedb: list[Row]) -> None:
    """free-exercise-db's first frame (the start position), scaled to 512 px wide
    to keep the bundle small. The Unlicense permits the change; it is stated on
    the Attributions page anyway."""
    from PIL import Image  # build-time only

    by_id = {r.id: r for r in fedb}
    out = RESOURCES / GRAPHICS_DIR
    out.mkdir(exist_ok=True)
    wanted = set()
    for rec in records:
        if "insert" not in rec:
            continue
        row = by_id[rec["exerciseId"]]
        target = out / f"{row.id}.jpg"
        wanted.add(target.name)
        with Image.open(lake / "free-exercise-db/exercises" / row.graphic) as im:
            im = im.convert("RGB")
            im.thumbnail((512, 512))
            im.save(target, "JPEG", quality=75, optimize=True, progressive=True)
    for stale in out.glob("*.jpg"):
        if stale.name not in wanted:
            stale.unlink()


def write_log(records, matches, held, kept_apart, counts) -> None:
    lines = [
        "# Exercise merge log",
        "",
        "Written by `tools/exercises` (`python3 -m almanac_exercises build`); do not edit by hand.",
        f"Sources: free-exercise-db `{FEDB_COMMIT[:12]}`, wger `{WGER_COMMIT[:12]}`, and the "
        "302 workout-guide rows already shipped.",
        "",
        "Rule (owner, 2026-10-19): one record per real exercise. Rows are matched on the name "
        "(normalised: case, plurals, equipment words, `push-up`/`pushup`…) plus muscle group plus "
        f"equipment. Equal names are **same**; a name overlap of {UNSURE} or more is **unsure** "
        "and is merged too, unless the names differ by a word that makes a different variation "
        "(incline, seated, weighted, one-arm…). Every source's fields are kept on the record, tagged with the "
        "source; where they disagree both values are kept and listed under Conflicts.",
        "",
        "| | Count |", "|---|---:|",
        *[f"| {k} | {v} |" for k, v in counts.items()],
        "",
        "## Conflicts",
        "",
        "Both values are kept. The record shows its base row's value until the owner says otherwise.",
        "",
        "| Record | Field | Values |", "|---|---|---|",
    ]
    for rec in records:
        for c in rec["conflicts"]:
            vals = "; ".join(f"{v['value']} ({', '.join(v['sources'])})" for v in c["values"])
            lines.append(f"| `{rec['sourceId']}:{rec['exerciseId']}` | {c['field']} | {vals} |")
    lines += ["", "## Merges", "", "| Record | Members (name) | Matches |", "|---|---|---|"]
    by_member = {}
    for m in matches:
        by_member.setdefault(m["a"], []).append(m)
        by_member.setdefault(m["b"], []).append(m)
    for rec in records:
        if len(rec["sources"]) < 2:
            continue
        keys = [f"{s['sourceId']}:{s['exerciseId']}" for s in rec["sources"]]
        members = "<br>".join(f"`{k}` {s['fields']['name']}" for k, s in zip(keys, rec["sources"]))
        seen = {id(m): m for k in keys for m in by_member.get(k, [])}
        how = "<br>".join(f"{m['kind']} {m['score']}: `{m['a']}` ~ `{m['b']}`" for m in seen.values())
        lines.append(f"| `{rec['sourceId']}:{rec['exerciseId']}` | {members} | {how} |")
    lines += ["", "## Kept apart: two workout-guide rows",
              "", "These matched, but merging would fold one shipped workout-guide row into another "
              "that people's logged sets already point at. Left as two records for the owner.", "",
              "| Row | Row | Score |", "|---|---|---:|"]
    lines += [f"| `{a.key}` {a.name} | `{b.key}` {b.name} | {s:.2f} |" for a, b, s in kept_apart]
    lines += ["", "## Held: no demonstration graphic", "",
              "No member has an image this build can ship, so the record is not shipped "
              "(every exercise must have one). wger's own images are on wger.de, which this "
              "build does not read.", "", "| Members |", "|---|"]
    lines += ["| " + "<br>".join(f"`{r.key}` {r.name}" for r in m) + " |" for m in held]
    MERGE_LOG.write_text("\n".join(lines) + "\n")


def build(lake: Path) -> dict:
    guide, fedb, wger = load(lake)
    records, matches, held, kept_apart = build_library(guide, fedb, wger)
    write_graphics(lake, records, fedb)
    LIBRARY_JSON.write_text(json.dumps({
        "freeExerciseDbCommit": FEDB_COMMIT, "wgerCommit": WGER_COMMIT, "records": records,
    }, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
    counts = {
        "workout-guide rows": len(guide), "free-exercise-db rows": len(fedb), "wger rows": len(wger),
        "new records shipped": sum("insert" in r for r in records),
        "merges into workout-guide rows": sum("insert" not in r for r in records),
        "records with more than one source": sum(len(r["sources"]) > 1 for r in records),
        "records with a conflict": sum(bool(r["conflicts"]) for r in records),
        "held (no graphic)": len(held),
        "workout-guide pairs kept apart": len(kept_apart),
    }
    write_log(records, matches, held, kept_apart, counts)
    return counts
