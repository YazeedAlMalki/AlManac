#!/bin/bash
# Capture Almanac's launch screen in both appearances, and at the largest
# Dynamic Type size, straight from a simulator.
#
# This exists because the design system is the thing being reviewed, and until
# now there was no way to see it without a human driving Xcode by hand. It uses
# only xcrun and xcodebuild, so it runs on a machine with no Node and no extra
# tooling.
#
# LIMITATION, and it is a real one: `xcrun simctl` has no tap, swipe or type
# primitive. It can only photograph what renders at launch. Today that is the
# Today screen and nothing else — the Quick Log sheet, Settings, the exercise
# picker and every editor need a UI test or an automation server to reach. See
# `.opencode/CONNECTORS.md` for what closes that gap.
#
# Usage:  docs/ui/capture.sh [output-directory]
# Default output directory is /tmp/almanac-shots.

set -euo pipefail

OUT="${1:-/tmp/almanac-shots}"
SIM_NAME="${ALMANAC_SIM:-iPhone 16e}"
BUNDLE_ID="com.almanac.personal"
PROJECT="Native/Almanac.xcodeproj"
SCHEME="Almanac"

cd "$(git rev-parse --show-toplevel)"
mkdir -p "$OUT"

if ! command -v xcodebuild >/dev/null; then
  echo "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

# Resolve the simulator. Pick a booted one if there is one, else the named one.
UDID="$(xcrun simctl list devices available -j \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for rt,devs in d.items():
    for x in devs:
        if x['name']=='''$SIM_NAME''' and x.get('isAvailable'):
            print(x['udid']); raise SystemExit
")"

if [ -z "$UDID" ]; then
  echo "No available simulator named '$SIM_NAME'. Set ALMANAC_SIM to another name." >&2
  exit 1
fi

echo "==> Simulator $SIM_NAME ($UDID)"

xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

echo "==> Building"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

# `-showBuildSettings` must be given the same destination as the build, or it
# resolves to a device (iphoneos) path and the app is not where it just went.
DEST="platform=iOS Simulator,name=$SIM_NAME"

APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination "$DEST" -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')"

if [ ! -d "$APP" ]; then
  echo "Could not locate the built app ($APP)." >&2
  exit 1
fi

echo "==> Installing"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

shoot() { # shoot <name>
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
  sleep 4
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null 2>&1
  echo "    $OUT/$1.png"
}

echo "==> Capturing"
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" content_size medium >/dev/null 2>&1 || true
shoot today-light

xcrun simctl ui "$UDID" appearance dark >/dev/null 2>&1 || true
shoot today-dark

xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large >/dev/null 2>&1 || true
shoot today-accessibility-type

# Leave the simulator as it was found.
xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" content_size medium >/dev/null 2>&1 || true

echo
echo "Done. Three captures of the launch screen only — see the limitation at the top."
echo "Open them to review, then hand the paths to /design-critique."
