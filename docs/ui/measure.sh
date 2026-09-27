#!/bin/bash
# Measure Almanac's UI against its own design tokens.
#
# capture.sh photographs the app; this one *checks* it. The point is that
# "does this screen obey the design system" has an objective answer, and
# answering it by eye is unreliable at exactly the sizes that matter — a
# divider one shade off, a hard-coded grey, a caption set at body size.
#
# What it reports:
#   - every text run with its size in points, calibrated to the screen title
#   - every colour covering more than 0.2% of the screen, matched to a token
#   - every structural band, classified as a rule or a panel edge
#
# It does not need a human, an MCP server, or any judgement, so it can run in
# CI. It also cannot tell you whether a screen is *good* — roughly a fifth of
# design review is taste, and this measures none of it. It is the four fifths
# that can be counted.
#
# Usage:  docs/ui/measure.sh [image.png ...]
#         docs/ui/measure.sh --capture          # capture first, then measure
#
# ALMANAC_SCALE overrides the assumed device scale, e.g. "ALMANAC_SCALE=--scale 2"
# for an iPad capture. It matters: every point size the tool prints is device
# pixels divided by this, so a 2x capture measured at 3x reports every size a
# third too large.
#
# Requires: xcodebuild, xcrun (for --capture only), and a Swift toolchain.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
TOOL="docs/ui/measure.swift"
BIN="$(mktemp -d)/measure"
CAPTURE_DIR=""

if [ "${1:-}" = "--capture" ]; then
  CAPTURE_DIR="$(mktemp -d)/shots"
  echo "==> Capturing to $CAPTURE_DIR"
  docs/ui/capture.sh "$CAPTURE_DIR" >/dev/null
  shift
  set -- "$CAPTURE_DIR"/*.png
fi

if [ $# -eq 0 ]; then
  echo "usage: docs/ui/measure.sh <image.png ...> | docs/ui/measure.sh --capture" >&2
  echo "       run docs/ui/capture.sh first, or pass --capture to do both." >&2
  exit 1
fi

if [ ! -x "$BIN" ]; then
  echo "==> Building the measurement tool"
  # AppKit is needed for NSImage; the simulator SDK is not, and using it would
  # produce a binary that cannot run on this host.
  xcrun swiftc -O -o "$BIN" "$TOOL"
fi

for img in "$@"; do
  if [ ! -f "$img" ]; then
    echo "no such image: $img" >&2
    exit 1
  fi
  # capture.sh names its shots `today-dark`, so infer the appearance from the
  # filename. Guessing wrong reports correct colours as off-token, which is how
  # a checker starts crying wolf and stops being read.
  appearance=light
  case "$(basename "$img")" in
    *dark*) appearance=dark ;;
    *light*) appearance=light ;;
  esac
  # shellcheck disable=SC2086  # ALMANAC_SCALE is a flag pair and must word-split
  "$BIN" "$img" --appearance "$appearance" ${ALMANAC_SCALE:-}
  echo
done
