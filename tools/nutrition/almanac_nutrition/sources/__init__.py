"""Source modules. Each defines NAMESPACE, extract(lake) and canonicalise(lake, dictionary).

Discovered by name so that adding a source never edits a shared file.
"""
from __future__ import annotations

import importlib
import pkgutil
from types import ModuleType


def load_sources() -> dict[str, ModuleType]:
    found: dict[str, ModuleType] = {}
    for info in pkgutil.iter_modules(__path__):
        if info.name.startswith("_"):
            continue
        module = importlib.import_module(f"{__name__}.{info.name}")
        found[module.NAMESPACE] = module
    return dict(sorted(found.items()))
