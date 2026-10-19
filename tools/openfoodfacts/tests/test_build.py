import sqlite3
import tempfile
import unittest
from pathlib import Path

from almanac_off.build import Product, build_records, check, write_db


def product(code, name="Laban", brands="Almarai", modified=1, **values):
    v = {"energy-kcal_100g": "60", "proteins_100g": "3", "fat_100g": "3", "carbohydrates_100g": "4.5"}
    v.update(values)
    v = {k: x for k, x in v.items() if x is not None}
    p = Product(code, name, brands, "1 l", "", None, ["en:saudi-arabia"], "", modified, v, "per_100ml")
    p.excluded = check(p)
    return p


class OffTests(unittest.TestCase):
    def test_leading_zero_barcodes_are_one_product(self):
        records, matches, _ = build_records([product("06281007000012"), product("6281007000012", modified=2)])
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["ref"], "off:6281007000012")  # the newer edit is the base
        self.assertEqual(matches[0]["why"], "barcode")

    def test_same_brand_and_name_with_matching_nutrition_merge_and_conflicts_keep_both(self):
        records, _, _ = build_records([product("1"), product("2", proteins_100g="3.2")])
        self.assertEqual(len(records), 1)
        self.assertEqual({v["value"] for v in records[0]["conflicts"][0]["values"]}, {"3", "3.2"})

    def test_different_nutrition_or_no_brand_stay_apart(self):
        records, _, _ = build_records([product("1"), product("2", fat_100g="0.1"),
                                       product("3", brands=""), product("4", brands="")])
        self.assertEqual(len(records), 4)

    def test_impossible_or_missing_values_exclude_the_product(self):
        self.assertIsNotNone(product("1", fat_100g="120").excluded)
        self.assertIsNotNone(product("2", proteins_100g="-1").excluded)
        self.assertIsNotNone(product("3", **{"energy-kcal_100g": None}).excluded)
        self.assertIsNone(product("4", **{"energy-kcal_100g": None, "energy-kj_100g": "251"}).excluded)

    def test_kilojoules_convert_and_stay_traceable(self):
        records, _, _ = build_records([product("1", **{"energy-kcal_100g": None, "energy-kj_100g": "251"})])
        energy = records[0]["values"]["energy_kcal"]
        self.assertAlmostEqual(energy["amount"], 60.0, places=1)
        self.assertEqual((energy["sourceValue"], energy["unit"]), ("251", "kJ"))

    def test_database_keeps_every_barcode_and_member(self):
        records, _, _ = build_records([product("1"), product("2", proteins_100g="3.2", modified=2)])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "off.sqlite"
            write_db(records, "sha", path)
            con = sqlite3.connect(path)
            self.assertEqual(con.execute("SELECT code FROM off_barcode ORDER BY code").fetchall(), [("1",), ("2",)])
            self.assertEqual(con.execute("SELECT code FROM off_member").fetchall(), [("1",)])
            self.assertEqual(con.execute("SELECT DISTINCT licence_group FROM off_product").fetchall(), [("C",)])


if __name__ == "__main__":
    unittest.main()
