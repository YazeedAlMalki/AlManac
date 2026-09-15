import tempfile
import unittest
from pathlib import Path
from xml.sax.saxutils import escape

from almanac_nutrition.canonical_io import CanonicalError, read_canonical
from almanac_nutrition.lake import InputVerificationError, Lake, read_csv
from almanac_nutrition.sources import ciqual, load_sources
from tests.support import DICTIONARY, REAL_LAKE, integration, register, temp_lake

LOCAL = "raw/ciqual/2025"
STAMP = "2025_11_03"

ALIM = [
    {"alim_code": "1000", "alim_nom_fr": "Pastis", "alim_nom_eng": "Pastis (anise-flavoured spirit)",
     "alim_nom_sci": None, "alim_grp_code": "06", "alim_ssgrp_code": "0603",
     "alim_ssssgrp_code": "060303", "facteur_Jones": "6.25"},
    {"alim_code": "2000", "alim_nom_fr": "Salade composée", "alim_nom_eng": "Mixed salad",
     "alim_nom_sci": None, "alim_grp_code": "01", "alim_ssgrp_code": "0101",
     "alim_ssssgrp_code": "000000", "facteur_Jones": "6.25"},
]
GROUPS = [
    {"alim_grp_code": "06", "alim_grp_nom_fr": "boissons", "alim_grp_nom_eng": "beverages",
     "alim_ssgrp_code": "0603", "alim_ssgrp_nom_fr": "boissons alcoolisées",
     "alim_ssgrp_nom_eng": "alcoholic beverages", "alim_ssssgrp_code": "060303",
     "alim_ssssgrp_nom_fr": "spiritueux", "alim_ssssgrp_nom_eng": "spirits"},
    {"alim_grp_code": "01", "alim_grp_nom_fr": "entrées", "alim_grp_nom_eng": "starters and dishes",
     "alim_ssgrp_code": "0101", "alim_ssgrp_nom_fr": "salades", "alim_ssgrp_nom_eng": "mixed salads",
     "alim_ssssgrp_code": "000000", "alim_ssssgrp_nom_fr": "-", "alim_ssssgrp_nom_eng": "-"},
]
CONST = {"328": "Energy, Regulation EU No 1169/2011 (kcal/100g)", "25000": "Protein (g/100g)",
         "40000": "Fat (g/100g)", "31000": "Carbohydrate (g/100g)", "34100": "Fibres (g/100g)",
         "60000": "Alcohol (g/100g)", "400": "Water (g/100g)"}


def compo(alim, const, teneur, confidence="A"):
    return {"alim_code": alim, "const_code": const, "teneur": teneur, "min": None, "max": None,
            "code_confiance": None if teneur == "-" else confidence, "source_code": "1"}


COMPO = [
    compo("1000", "328", "274", "D"), compo("1000", "25000", "0"), compo("1000", "40000", "traces"),
    compo("1000", "31000", "< 0,5", "B"), compo("1000", "34100", "-"), compo("1000", "60000", "31,7", "B"),
    compo("1000", "400", "59,7"),
    compo("2000", "328", "95", "D"), compo("2000", "25000", "2,31"), compo("2000", "40000", "6,8"),
    compo("2000", "31000", "8,1"), compo("2000", "34100", "1,9"), compo("2000", "60000", "0"),
]


def xml(tag, records):
    """A CIQUAL-shaped table: BOM, CRLF, padded text, missing=" " for absent values."""
    lines = ['﻿<?xml version="1.0" encoding="utf-8" ?>', "<TABLE>"]
    for record in records:
        lines.append(f"   <{tag}>")
        for element, text in record.items():
            lines.append(f'      <{element} missing=" " />' if text is None
                         else f"      <{element}> {escape(text)} </{element}>")
        lines.append(f"   </{tag}>")
    lines.append("</TABLE>")
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


def fixture_lake(case, compo_rows=COMPO, const=CONST):
    lake = temp_lake(case)
    base = lake.root / LOCAL
    base.mkdir(parents=True)
    tables = {
        "alim": ("ALIM", ALIM), "alim_grp": ("ALIM_GRP", GROUPS), "compo": ("COMPO", compo_rows),
        "const": ("CONST", [{"const_code": c, "const_nom_fr": n, "const_nom_eng": n, "code_INFOODS": "X"}
                            for c, n in const.items()]),
        "sources": ("SOURCES", [{"source_code": "1", "ref_citation": "Fixture"}]),
    }
    for table, (tag, records) in tables.items():
        (base / f"{table}_{STAMP}.xml").write_bytes(xml(tag, records))
    register(lake, "ciqual", LOCAL, [f"{t}_{STAMP}.xml" for t in tables], release="2025")
    return lake


def canonical(lake):
    foods, names, values, portions, manifest = read_canonical(lake.canonical("ciqual"))
    return foods, names, {(v.food_ref, v.nutrient_id): v for v in values}, manifest


class Extract(unittest.TestCase):
    def test_refuses_inputs_that_differ_from_the_collection_manifest(self):
        lake = fixture_lake(self)
        (lake.root / LOCAL / f"compo_{STAMP}.xml").write_bytes(b"<TABLE/>")
        with self.assertRaises(InputVerificationError):
            ciqual.extract(lake)
        self.assertFalse(lake.extracted("ciqual").exists())

    def test_one_column_per_element_trimmed_and_missing_as_empty(self):
        out = ciqual.extract(fixture_lake(self))
        rows = read_csv(out / "compo.csv")
        self.assertEqual(len(rows), len(COMPO))
        self.assertEqual(rows[3]["teneur"], "< 0,5")
        self.assertEqual((rows[4]["teneur"], rows[4]["code_confiance"], rows[4]["min"]), ("-", "", ""))
        self.assertEqual(read_csv(out / "alim.csv")[1]["alim_nom_fr"], "Salade composée")


