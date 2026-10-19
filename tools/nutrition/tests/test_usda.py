import csv
import unittest

from almanac_nutrition.canonical_io import CanonicalError, read_canonical
from almanac_nutrition.lake import InputVerificationError, read_csv
from almanac_nutrition.sources import load_sources, usda
from tests.support import DICTIONARY, REAL_LAKE, integration, register, temp_lake, write_table

LOCAL = "FoodData Central United States"
FOLDER = usda.RELEASE_FOLDER
FN_HEADER = ["id", "fdc_id", "nutrient_id", "amount", "data_points", "derivation_id", "min", "max",
             "median", "loq", "footnote", "min_year_acquired", "percent_daily_value"]


def fn(row_id, fdc_id, nutrient_id, amount, derivation_id):
    return [row_id, fdc_id, nutrient_id, amount, "", derivation_id, "", "", "", "", "", "", ""]


def fixture_lake(case, extra_nutrient_rows=(), derivations=None):
    lake = temp_lake(case)
    base = lake.root / LOCAL / FOLDER
    write_table(base / "food.csv", ["fdc_id", "data_type", "description", "food_category_id",
                                    "publication_date"], [
        ["1001", "foundation_food", "Oats, raw ", "1", "2024-04-01"],
        ["1002", "foundation_food", "Milk, whole (2019 version)", "1", "2019-04-01"],
        ["1003", "branded_food", "BRAND BAR", "Snacks", "2020-11-13"],
        ["1004", "foundation_food", "Oil, olive", "2", "2024-04-01"],
        ["2001", "sr_legacy_food", "Oats", "1", "2019-04-01"],
        ["3001", "survey_fndds_food", "Oatmeal, cooked", "", "2024-10-31"],
        ["3002", "survey_fndds_food", "Apple, raw", "", "2024-10-31"],
    ])
    write_table(base / "foundation_food.csv", ["fdc_id", "NDB_number", "footnote"],
                [["1001", "20038", ""], ["1004", "4053", ""]])
    write_table(base / "sr_legacy_food.csv", ["fdc_id", "NDB_number"], [["2001", "20038"]])
    write_table(base / "survey_fndds_food.csv", ["fdc_id", "food_code", "wweia_category_number",
                                                 "start_date", "end_date"],
                [["3001", "56203000", "4802", "2021-01-01", "2023-12-31"],
                 ["3002", "63101000", "6002", "2021-01-01", "2023-12-31"]])
    write_table(base / "wweia_food_category.csv", ["wweia_food_category", "wweia_food_category_description"],
                [["4802", "Oatmeal"], ["6002", "Apples"]])
    write_table(base / "input_food.csv", ["id", "fdc_id", "fdc_id_of_input_food", "seq_num", "amount",
                                          "sr_code", "sr_description", "unit", "portion_code",
                                          "portion_description", "gram_weight", "retention_code",
                                          "survey_flag"],
                [["1", "3001", "2001", "1", "40", "20038", "Oats", "GM", "", "", "40", "", ""],
                 ["2", "3001", "9001", "2", "200", "14411", "Water", "GM", "", "", "200", "", ""],
                 ["3", "3002", "2002", "1", "100", "9003", "Apples, raw", "GM", "", "", "100", "", ""]])
    write_table(base / "nutrient.csv", ["id", "name", "unit_name", "nutrient_nbr", "rank"], [
        ["1003", "Protein", "G", "203", "600"], ["1004", "Total lipid (fat)", "G", "204", "800"],
        ["1005", "Carbohydrate, by difference", "G", "205", "1110"], ["1008", "Energy", "KCAL", "208", "300"],
        ["1018", "Alcohol, ethyl", "G", "221", "18200"], ["1050", "Carbohydrate, by summation", "G", "205.2", "1120"],
        ["1051", "Water", "G", "255", "100"], ["1079", "Fiber, total dietary", "G", "291", "1200"],
        ["2033", "Total dietary fiber (AOAC 2011.25)", "G", "293", "1201"],
        ["2047", "Energy (Atwater General Factors)", "KCAL", "957", "280"],
        ["2048", "Energy (Atwater Specific Factors)", "KCAL", "958", "290"],
    ])
    write_table(base / "food_nutrient_derivation.csv", ["id", "code", "description"], derivations or [
        ["1", "A", "Analytical"], ["4", "AS", "Summed"], ["49", "NC", "Calculated"],
        ["68", "Z", "Assumed zero"]])
    write_table(base / "food_category.csv", ["id", "code", "description"],
                [["1", "0100", "Dairy and Egg Products"], ["2", "0400", "Fats and Oils"]])
    write_table(base / "measure_unit.csv", ["id", "name"], [["1000", "cup"], ["9999", "undetermined"]])
    write_table(base / "food_nutrient.csv", FN_HEADER, [
        fn("1", "1001", "1003", "13.2", "49"), fn("2", "1001", "1004", "6.52", "1"),
        fn("3", "1001", "1005", "67.7", "49"), fn("4", "1001", "2047", "384", "49"),
        fn("5", "1001", "2048", "379", "1"), fn("6", "1001", "1079", "10.1", ""),
        fn("7", "1001", "1018", "0.0", "1"), fn("8", "1001", "1051", "10.8", "1"),
        fn("9", "1001", "2033", "11.0", "1"),
        fn("10", "1004", "1004", "100.0", "1"), fn("11", "1004", "1008", "884", "49"),
        fn("12", "1004", "2048", "880", "49"), fn("13", "1004", "1003", "0.00", "68"),
        fn("14", "1002", "1003", "3.3", "1"), fn("15", "1003", "1003", "8.0", "71"),
        fn("16", "2001", "1003", "16.9", "1"), fn("17", "2001", "1008", "389", "49"),
        fn("18", "3001", "1003", "2.4", ""), fn("19", "3001", "1008", "71", ""),
        fn("20", "3002", "1004", "0.17", ""),
        *extra_nutrient_rows,
    ])
    write_table(base / "food_portion.csv", ["id", "fdc_id", "seq_num", "amount", "measure_unit_id",
                                            "portion_description", "modifier", "gram_weight",
                                            "data_points", "footnote", "min_year_acquired"],
                [["1", "1001", "1", "1.0", "1000", "", "", "81.0", "", "", ""],
                 ["2", "1003", "1", "1.0", "9999", "", "bar", "40.0", "", "", ""],
                 ["3", "2001", "1", "1.0", "9999", "", "cup", "81.0", "", "", ""],
                 ["4", "3001", "1", "", "9999", "1 cup", "10205", "234.0", "", "", ""],
                 ["5", "3002", "1", "", "9999", "", "", "182.0", "", "", ""]])
    register(lake, "usda", LOCAL, [f"{FOLDER}/{t}" for t in usda.SCOPED_TABLES + usda.WHOLE_TABLES],
             release="2026-04-30")
    return lake


