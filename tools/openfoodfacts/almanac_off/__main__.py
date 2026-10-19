import argparse
import os
from pathlib import Path

from . import build

parser = argparse.ArgumentParser(prog="almanac_off")
parser.add_argument("command", choices=["fetch", "build"])
parser.add_argument("--lake", type=Path, default=Path(os.environ.get(
    "ALMANAC_FOOD_DATA", Path.home() / "ALManac-food-data")))
args = parser.parse_args()
if args.command == "fetch":
    build.fetch(args.lake)
else:
    for k, v in build.build(args.lake).items():
        print(f"{k}: {v}")