class Canonicalise(unittest.TestCase):
    def setUp(self):
        self.lake = fixture_lake(self)
        ciqual.extract(self.lake)
        ciqual.canonicalise(self.lake, DICTIONARY)
        self.foods, self.names, self.values, self.manifest = canonical(self.lake)

    def test_tokens_have_no_amount_and_keep_their_text(self):
        fat, fibre = self.values[("ciqual:1000", "fat_total")], self.values[("ciqual:1000", "fibre_total_dietary")]
        self.assertEqual((fat.amount, fat.qualifier, fat.source_value), (None, "trace", "traces"))
        self.assertEqual((fibre.amount, fibre.qualifier, fibre.source_value, fibre.confidence),
                         (None, "not_analysed", "-", ""))

    def test_bounds_decimal_commas_zeros_and_confidence(self):
        carbohydrate = self.values[("ciqual:1000", "carbohydrate_available")]
        self.assertEqual((carbohydrate.amount, carbohydrate.qualifier, carbohydrate.source_value),
                         (0.5, "below_loq", "< 0,5"))
        alcohol = self.values[("ciqual:1000", "alcohol")]
        self.assertEqual((alcohol.amount, alcohol.qualifier, alcohol.confidence), (31.7, "measured", "B"))
        protein = self.values[("ciqual:1000", "protein")]
        self.assertEqual((protein.amount, protein.qualifier, protein.source_value), (0.0, "zero_reported", "0"))
        energy = self.values[("ciqual:1000", "energy_kcal")]
        self.assertEqual((energy.amount, energy.qualifier, energy.source_unit, energy.confidence),
                         (274.0, "calculated_factor", "kcal", "D"))

    def test_every_mapped_constituent_and_nothing_else(self):
        self.assertEqual(len(self.values), 12)
        self.assertNotIn(("ciqual:1000", "water"), self.values)
        self.assertTrue(all(v.basis == "per_100g" and v.licence_group == "B" for v in self.values.values()))

    def test_names_and_the_most_specific_used_group(self):
        spirit, salad = self.foods
        self.assertEqual((spirit.food_group_code, spirit.food_group_name), ("060303", "spirits"))
        self.assertEqual((salad.food_group_code, salad.food_group_name), ("0101", "mixed salads"))
        self.assertEqual({(n.food_ref, n.language, n.is_primary) for n in self.names},
                         {("ciqual:1000", "en", True), ("ciqual:1000", "fr", False),
                          ("ciqual:2000", "en", True), ("ciqual:2000", "fr", False)})

    def test_reruns_are_byte_identical_and_the_cli_finds_the_module(self):
        first = self.manifest["outputs"]
        ciqual.canonicalise(self.lake, DICTIONARY)
        self.assertEqual(canonical(self.lake)[3]["outputs"], first)
        self.assertIs(load_sources()["ciqual"], ciqual)


class Refusals(unittest.TestCase):
    def run_both(self, lake):
        ciqual.extract(lake)
        return ciqual.canonicalise(lake, DICTIONARY)

    def test_an_unknown_token_fails(self):
        rows = COMPO[:-1] + [compo("2000", "60000", "env. 3")]
        with self.assertRaisesRegex(CanonicalError, "neither a number nor a known token"):
            self.run_both(fixture_lake(self, rows))

    def test_a_unit_that_disagrees_with_the_mapping_fails(self):
        with self.assertRaisesRegex(CanonicalError, "unit 'kcal'"):
            self.run_both(fixture_lake(self, const={**CONST, "328": "Energy (kJ/100g)"}))

    def test_duplicate_rows_fail(self):
        with self.assertRaisesRegex(CanonicalError, "two rows"):
            self.run_both(fixture_lake(self, COMPO + [compo("2000", "60000", "0")]))

    def test_a_negative_amount_produces_no_row_and_is_recorded(self):
        manifest = self.run_both(fixture_lake(self, COMPO[:-1] + [compo("2000", "60000", "-0,2")]))
        self.assertEqual(manifest["notes"]["rejected_values"],
                         [{"food_ref": "ciqual:2000", "source_nutrient_id": "60000",
                           "source_value": "-0,2", "reason": "negative amount"}])


class AgainstTheRealLake(unittest.TestCase):
    @integration
    def test_every_food_and_every_mapped_constituent(self):
        with tempfile.TemporaryDirectory() as out:
            scratch = Lake(out)
            (Path(out) / "manifests").symlink_to(REAL_LAKE.manifests)
            (Path(out) / "raw").symlink_to(REAL_LAKE.root / "raw")
            ciqual.extract(scratch)
            manifest = ciqual.canonicalise(scratch, DICTIONARY)
            _, _, values, _, _ = read_canonical(scratch.canonical("ciqual"))
        self.assertEqual(manifest["counts"]["foods"], 3484)
        self.assertEqual(manifest["counts"]["values"], 3484 * 6)
        self.assertFalse([v for v in values if v.amount == 0 and v.source_value.strip() in ("traces", "-")])
        self.assertEqual(manifest["notes"]["food_groups_without_names"], [])


if __name__ == "__main__":
    unittest.main()