def values_of(lake):
    _, _, values, _, manifest = read_canonical(lake.canonical("usda"))
    return {(v.food_ref, v.nutrient_id): v for v in values}, manifest


class Extract(unittest.TestCase):
    def test_refuses_inputs_that_differ_from_the_collection_manifest(self):
        lake = fixture_lake(self)
        (lake.root / LOCAL / FOLDER / "food.csv").write_text("tampered\n")
        with self.assertRaises(InputVerificationError):
            usda.extract(lake)
        self.assertFalse(lake.extracted("usda").exists())

    def test_keeps_the_three_data_types_only_in_usdas_own_shape(self):
        lake = fixture_lake(self)
        out = usda.extract(lake)
        kept = ["1001", "1002", "1004", "2001", "3001", "3002"]
        self.assertEqual([r["fdc_id"] for r in read_csv(out / "food.csv")], kept)
        self.assertEqual({r["fdc_id"] for r in read_csv(out / "food_nutrient.csv")}, set(kept))
        self.assertEqual([r["fdc_id"] for r in read_csv(out / "food_portion.csv")],
                         ["1001", "2001", "3001", "3002"])
        self.assertEqual([r["fdc_id"] for r in read_csv(out / "input_food.csv")], ["3001", "3001", "3002"])
        with open(out / "food.csv", newline="") as f:
            self.assertEqual(next(csv.reader(f))[0], "fdc_id")
        self.assertEqual(read_csv(out / "food.csv")[0]["description"], "Oats, raw ")


