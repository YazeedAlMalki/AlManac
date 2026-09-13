"""The food-data lake on disk (Processing Design v0.1 §5).

    raw/                         immutable, verified against manifests/
    processed/extracted/{ns}/    the source's own shape
    processed/canonical/{ns}/    Almanac schema, source values preserved
    processed/union/             every canonical source, licence-tagged
    build/almanac.sqlite         what ships

Every stage writes only its own directory, through `staged_directory`, so a
failed run leaves the previous output exactly as it was.
"""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator

DEFAULT_ROOT = Path.home() / "ALManac-food-data"


class InputVerificationError(RuntimeError):
    """An input differs from what the collection manifest recorded."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while block := f.read(1 << 20):
            digest.update(block)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def tool_revision() -> str:
    """The git commit this pipeline ran from, marked dirty if uncommitted."""
    here = Path(__file__).resolve().parent
    try:
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=here, capture_output=True,
                              text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--", "."], cwd=here.parent,
                               capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return head + ("+dirty" if dirty else "")


class Lake:
    def __init__(self, root: Path | str | None = None) -> None:
        chosen = root or os.environ.get("ALMANAC_FOOD_DATA") or DEFAULT_ROOT
        self.root = Path(chosen).expanduser().resolve()

    @property
    def manifests(self) -> Path:
        return self.root / "manifests"

    @property
    def canonical_root(self) -> Path:
        return self.root / "processed" / "canonical"

    def extracted(self, namespace: str) -> Path:
        return self.root / "processed" / "extracted" / namespace

    def canonical(self, namespace: str) -> Path:
        return self.canonical_root / namespace

    @property
    def union(self) -> Path:
        return self.root / "processed" / "union"

    @property
    def bundle(self) -> Path:
        return self.root / "build" / "almanac.sqlite"

    def manifest(self, name: str) -> dict:
        return json.loads((self.manifests / f"{name}.json").read_text(encoding="utf-8"))

    def source_dir(self, manifest_name: str) -> Path:
        return self.root / self.manifest(manifest_name)["local_path"]

    def verify_inputs(self, manifest_name: str, filenames: Iterable[str]) -> list[dict]:
        """Checksums every input against the collection manifest before it is read."""
        manifest = self.manifest(manifest_name)
        recorded = {entry["filename"]: entry for entry in manifest["files"]}
        base = self.root / manifest["local_path"]
        verified = []
        for name in filenames:
            entry = recorded.get(name)
            if entry is None:
                raise InputVerificationError(f"{name} is not recorded in manifests/{manifest_name}.json")
            path = base / name
            if not path.is_file():
                raise InputVerificationError(f"{path} is missing")
            actual = sha256_file(path)
            if actual != entry["sha256"]:
                raise InputVerificationError(
                    f"{path}: sha256 {actual} differs from the manifest's {entry['sha256']}")
            verified.append({"file": str(path.relative_to(self.root)), "sha256": actual})
        return verified


@contextmanager
def staged_directory(final: Path) -> Iterator[Path]:
    """Yields an empty scratch directory that replaces `final` only on success."""
    final = Path(final)
    final.parent.mkdir(parents=True, exist_ok=True)
    scratch = final.with_name(f".{final.name}.partial")
    if scratch.exists():
        shutil.rmtree(scratch)
    scratch.mkdir()
    try:
        yield scratch
    except BaseException:
        shutil.rmtree(scratch, ignore_errors=True)
        raise
    retired = final.with_name(f".{final.name}.retired")
    if retired.exists():
        shutil.rmtree(retired)
    if final.exists():
        final.rename(retired)
    scratch.rename(final)
    shutil.rmtree(retired, ignore_errors=True)


def write_csv(path: Path, header: list[str], rows: Iterable[Iterable[object]], *,
              quote_all: bool = False) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n",
                            quoting=csv.QUOTE_ALL if quote_all else csv.QUOTE_MINIMAL)
        writer.writerow(header)
        writer.writerows(rows)


def read_csv(path: Path) -> list[dict[str, str]]:
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
                    encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))
