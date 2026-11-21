#!/bin/zsh
# Capture the three Today prototypes in light and dark on the booted simulator.
# Usage: capture.sh <udid> <app-path>
#
# The order matters: set the appearance *before* launching, give the simulator
# time to commit the appearance change and the app time to finish its first
# frame, then screenshot. A capture taken too early catches the launch screen
# (pure black) and looks like a rendering bug when it is only a race.
set -e
UDID="${1:?udid}"
APP="${2:?app path}"
OUT="${0:a:h}/shots"
BUNDLE=com.almanac.personal
mkdir -p "$OUT"

# Guard against the failure that wasted a whole capture pass: `xcodebuild
# -showBuildSettings` can resolve a *stale* DerivedData product with the same
# bundle id, and every prototype then photographs the production screen. If the
# binary does not carry the gate symbol, stop.
if ! strings "$APP/Almanac.debug.dylib" 2>/dev/null | grep -q AlmanacTodayPrototype; then
  echo "error: $APP is not the prototype build (no AlmanacTodayPrototype symbol)." >&2
  echo "       Build with the same DerivedData root you pass here." >&2
  exit 1
fi

xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --wifiMode active 2>/dev/null || true

for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  sleep 1
  for dir in instrument day-page native-console; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    sleep 0.6
    xcrun simctl launch "$UDID" "$BUNDLE" -AlmanacTodayPrototype "$dir" >/dev/null
    sleep 4.5
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/${dir}-${mode}.png" >/dev/null 2>&1
    echo "captured ${dir}-${mode}.png  md5=$(md5 -q "$OUT/${dir}-${mode}.png")"
  done
done

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

# Distinctness check: three designs must not photograph the same pixels.
DISTINCT=$(md5 -q "$OUT"/*.png | sort -u | wc -l | tr -d ' ')
echo "distinct images: $DISTINCT"

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
