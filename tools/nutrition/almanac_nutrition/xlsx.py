"""Spreadsheet cells as text, for the extract stage of XLSX sources.

Extraction never types a value: a cell becomes the text a reviewer would
compare against the workbook, and canonicalise parses it through values.qualify.
"""
from __future__ import annotations

import csv
import datetime as dt
import re
from pathlib import Path
from typing import Iterable

import openpyxl

from .canonical_io import CanonicalError
from .lake import sha256_file


def sheet_file(workbook: str, title: str) -> str:
    """The extracted CSV for one sheet: `<workbook stem>__<sheet title, sanitised>.csv`."""
    return f"{Path(workbook).stem}__{re.sub(r'[^A-Za-z0-9.-]+', '_', title).strip('_')}.csv"


def cell_text(value: object, where: str) -> str:
    """One cell, unparsed: text as-is, numbers as their shortest round trip, dates in ISO 8601."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, (dt.datetime, dt.date, dt.time)):
        return value.isoformat()
    raise CanonicalError(f"{where}: cell of type {type(value).__name__} ({value!r}) has no "
                         "verbatim text form; refusing to extract it")


def extract_workbooks(source: Path, workbooks: Iterable[str], scratch: Path) -> list[dict]:
    """Writes every sheet of every workbook to its own CSV in `scratch`, all rows kept."""
    sheets = []
    for workbook in workbooks:
        book = openpyxl.load_workbook(source / workbook, read_only=True, data_only=True)
        try:
            for sheet in book.worksheets:
                name = sheet_file(workbook, sheet.title)
                if (scratch / name).exists():
                    raise CanonicalError(f"{workbook}: sheet {sheet.title!r} and another sheet "
                                         f"both extract to {name}")
                rows = columns = 0
                with open(scratch / name, "w", newline="", encoding="utf-8") as f:
                    writer = csv.writer(f, lineterminator="\n", quoting=csv.QUOTE_ALL)
                    for rows, row in enumerate(sheet.iter_rows(values_only=True), start=1):
                        writer.writerow([cell_text(v, f"{workbook}!{sheet.title} row {rows}")
                                         for v in row])
                        columns = max(columns, len(row))
                sheets.append({"workbook": workbook, "sheet": sheet.title, "file": name,
                               "rows": rows, "columns": columns})
        finally:
            book.close()
    return sheets


def read_sheet(extracted: Path, manifest: dict, workbook: str, title: str) -> tuple[list[list[str]], dict]:
    """An extracted sheet's rows, refused if the file changed after extraction."""
    name = sheet_file(workbook, title)
    path = extracted / name
    recorded = manifest.get("outputs", {}).get(name)
    if not path.is_file() or recorded != sha256_file(path):
        raise CanonicalError(f"{path} is missing or changed after extraction; re-run extract")
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    return rows, {"file": f"processed/extracted/{extracted.name}/{name}", "sha256": recorded}


def cell(row: list[str], column: int) -> str:
    """A cell by position; openpyxl rows stop at their last non-empty cell."""
    return row[column] if column < len(row) else ""
