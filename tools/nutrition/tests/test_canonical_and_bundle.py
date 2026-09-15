import dataclasses
import sqlite3
import unittest
from contextlib import closing

from almanac_nutrition import bundle
from almanac_nutrition.canonical_io import CanonicalError, read_canonical, write_canonical
from almanac_nutrition.dictionary import Source
from almanac_nutrition.licence import LicenceViolation, assert_shippable
from almanac_nutrition.model import Food, FoodName, Value, validate
from tests.support import DICTIONARY, canonical_set, temp_lake


def replace_value(values, index, **changes):
    values = list(values)
    values[index] = dataclasses.replace(values[index], **changes)
    return values


class Validation(unittest.TestCase):
    def test_the_sample_set_is_valid(self):
        self.assertEqual(validate(*canonical_set(), DICTIONARY, namespace="cofid"), [])

    def test_trace_coerced_to_zero_is_caught_twice(self):
        foods, names, values = canonical_set()
        bad = replace_value(values, 1, amount=0.0, qualifier="zero_reported")  # 'Tr' -> 0
        problems = validate(foods, names, bad, DICTIONARY)
        self.assertTrue(any("only an explicit zero may become 0" in p for p in problems), problems)

    def test_tokens_may_not_carry_amounts(self):
        foods, names, values = canonical_set()
        problems = validate(foods, names, replace_value(values, 2, amount=0.0), DICTIONARY)
        self.assertTrue(any("never coerced" in p for p in problems), problems)

    def test_numeric_qualifiers_need_amounts(self):
        foods, names, values = canonical_set()
        problems = validate(foods, names, replace_value(values, 0, amount=None), DICTIONARY)
        self.assertTrue(any("requires an amount" in p for p in problems), problems)

    def test_duplicate_values_and_bad_basis(self):
        foods, names, values = canonical_set()
        problems = validate(foods, names, values + [values[0]], DICTIONARY)
        self.assertTrue(any("duplicate value" in p for p in problems))
        problems = validate(foods, names, replace_value(values, 0, basis="per_serving"), DICTIONARY)
        self.assertTrue(any("basis" in p for p in problems))

    def test_licence_group_must_match_the_registry(self):
        foods, names, values = canonical_set()
        foods = [dataclasses.replace(foods[0], licence_group="A")] + foods[1:]
        problems = validate(foods, names, values, DICTIONARY)
        self.assertTrue(any("sources.csv says 'B'" in p for p in problems), problems)

    def test_every_food_needs_exactly_one_primary_name(self):
        foods, names, values = canonical_set()
        problems = validate(foods, names[1:], values, DICTIONARY)
        self.assertTrue(any("0 primary names" in p for p in problems))

    def test_namespace_is_confined_in_the_canonical_stage(self):
        foods, names, values = canonical_set("usda")
        problems = validate(foods, names, values, DICTIONARY, namespace="cofid")
        self.assertTrue(any("in canonical/cofid" in p for p in problems))


class CanonicalFiles(unittest.TestCase):
    def test_round_trip(self):
        lake = temp_lake(self)
        foods, names, values = canonical_set()
        write_canonical(lake.canonical("cofid"), namespace="cofid", foods=foods, names=names,
                        values=values, dictionary=DICTIONARY, inputs=[])
        f, n, v, p, manifest = read_canonical(lake.canonical("cofid"))
        self.assertEqual((sorted(f, key=lambda x: x.food_ref), len(n)), (foods, len(names)))
        self.assertEqual(sorted(v, key=lambda x: (x.food_ref, x.nutrient_id)),
                         sorted(values, key=lambda x: (x.food_ref, x.nutrient_id)))
        self.assertEqual(manifest["counts"]["values_by_qualifier"]["trace"], 2)

    def test_an_invalid_set_leaves_the_previous_output_untouched(self):
        lake = temp_lake(self)
        foods, names, values = canonical_set()
        write_canonical(lake.canonical("cofid"), namespace="cofid", foods=foods, names=names,
                        values=values, dictionary=DICTIONARY, inputs=[])
        before = (lake.canonical("cofid") / "values.csv").read_bytes()
        with self.assertRaises(CanonicalError):
            write_canonical(lake.canonical("cofid"), namespace="cofid", foods=foods, names=names,
                            values=replace_value(values, 1, amount=0.0), dictionary=DICTIONARY,
                            inputs=[])
        self.assertEqual((lake.canonical("cofid") / "values.csv").read_bytes(), before)

    def test_an_edited_file_is_refused(self):
        lake = temp_lake(self)
        write_source(lake, "cofid")
        path = lake.canonical("cofid") / "values.csv"
        path.write_text(path.read_text().replace(",Tr,", ",0,"))
        with self.assertRaisesRegex(CanonicalError, "does not match its manifest"):
            read_canonical(lake.canonical("cofid"))


