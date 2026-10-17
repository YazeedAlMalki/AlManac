import sqlite3
import unittest

from almanac_nutrition import fixture
from tests.support import DICTIONARY


def contents(sql: str) -> dict:
    """Every table's schema and rows. Compared instead of the text, because SQLite
    versions spell the same REAL differently in a dump (3.45: 1.0e+00; macOS: 1.0)."""
    con = sqlite3.connect(":memory:")
    try:
        con.executescript(sql)
        tables = con.execute("SELECT name, sql FROM sqlite_master WHERE type = 'table' ORDER BY name").fetchall()
        return {name: (schema, sorted(con.execute(f'SELECT * FROM "{name}"').fetchall(), key=repr))
                for name, schema in tables}
    finally:
        con.close()


class CommittedFixture(unittest.TestCase):
    """AlmanacCore's tests import fixtures/bundle_v1.sql. It must be what the pipeline writes today."""

    def test_committed_fixture_is_current(self):
        self.assertTrue(fixture.FIXTURE_PATH.is_file(), "run: python3 -m almanac_nutrition fixture")
        self.assertEqual(contents(fixture.FIXTURE_PATH.read_text(encoding="utf-8")),
                         contents(fixture.render(DICTIONARY)),
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
