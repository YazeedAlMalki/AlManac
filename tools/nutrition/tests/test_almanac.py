"""Native regional dishes (sources/almanac.py), on a synthetic lake."""
import dataclasses
import sqlite3
import unittest
from contextlib import closing

from almanac_nutrition import bundle
from almanac_nutrition.canonical_io import CanonicalError, read_canonical, write_canonical
from almanac_nutrition.dictionary import Source
from almanac_nutrition.model import Food, FoodName, Value
from almanac_nutrition.sources import almanac
from tests.support import DICTIONARY, temp_lake, write_table

DISH_HEADER = ["dish_id", "name_en", "name_ar", "transliteration", "state", "yield_g", "retention",
               "benchmark_ref", "notes"]


def usda(ref_id, **amounts):
    """A USDA food; amounts by nutrient, a string qualifier for a token ('trace', 'not_analysed')."""
    ref = f"usda:{ref_id}"
    values = []
    for nutrient, amount in amounts.items():
        if isinstance(amount, str):
            values.append(Value(ref, nutrient, "per_100g", None, amount, "", "~", "1", "g", "A"))
        else:
            qualifier = "zero_reported" if amount == 0 else "measured"
            values.append(Value(ref, nutrient, "per_100g", float(amount), qualifier, "", str(amount),
                                "1", "g", "A"))
    return Food("usda", ref_id, "A", "", "", "test"), FoodName(ref, "en", f"Food {ref_id}", True), values


REFERENCE = [
    usda("rice", energy_kcal=130, protein=2.7, fat_total=0.3, carbohydrate_by_difference=28, alcohol=0),
    usda("chicken", energy_kcal=239, protein=27, fat_total=14, carbohydrate_by_difference=0),
    usda("oil", energy_kcal=884, protein=0, fat_total=100, carbohydrate_by_difference=0),
    usda("spice", energy_kcal=300, protein="trace", fat_total=10, carbohydrate_by_difference=50,
         alcohol="not_analysed"),
    usda("bench", energy_kcal=180, protein=10, fat_total=7, carbohydrate_by_difference=19),
]


