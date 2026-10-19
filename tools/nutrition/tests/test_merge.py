import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from almanac_nutrition import merge

FDN = "food.csv fdc_id={id}; foundation_food.csv NDB_number={code}"
SR = "food.csv fdc_id={id}; sr_legacy_food.csv NDB_number={code}"


def bundle(case, foods):
    """foods: (food_ref, english name, source_record, {nutrient: amount per 100 g})."""
    directory = tempfile.TemporaryDirectory()
    case.addCleanup(directory.cleanup)
    path = Path(directory.name) / "almanac.sqlite"
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE nutrition_food (food_ref TEXT, namespace TEXT, source_record TEXT);
        CREATE TABLE nutrition_food_name (food_ref TEXT, language TEXT, name TEXT, is_primary INTEGER);
        CREATE TABLE nutrition_value (food_ref TEXT, nutrient_id TEXT, basis TEXT, amount REAL);
    """)
    for ref, name, record, values in foods:
        db.execute("INSERT INTO nutrition_food VALUES (?, ?, ?)", (ref, ref.split(":")[0], record))
        db.execute("INSERT INTO nutrition_food_name VALUES (?, 'en', ?, 1)", (ref, name))
        for nutrient, amount in values.items():
            db.execute("INSERT INTO nutrition_value VALUES (?, ?, 'per_100g', ?)", (ref, nutrient, amount))
    db.commit()
    db.close()
    return path


EGG = {"energy_kcal": 143, "protein": 12.6, "fat_total": 9.5, "carbohydrate_by_difference": 0.7}
BEEF = {"energy_kcal": 150, "protein": 22.0, "fat_total": 6.0, "carbohydrate_by_difference": 0.0}


def records(path):
    groups, matches = merge.group(merge.read_foods(path))
    return {frozenset(f["food_ref"] for f in g) for g in groups}, matches, groups


class Matching(unittest.TestCase):
    def test_same_name_merges_and_not_is_a_word(self):
        path = bundle(self, [
            ("cofid:1", "Eggs, chicken, whole, raw", "", EGG),
            ("afcd:1", "Egg, chicken, whole, raw", "", {**EGG, "fat_total": 12.0}),
            ("ciqual:1", "Sausage (vegan), prepacked", "", BEEF),
            ("ciqual:2", "Sausage (not vegan), prepacked", "", BEEF),
        ])
        groups, _, _ = records(path)
        self.assertEqual(groups, {frozenset({"cofid:1", "afcd:1"})})

    def test_unsure_needs_neutral_words_and_an_agreeing_profile(self):
        path = bundle(self, [
            ("cofid:1", "Spinach, baby, fresh, raw", "", BEEF),
            ("afcd:1", "Spinach, baby, raw", "", BEEF),
            ("cofid:2", "Beef, sirloin steak, raw", "", BEEF),
            ("afcd:2", "Beef, fillet steak, raw", "", BEEF),           # a cut: a different food
            ("cofid:3", "Celery, fresh, raw", "", EGG),
            ("afcd:3", "Celery, raw", "", BEEF),                       # profiles disagree
        ])
        groups, matches, _ = records(path)
        self.assertEqual(groups, {frozenset({"cofid:1", "afcd:1"})})
        self.assertEqual([m["kind"] for m in matches], ["unsure"])

    def test_usda_codes_link_foods_whatever_their_names(self):
        path = bundle(self, [
            ("usda:1", "Eggs, Grade A, Large, egg whole", FDN.format(id=1, code="01123"), EGG),
            ("usda:2", "Egg, whole, raw, fresh", SR.format(id=2, code="1123"), EGG),
            ("usda:3", "Egg, whole, fried", "food.csv fdc_id=3; survey_fndds_food.csv food_code=31105005; "
                                            "input_food.csv sole input fdc_id=2 sr_code=1123", EGG),
        ])
        groups, matches, _ = records(path)
        self.assertEqual(groups, {frozenset({"usda:1", "usda:2", "usda:3"})})
        self.assertEqual({m["kind"] for m in matches}, {"code"})

    def test_almanac_dishes_are_never_merged(self):
        path = bundle(self, [("almanac:x", "Falafel", "", BEEF), ("ciqual:1", "Falafel", "", BEEF)])
        self.assertEqual(records(path)[0], set())


class Output(unittest.TestCase):
    def test_conflicts_keep_every_value_and_usda_is_the_record(self):
        path = bundle(self, [
            ("ciqual:1", "Honey", "", {"energy_kcal": 331, "protein": 0.3, "fat_total": 0.0}),
            ("usda:9", "Honey", FDN.format(id=9, code="19296"), {"energy_kcal": 304, "protein": 0.3,
                                                                 "fat_total": 0.0}),
            ("cofid:1", "Honey", "", {"energy_kcal": 288, "protein": 0.4, "fat_total": 0.0}),
        ])
        out = Path(path.parent)
        merge.run(path, out / "merges.json", out / "log.md")
        merges = json.loads((out / "merges.json").read_text())["merges"]
        self.assertEqual({m["foodRef"]: m["recordRef"] for m in merges},
                         {"ciqual:1": "usda:9", "usda:9": "usda:9", "cofid:1": "usda:9"})
        _, _, groups = records(path)
        conflict = merge.conflicts(groups[0])
        self.assertEqual([c["nutrient"] for c in conflict], ["energy_kcal"])
        self.assertEqual(sorted(v["value"] for v in conflict[0]["values"]), [288, 304, 331])
        self.assertIn("| `usda:9` Honey | energy_kcal |", (out / "log.md").read_text())


if __name__ == "__main__":
    unittest.main()