class LicenceGuard(unittest.TestCase):
    def test_restricted_rows_fail_loudly_with_their_identifiers(self):
        rows = [("usda:1", "A"), ("cofid:13-145", "B"), ("almanac:kabsa", "N"), ("sfda:kabsa-01", "D")]
        with self.assertRaises(LicenceViolation) as caught:
            assert_shippable(rows, DICTIONARY.shippable_groups)
        self.assertIn("sfda:kabsa-01 (group D)", str(caught.exception))
        self.assertIn("BUILD FAILURE", str(caught.exception))

    def test_native_rows_ship(self):
        self.assertEqual(assert_shippable([("almanac:kabsa", "N")], DICTIONARY.shippable_groups), 1)


def write_source(lake, namespace, dictionary=DICTIONARY, group=None, count=2):
    foods, names, values = canonical_set(namespace, count, dictionary, group)
    write_canonical(lake.canonical(namespace), namespace=namespace, foods=foods, names=names,
                    values=values, dictionary=dictionary, inputs=[])


class UnionAndBundle(unittest.TestCase):
    def test_bundle_holds_every_source_and_its_attribution(self):
        lake = temp_lake(self)
        write_source(lake, "usda")
        write_source(lake, "cofid", count=3)
        bundle.union(lake, DICTIONARY)
        report = bundle.build(lake, DICTIONARY)
        self.assertEqual(report["namespaces"], ["cofid", "usda"])
        with closing(sqlite3.connect(lake.bundle)) as con:
            self.assertEqual(con.execute("SELECT COUNT(*) FROM nutrition_food").fetchone()[0], 5)
            self.assertEqual(con.execute("SELECT value FROM bundle_meta WHERE key='schema_version'")
                             .fetchone()[0], "1")
            attribution = con.execute("SELECT attribution FROM nutrition_source WHERE namespace='cofid'"
                                      ).fetchone()[0]
            self.assertIn("Open Government Licence", attribution)
            trace = con.execute("SELECT amount, source_value FROM nutrition_value "
                                "WHERE qualifier='trace'").fetchall()
            self.assertTrue(trace and all(row == (None, "Tr") for row in trace))

    def test_the_bundle_schema_itself_refuses_restricted_and_coerced_rows(self):
        lake = temp_lake(self)
        write_source(lake, "usda")
        bundle.union(lake, DICTIONARY)
        bundle.build(lake, DICTIONARY)
        with closing(sqlite3.connect(lake.bundle)) as con:
            con.execute("PRAGMA foreign_keys = ON")
            with self.assertRaises(sqlite3.IntegrityError):
                con.execute("INSERT INTO nutrition_food VALUES ('usda:x', 'usda', 'x', 'D', '', '', '')")
            with self.assertRaises(sqlite3.IntegrityError):
                con.execute("INSERT INTO nutrition_value VALUES ('usda:1-1', 'alcohol', 'per_100g', 0.0,"
                            " 'trace', NULL, 'Tr', 'ALCO', 'g', 'A')")

    def test_deleting_a_canonical_source_removes_it_from_the_next_bundle(self):
        lake = temp_lake(self)
        write_source(lake, "usda")
        write_source(lake, "cofid")
        bundle.union(lake, DICTIONARY)
        bundle.build(lake, DICTIONARY)
        import shutil
        shutil.rmtree(lake.canonical("cofid"))
        bundle.union(lake, DICTIONARY)
        self.assertEqual(bundle.build(lake, DICTIONARY)["namespaces"], ["usda"])

    def test_a_group_d_source_fails_the_build_and_leaves_the_old_bundle(self):
        lake = temp_lake(self)
        write_source(lake, "usda")
        bundle.union(lake, DICTIONARY)
        bundle.build(lake, DICTIONARY)
        before = lake.bundle.read_bytes()

        sfda = Source("sfda", "sfda", "SFDA", "2026", "unclear", "D", "", "")
        restricted = dataclasses.replace(DICTIONARY, sources={**DICTIONARY.sources, "sfda": sfda})
        write_source(lake, "sfda", restricted)
        bundle.union(lake, restricted)  # union may hold group D: it never ships
        with self.assertRaisesRegex(LicenceViolation, r"sfda:1-1 \(group D\)"):
            bundle.build(lake, restricted)
        self.assertEqual(lake.bundle.read_bytes(), before)
        self.assertFalse(any(p.name.endswith(".partial") for p in lake.bundle.parent.iterdir()))

    def test_union_refuses_stale_or_unregistered_canonical_directories(self):
        lake = temp_lake(self)
        write_source(lake, "usda")
        stale = dataclasses.replace(DICTIONARY, sha256="0" * 64)
        with self.assertRaisesRegex(CanonicalError, "different dictionary"):
            bundle.union(lake, stale)
        (lake.canonical_root / "nevo").mkdir()
        with self.assertRaisesRegex(CanonicalError, "nevo: namespace is not in"):
            bundle.union(lake, DICTIONARY)


if __name__ == "__main__":
    unittest.main()