class NativeDishes(unittest.TestCase):
    def setUp(self):
        self.lake = temp_lake(self)
        self.native = self.lake.root / "native"
        write_canonical(self.lake.canonical("usda"), namespace="usda", dictionary=DICTIONARY, inputs=[],
                        foods=[f for f, _, _ in REFERENCE], names=[n for _, n, _ in REFERENCE],
                        values=[v for _, _, vs in REFERENCE for v in vs])
        self.write(dishes=[["kabsa", "Chicken kabsa", "كبسة دجاج", "kabsat dajaj", "cooked", "500", "",
                            "usda:bench", ""]],
                   components=[["kabsa", "usda:rice", "300", ""], ["kabsa", "usda:chicken", "250", ""],
                               ["kabsa", "usda:oil", "20", ""]],
                   portions=[["kabsa", "1", "plate", "350"]])

    def write(self, dishes=(), components=(), portions=()):
        write_table(self.native / "dishes.csv", DISH_HEADER, list(dishes))
        write_table(self.native / "components.csv", ["dish_id", "food_ref", "grams", "note"], list(components))
        write_table(self.native / "portions.csv", ["dish_id", "amount", "unit", "grams"], list(portions))

    def run_stage(self):
        almanac.extract(self.lake, self.native)
        return almanac.canonicalise(self.lake, DICTIONARY)

    def rows(self):
        return read_canonical(self.lake.canonical("almanac"))

    def report(self):
        return (self.lake.root / "processed" / "native-report.md").read_text(encoding="utf-8")

    def test_a_dish_is_its_recipe_reduced_over_its_yield(self):
        self.run_stage()
        foods, names, values, portions, _ = self.rows()
        self.assertEqual([(f.food_ref, f.licence_group, f.food_group_code) for f in foods],
                         [("almanac:regional-kabsa", "N", "regional")])
        self.assertIn("benchmarked against usda:bench", foods[0].source_record)
        self.assertIn("cooked", foods[0].source_record)
        by_nutrient = {v.nutrient_id: v for v in values}
        # protein: (300 × 2.7 + 250 × 27 + 0) / 100 g of ingredients, over a 500 g yield.
        self.assertAlmostEqual(by_nutrient["protein"].amount, (8.1 + 67.5) / 500 * 100, places=3)
        self.assertAlmostEqual(by_nutrient["fat_total"].amount, (0.9 + 35 + 20) / 500 * 100, places=3)
        self.assertEqual({v.qualifier for v in values}, {"calculated_recipe"})
        self.assertEqual({v.licence_group for v in values}, {"N"})

    def test_names_carry_arabic_and_the_transliteration(self):
        self.run_stage()
        names = {n.language: n.name for n in self.rows()[1]}
        self.assertEqual(names, {"en": "Chicken kabsa (kabsat dajaj)", "ar": "كبسة دجاج"})

    def test_a_household_measure_becomes_a_portion(self):
        self.run_stage()
        [portion] = self.rows()[3]
        self.assertEqual((portion.kind, portion.amount, portion.unit, portion.value),
                         ("household_measure", 1.0, "plate", 350.0))

    def test_without_a_yield_the_component_sum_is_the_weight(self):
        self.write(dishes=[["salad", "Salad", "سلطة", "", "raw", "", "", "", ""]],
                   components=[["salad", "usda:rice", "100", ""], ["salad", "usda:oil", "100", ""]],
                   portions=[["salad", "1", "bowl", "200"]])
        self.run_stage()
        fat = next(v for v in self.rows()[2] if v.nutrient_id == "fat_total")
        self.assertAlmostEqual(fat.amount, (0.3 + 100) / 2, places=3)

    def test_trace_counts_as_zero_and_not_analysed_leaves_the_nutrient_out(self):
        self.write(dishes=[["mix", "Mix", "خلطة", "", "raw", "", "", "", ""]],
                   components=[["mix", "usda:spice", "10", ""], ["mix", "usda:rice", "90", ""]])
        self.run_stage()
        values = {v.nutrient_id: v.amount for v in self.rows()[2]}
        self.assertAlmostEqual(values["protein"], 90 * 2.7 / 100, places=3)  # the spice's trace is 0
        self.assertNotIn("alcohol", values)  # rice says 0, the spice says not analysed: unknown

    def test_the_report_names_each_soft_finding(self):
        self.write(dishes=[["a", "Saleeg", "", "", "cooked", "", "", "", ""],
                           ["b", "saleeg", "سليق", "", "raw", "", "", "usda:bench", ""]],
                   components=[["a", "usda:oil", "50", ""], ["b", "usda:chicken", "100", ""]])
        self.run_stage()
        report = self.report()
        for expected in ("no Arabic name", "no household measure", "cooked, but no yield_g",
                         "no benchmark_ref", "also used by b", "also used by a",
                         "vs benchmark usda:bench"):
            self.assertIn(expected, report)

    def test_energy_far_from_general_atwater_is_flagged(self):
        reference = REFERENCE + [usda("odd", energy_kcal=50, protein=10, fat_total=10,
                                      carbohydrate_by_difference=10)]  # 4/4/9/7 says 170
        write_canonical(self.lake.canonical("usda"), namespace="usda", dictionary=DICTIONARY, inputs=[],
                        foods=[f for f, _, _ in reference], names=[n for _, n, _ in reference],
                        values=[v for _, _, vs in reference for v in vs])
        self.write(dishes=[["odd", "Odd", "غريب", "", "raw", "", "", "", ""]],
                   components=[["odd", "usda:odd", "100", ""]])
        self.run_stage()
        self.assertIn("general Atwater 170.0 kcal vs the components' own energy 50.0", self.report())

    def test_problems_stop_the_stage_and_keep_the_previous_output(self):
        self.run_stage()
        cases = {
            "no such food in canonical/usda": dict(
                dishes=[["x", "X", "", "", "raw", "", "", "", ""]],
                components=[["x", "usda:missing", "10", ""]]),
            "not a reference food": dict(
                dishes=[["x", "X", "", "", "raw", "", "", "sfda:1", ""]],
                components=[["x", "usda:rice", "10", ""]]),
            "appears twice": dict(
                dishes=[["x", "X", "", "", "raw", "", "", "", ""], ["x", "Y", "", "", "raw", "", "", "", ""]],
                components=[["x", "usda:rice", "10", ""]]),
            "state must be one of": dict(
                dishes=[["x", "X", "", "", "fried", "", "", "", ""]],
                components=[["x", "usda:rice", "10", ""]]),
            "no components": dict(dishes=[["x", "X", "", "", "raw", "", "", "", ""]]),
            "must be a positive number": dict(
                dishes=[["x", "X", "", "", "raw", "", "", "", ""]],
                components=[["x", "usda:rice", "0", ""]]),
            "dish_id 'X Y'": dict(
                dishes=[["X Y", "X", "", "", "raw", "", "", "", ""]],
                components=[["X Y", "usda:rice", "10", ""]]),
        }
        for message, tables in cases.items():
            with self.subTest(message):
                self.write(**tables)
                almanac.extract(self.lake, self.native)
                with self.assertRaisesRegex(CanonicalError, message):
                    almanac.canonicalise(self.lake, DICTIONARY)
                self.assertEqual([f.food_ref for f in self.rows()[0]], ["almanac:regional-kabsa"])

    def test_a_group_d_source_is_refused_even_as_a_benchmark(self):
        # The union may one day hold SFDA for research; a dish may still not use it (D8).
        sfda = Source("sfda", "sfda", "SFDA", "2026", "unclear", "D", "", "")
        restricted = dataclasses.replace(DICTIONARY, sources={**DICTIONARY.sources, "sfda": sfda})
        self.write(dishes=[["x", "X", "", "", "raw", "", "", "sfda:1", ""]],
                   components=[["x", "usda:rice", "10", ""]])
        almanac.extract(self.lake, self.native)
        with self.assertRaisesRegex(CanonicalError, "licence group D may not be used"):
            almanac.canonicalise(self.lake, restricted)

    def test_native_rows_ship_in_the_bundle_as_group_n(self):
        self.run_stage()
        bundle.union(self.lake, DICTIONARY)
        report = bundle.build(self.lake, DICTIONARY)
        self.assertEqual(report["namespaces"], ["almanac", "usda"])
        with closing(sqlite3.connect(report["path"])) as con:
            self.assertEqual(con.execute("SELECT licence_group, food_group_code FROM nutrition_food "
                                         "WHERE namespace = 'almanac'").fetchall(), [("N", "regional")])
            self.assertEqual(con.execute("SELECT name FROM nutrition_food_name WHERE language = 'ar'")
                             .fetchall(), [("كبسة دجاج",)])

    def test_no_dishes_puts_no_native_source_in_the_bundle(self):
        self.write()
        self.run_stage()
        bundle.union(self.lake, DICTIONARY)
        self.assertEqual(bundle.build(self.lake, DICTIONARY)["namespaces"], ["usda"])

    def test_the_shipped_native_files_have_the_columns_the_stage_reads(self):
        lake = temp_lake(self)
        almanac.extract(lake)  # the repository's own native/ files
        self.assertEqual(sorted(p.name for p in lake.extracted("almanac").iterdir()),
                         ["components.csv", "dishes.csv", "manifest.json", "portions.csv"])
        almanac._read(lake.extracted("almanac"))


class Fold(unittest.TestCase):
    def test_case_harakat_and_letter_variants_fold_together(self):
        self.assertEqual(almanac.fold("Kabsa"), almanac.fold("KABSA"))
        self.assertEqual(almanac.fold("كَبْسَة"), almanac.fold("كبسه"))
        self.assertEqual(almanac.fold("أرز"), almanac.fold("ارز"))


if __name__ == "__main__":
    unittest.main()
