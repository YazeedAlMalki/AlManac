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
    ])
    write_table(base / "foundation_food.csv", ["fdc_id", "NDB_number", "footnote"],
                [["1001", "20038", ""], ["1004", "4053", ""]])
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
    write_table(base / "measure_unit.csv", ["id", "name"], [["1000", "cup"]])
    write_table(base / "food_nutrient.csv", FN_HEADER, [
        fn("1", "1001", "1003", "13.2", "49"), fn("2", "1001", "1004", "6.52", "1"),
        fn("3", "1001", "1005", "67.7", "49"), fn("4", "1001", "2047", "384", "49"),
        fn("5", "1001", "2048", "379", "1"), fn("6", "1001", "1079", "10.1", ""),
        fn("7", "1001", "1018", "0.0", "1"), fn("8", "1001", "1051", "10.8", "1"),
        fn("9", "1001", "2033", "11.0", "1"),
        fn("10", "1004", "1004", "100.0", "1"), fn("11", "1004", "1008", "884", "49"),
        fn("12", "1004", "2048", "880", "49"), fn("13", "1004", "1003", "0.00", "68"),
        fn("14", "1002", "1003", "3.3", "1"), fn("15", "1003", "1003", "8.0", "71"),
        *extra_nutrient_rows,
    ])
    write_table(base / "food_portion.csv", ["id", "fdc_id", "seq_num", "amount", "measure_unit_id",
                                            "portion_description", "modifier", "gram_weight",
                                            "data_points", "footnote", "min_year_acquired"],
                [["1", "1001", "1", "1.0", "1000", "", "", "81.0", "", "", ""],
                 ["2", "1003", "1", "1.0", "9999", "", "bar", "40.0", "", "", ""]])
    register(lake, "usda", LOCAL, [f"{FOLDER}/{t}" for t in usda.SCOPED_TABLES + usda.WHOLE_TABLES],
             release="2026-04-30")
    return lake


def values_of(lake):
    _, _, values, manifest = read_canonical(lake.canonical("usda"))
    return {(v.food_ref, v.nutrient_id): v for v in values}, manifest


class Extract(unittest.TestCase):
    def test_refuses_inputs_that_differ_from_the_collection_manifest(self):
        lake = fixture_lake(self)
        (lake.root / LOCAL / FOLDER / "food.csv").write_text("tampered\n")
        with self.assertRaises(InputVerificationError):
            usda.extract(lake)
        self.assertFalse(lake.extracted("usda").exists())

    def test_keeps_foundation_rows_only_in_usdas_own_shape(self):
        lake = fixture_lake(self)
        out = usda.extract(lake)
        self.assertEqual([r["fdc_id"] for r in read_csv(out / "food.csv")], ["1001", "1002", "1004"])
        self.assertEqual({r["fdc_id"] for r in read_csv(out / "food_nutrient.csv")},
                         {"1001", "1002", "1004"})
        self.assertEqual([r["fdc_id"] for r in read_csv(out / "food_portion.csv")], ["1001"])
        with open(out / "food.csv", newline="") as f:
            self.assertEqual(next(csv.reader(f))[0], "fdc_id")
        self.assertEqual(read_csv(out / "food.csv")[0]["description"], "Oats, raw ")


class Canonicalise(unittest.TestCase):
    def setUp(self):
        self.lake = fixture_lake(self)
        usda.extract(self.lake)
        usda.canonicalise(self.lake, DICTIONARY)
        self.values, self.manifest = values_of(self.lake)

    def test_only_listed_foundation_foods_and_the_rest_are_recorded(self):
        foods, names, _, _ = read_canonical(self.lake.canonical("usda"))
        self.assertEqual([f.food_ref for f in foods], ["usda:1001", "usda:1004"])
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
            (Path(out) / LOCAL).symlink_to(REAL_LAKE.root / LOCAL)
            usda.extract(scratch)
            manifest = usda.canonicalise(scratch, DICTIONARY)
        self.assertEqual(manifest["counts"]["foods"], 395)
        self.assertEqual(len(manifest["notes"]["excluded"]), 74)
        self.assertNotIn("trace", manifest["counts"]["values_by_qualifier"])


if __name__ == "__main__":
    unittest.main()
