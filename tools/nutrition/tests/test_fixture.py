import unittest

from almanac_nutrition import fixture
from tests.support import DICTIONARY


class CommittedFixture(unittest.TestCase):
    """AlmanacCore's tests import fixtures/bundle_v1.sql. It must be what the pipeline writes today."""

    def test_committed_fixture_is_current(self):
        self.assertTrue(fixture.FIXTURE_PATH.is_file(), "run: python3 -m almanac_nutrition fixture")
        self.assertEqual(fixture.FIXTURE_PATH.read_text(encoding="utf-8"), fixture.render(DICTIONARY),
                         "fixtures/bundle_v1.sql is stale — run: python3 -m almanac_nutrition fixture")

    def test_fixture_covers_every_shippable_group_basis_and_qualifier(self):
        text = fixture.render(DICTIONARY)
        for group in DICTIONARY.shippable_groups:
            self.assertIn(f"'{group}'", text)
        for qualifier in ("measured", "trace", "not_analysed", "below_loq", "calculated_recipe",
                          "calculated_factor", "zero_reported"):
            self.assertIn(f"'{qualifier}'", text)
        self.assertIn("'per_100ml'", text)


if __name__ == "__main__":
    unittest.main()