class Canonicalise(unittest.TestCase):
    def setUp(self):
        self.lake = fixture_lake(self)
        usda.extract(self.lake)
        usda.canonicalise(self.lake, DICTIONARY)
        self.values, self.manifest = values_of(self.lake)

    def test_only_listed_foods_and_the_rest_are_recorded(self):
        foods, names, _, _, _ = read_canonical(self.lake.canonical("usda"))
        self.assertEqual([f.food_ref for f in foods],
                         ["usda:1001", "usda:1004", "usda:2001", "usda:3001", "usda:3002"])
        self.assertEqual(self.manifest["notes"]["foods_by_data_type"],
                         {"foundation_food": 2, "sr_legacy_food": 1, "survey_fndds_food": 2})
        self.assertEqual([e["fdc_id"] for e in self.manifest["notes"]["excluded"]], ["1002"])
        self.assertEqual(names[0].name, "Oats, raw")
        self.assertEqual((foods[0].food_group_code, foods[0].food_group_name),
                         ("0100", "Dairy and Egg Products"))
        self.assertTrue(all(f.licence_group == "A" for f in foods))

    def test_energy_priority_and_the_published_general_atwater_figure(self):
        oats, oil = self.values[("usda:1001", "energy_kcal")], self.values[("usda:1004", "energy_kcal")]
        self.assertEqual((oats.source_nutrient_id, oats.amount), ("2048", 379.0))
        self.assertEqual((oil.source_nutrient_id, oil.amount), ("1008", 884.0))
        general = self.values[("usda:1001", "energy_general_atwater_kcal")]
        self.assertEqual((general.amount, general.source_unit), (384.0, "KCAL"))
        # Energy is never measured, whatever derivation code USDA attached (2048 here is 'A').
        self.assertEqual(oats.qualifier, "calculated_factor")

    def test_qualifiers_follow_the_derivation_codes(self):
        self.assertEqual(self.values[("usda:1001", "protein")].qualifier, "calculated_factor")  # NC
        self.assertEqual(self.values[("usda:1001", "fat_total")].qualifier, "measured")  # A
        fibre = self.values[("usda:1001", "fibre_total_dietary")]
        self.assertEqual((fibre.source_nutrient_id, fibre.qualifier, fibre.confidence), ("1079", "measured", ""))
        zero = self.values[("usda:1004", "protein")]
        self.assertEqual((zero.amount, zero.qualifier, zero.source_value, zero.confidence),
                         (0.0, "zero_reported", "0.00", "Z"))
        self.assertEqual(self.values[("usda:1001", "alcohol")].qualifier, "zero_reported")

    def test_source_values_are_verbatim_and_unmapped_nutrients_are_not_canonical(self):
        fat = self.values[("usda:1001", "fat_total")]
        self.assertEqual((fat.source_value, fat.source_unit, fat.basis), ("6.52", "G", "per_100g"))
        self.assertNotIn(("usda:1001", "water"), self.values)
        self.assertEqual({n for _, n in self.values} - set(DICTIONARY.nutrients), set())

    def test_each_food_keeps_its_own_code_and_a_sole_fndds_ingredient(self):
        foods = {f.food_ref: f for f in read_canonical(self.lake.canonical("usda"))[0]}
        self.assertEqual(foods["usda:1001"].source_record,
                         "food.csv fdc_id=1001; foundation_food.csv NDB_number=20038")
        self.assertEqual(foods["usda:2001"].source_record,
                         "food.csv fdc_id=2001; sr_legacy_food.csv NDB_number=20038")
        # Two ingredients (oats and water): no sole input.
        self.assertEqual(foods["usda:3001"].source_record,
                         "food.csv fdc_id=3001; survey_fndds_food.csv food_code=56203000")
        self.assertEqual(foods["usda:3002"].source_record,
                         "food.csv fdc_id=3002; survey_fndds_food.csv food_code=63101000; "
                         "input_food.csv sole input fdc_id=2002 sr_code=9003")
        self.assertEqual((foods["usda:3002"].food_group_code, foods["usda:3002"].food_group_name),
                         ("6002", "Apples"))

    def test_fndds_values_are_recipe_calculations_with_no_code_invented(self):
        protein = self.values[("usda:3001", "protein")]
        self.assertEqual((protein.qualifier, protein.confidence), ("calculated_recipe", ""))
        self.assertEqual(self.values[("usda:3001", "energy_kcal")].qualifier, "calculated_factor")
        self.assertEqual(self.values[("usda:2001", "protein")].qualifier, "measured")

    def test_sr_and_fndds_portions_are_named_in_the_publishers_words(self):
        portions = {p.source_record: p for p in read_canonical(self.lake.canonical("usda"))[3]}
        sr, fndds = portions["food_portion.csv id=3"], portions["food_portion.csv id=4"]
        self.assertEqual((sr.unit, sr.amount, sr.value), ("cup", 1.0, 81.0))
        self.assertEqual((fndds.unit, fndds.amount, fndds.value, fndds.modifier), ("1 cup", 1.0, 234.0, "10205"))
        self.assertNotIn("food_portion.csv id=5", portions)
        self.assertEqual(self.manifest["notes"]["portions_with_no_measure_name"], ["food_portion.csv id=5"])

    def test_reruns_are_byte_identical(self):
        first = self.manifest["outputs"]
        usda.canonicalise(self.lake, DICTIONARY)
        self.assertEqual(values_of(self.lake)[1]["outputs"], first)

    def test_discovered_by_the_cli(self):
        self.assertIs(load_sources()["usda"], usda)


