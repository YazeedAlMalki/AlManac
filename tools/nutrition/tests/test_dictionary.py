import csv
import shutil
import tempfile
import unittest
from pathlib import Path

from almanac_nutrition.dictionary import DICTIONARY_DIR, DictionaryError, load
from tests.support import DICTIONARY, REAL_LAKE, integration

# NutrientQualifier's raw values in Sources/AlmanacCore/Provenance/NutrientQualifier.swift.
SWIFT_QUALIFIERS = {"measured", "trace", "not_analysed", "below_loq", "borrowed",
                    "calculated_recipe", "calculated_factor", "zero_reported"}


class TheShippedDictionary(unittest.TestCase):
    def test_qualifiers_are_the_closed_set(self):
        self.assertEqual(set(DICTIONARY.qualifiers), SWIFT_QUALIFIERS)

    def test_only_trace_and_not_analysed_carry_no_amount(self):
        empty = {q for q, row in DICTIONARY.qualifiers.items() if row.amount_rule == "null"}
        self.assertEqual(empty, {"trace", "not_analysed"})

    def test_shippable_groups_are_a_b_and_n(self):
        self.assertEqual(DICTIONARY.shippable_groups, {"A", "B", "N"})

    def test_source_groups(self):
        self.assertEqual({ns: s.licence_group for ns, s in DICTIONARY.sources.items()},
                         {"usda": "A", "ciqual": "B", "cofid": "B", "afcd": "B", "almanac": "N"})

    def test_carbohydrate_definitions_stay_apart(self):
        def target(source, source_id):
            return next(m.nutrient_id for m in DICTIONARY.mappings
                        if m.source == source and m.source_nutrient_id == source_id)
        self.assertEqual(target("usda", "1005"), "carbohydrate_by_difference")
        self.assertEqual(target("ciqual", "31000"), "carbohydrate_available")
        self.assertEqual(target("cofid", "CHO"), "carbohydrate_available_monosaccharide")
        # CIQUAL's carbohydrate includes polyols (EU 1169/2011); AFCD's matching column is "with".
        self.assertEqual(target("afcd", "Available carbohydrate, with sugar alcohols (g)"),
                         "carbohydrate_available")

    def test_englyst_fibre_and_nlea_fat_are_not_mapped(self):
        mapped = {(m.source, m.source_nutrient_id) for m in DICTIONARY.mappings}
        self.assertNotIn(("cofid", "ENGFIB"), mapped)
        self.assertNotIn(("usda", "1085"), mapped)

    def test_every_calorie_input_is_mapped_for_every_source(self):
        needed = {"energy_kcal", "protein", "fat_total", "fibre_total_dietary", "alcohol"}
        for source in ("usda", "ciqual", "cofid", "afcd"):
            with self.subTest(source=source):
                self.assertLessEqual(needed, set(DICTIONARY.mappings_for(source)))

    def test_digest_is_stable(self):
        self.assertEqual(load().sha256, DICTIONARY.sha256)


class ContradictionsAreRefused(unittest.TestCase):
    def mutated(self, name, edit):
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        for f in DICTIONARY_DIR.iterdir():
            shutil.copy(f, directory / f.name)
        path = directory / name
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        header = list(rows[0])
        edit(rows)
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, header, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        return directory

    def test_a_token_may_not_map_to_a_qualifier_that_needs_a_number(self):
        def edit(rows):
            rows[0]["qualifier"] = "zero_reported"
        with self.assertRaisesRegex(DictionaryError, "token may only map"):
            load(self.mutated("value_tokens.csv", edit))

    def test_unknown_nutrient(self):
        def edit(rows):
            rows[0]["nutrient_id"] = "vitamin_q"
        with self.assertRaisesRegex(DictionaryError, "unknown nutrient"):
            load(self.mutated("nutrient_map.csv", edit))

    def test_unit_mismatch_without_conversion(self):
        def edit(rows):
            row = next(r for r in rows if r["unit_conversion"] == "kj_to_kcal")
            row["unit_conversion"] = ""
        with self.assertRaisesRegex(DictionaryError, "no unit_conversion"):
            load(self.mutated("nutrient_map.csv", edit))

    def test_a_source_with_an_unknown_licence_group(self):
        def edit(rows):
            rows[0]["licence_group"] = "Z"
        with self.assertRaisesRegex(DictionaryError, "unknown licence group"):
            load(self.mutated("sources.csv", edit))


class AgainstTheRealLake(unittest.TestCase):
    @integration
    def test_every_usda_derivation_code_is_mapped(self):
        table = (REAL_LAKE.source_dir("usda") / "FoodData_Central_csv_2026-04-30" /
                 "food_nutrient_derivation.csv")
        with open(table, newline="", encoding="utf-8") as f:
            codes = {r["code"] for r in csv.DictReader(f)}
        self.assertLessEqual(codes, set(DICTIONARY.derivations_for("usda")))


if __name__ == "__main__":
    unittest.main()
