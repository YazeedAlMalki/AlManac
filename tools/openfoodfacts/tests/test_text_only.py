"""Open Food Facts is used as text only (owner, 2026-10-21; docs/features/open-food-facts.md).

Product photos are CC BY-SA with third-party rights in the packaging, so no image
field may be read from the export, stored in the database, or shown. These tests
fail if one is added.
"""
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path

from almanac_off import build
from almanac_off.build import write_db

IMAGE_WORD = re.compile(r"image|img|photo|picture|thumb|\bpic\b", re.IGNORECASE)
IMAGE_VALUE = re.compile(r"images\.openfoodfacts|static\.openfoodfacts|\.(jpe?g|png|webp|gif|svg)(\?|\b)",
                         re.IGNORECASE)
SHIPPED = build.OUT_DB


def schema(con: sqlite3.Connection) -> list[tuple[str, str]]:
    """(table, column) for every column in the database."""
    tables = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")]
    return [(t, r[1]) for t in tables for r in con.execute(f'PRAGMA table_info("{t}")')]


def text_values(con: sqlite3.Connection):
    """(table, column, value) for every non-empty text cell."""
    for table, column in schema(con):
        for (value,) in con.execute(f'SELECT "{column}" FROM "{table}" WHERE typeof("{column}") = \'text\''):
            if value:
                yield table, column, value


class TextOnly(unittest.TestCase):
    def test_ingestion_reads_no_image_column_of_the_export(self):
        source = Path(build.__file__).read_text(encoding="utf-8")
        read = set(re.findall(r'col\["([^"]+)"\]', source)) | set(build.NUTRIENTS) | set(build.REQUIRED)
        self.assertEqual([c for c in read if IMAGE_WORD.search(c)], [], "an export image column is read")
        self.assertTrue({"code", "product_name", "brands"} <= read, "the pattern above no longer finds the reads")

    def test_the_schema_has_no_image_column(self):
        con = sqlite3.connect(":memory:")
        con.executescript(build.SCHEMA)
        columns = schema(con)
        self.assertTrue(columns, "empty schema")
        self.assertEqual([c for c in columns if IMAGE_WORD.search(c[0]) or IMAGE_WORD.search(c[1])], [])

    def test_a_written_database_carries_no_image_value(self):
        record = {"ref": "off:6281007000012", "name": "Laban", "brands": "Almarai", "quantity": "1 l",
                  "servingText": "", "servingGrams": None, "basis": "per_100ml",
                  "url": "https://world.openfoodfacts.org/product/6281007000012", "lastModified": 1,
                  "codes": ["6281007000012"], "members": [],
                  "values": {"protein": {"amount": 3.0, "qualifier": "measured", "sourceValue": "3",
                                         "sourceField": "proteins_100g", "unit": "g"}}}
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "off.sqlite"
            write_db([record], "0" * 64, target)
            con = sqlite3.connect(target)
            self.assertEqual([c for c in schema(con) if IMAGE_WORD.search(c[1])], [])
            self.assertEqual([v for _, _, v in text_values(con) if IMAGE_VALUE.search(v)], [])

    def test_the_shipped_database_has_no_image_column_or_url(self):
        con = sqlite3.connect(f"file:{SHIPPED}?mode=ro", uri=True)
        self.assertEqual([c for c in schema(con) if IMAGE_WORD.search(c[0]) or IMAGE_WORD.search(c[1])], [])
        found = [(t, c, v[:80]) for t, c, v in text_values(con) if IMAGE_VALUE.search(v)]
        self.assertEqual(found[:5], [], f"{len(found)} image reference(s) in the shipped database")


if __name__ == "__main__":
    unittest.main()