class Refusals(unittest.TestCase):
    def test_an_unmapped_derivation_code_fails(self):
        lake = fixture_lake(self, extra_nutrient_rows=[fn("99", "1004", "1005", "0.5", "900")],
                           derivations=[["1", "A", "Analytical"], ["49", "NC", "Calculated"],
                                        ["68", "Z", "Assumed zero"], ["900", "QQ", "Invented"]])
        usda.extract(lake)
        with self.assertRaisesRegex(CanonicalError, "'QQ' has no row"):
            usda.canonicalise(lake, DICTIONARY)

    def test_a_nonzero_assumed_zero_fails(self):
        lake = fixture_lake(self, extra_nutrient_rows=[fn("99", "1004", "1005", "0.5", "68")])
        usda.extract(lake)
        with self.assertRaisesRegex(CanonicalError, "zero_reported with amount 0.5"):
            usda.canonicalise(lake, DICTIONARY)

    def test_a_negative_amount_produces_no_row_and_is_recorded(self):
        lake = fixture_lake(self, extra_nutrient_rows=[fn("99", "1004", "1005", "-0.47505", "49")])
        usda.extract(lake)
        manifest = usda.canonicalise(lake, DICTIONARY)
        self.assertNotIn(("usda:1004", "carbohydrate_by_difference"), values_of(lake)[0])
        self.assertEqual(manifest["notes"]["rejected_values"],
                         [{"food_ref": "usda:1004", "source_nutrient_id": "1005",
                           "source_value": "-0.47505", "reason": "negative amount"}])

    def test_a_duplicate_in_an_unmapped_nutrient_is_recorded_not_fatal(self):
        lake = fixture_lake(self, extra_nutrient_rows=[fn("99", "1001", "1051", "10.8", "1")])
        usda.extract(lake)
        manifest = usda.canonicalise(lake, DICTIONARY)
        self.assertEqual(manifest["notes"]["unmapped_duplicates"],
                         [{"fdc_id": "1001", "nutrient_id": "1051", "food_nutrient_ids": ["8", "99"]}])

    def test_duplicate_rows_for_one_nutrient_fail(self):
        lake = fixture_lake(self, extra_nutrient_rows=[fn("99", "1001", "1003", "13.3", "1")])
        usda.extract(lake)
        with self.assertRaisesRegex(CanonicalError, "two food_nutrient rows"):
            usda.canonicalise(lake, DICTIONARY)


class AgainstTheRealLake(unittest.TestCase):
    @integration
    def test_foundation_foods(self):
        import tempfile
        from pathlib import Path
        from almanac_nutrition.lake import Lake
        with tempfile.TemporaryDirectory() as out:
            # Read the real raw data, write into a scratch lake that mirrors it by symlink.
            scratch = Lake(out)
            (Path(out) / "manifests").symlink_to(REAL_LAKE.manifests)
            local_path = REAL_LAKE.manifest("usda")["local_path"]
            link = Path(out) / local_path
            link.parent.mkdir(parents=True)
            link.symlink_to(REAL_LAKE.root / local_path)
            usda.extract(scratch)
            manifest = usda.canonicalise(scratch, DICTIONARY)
        self.assertEqual(manifest["counts"]["foods"], 395)
        self.assertEqual(len(manifest["notes"]["excluded"]), 74)
        self.assertNotIn("trace", manifest["counts"]["values_by_qualifier"])


if __name__ == "__main__":
    unittest.main()
