# UI review

Three tools, for three different jobs.

## `capture.sh` — the reproducible matrix

Builds Almanac, installs it on a simulator, and photographs the launch screen in both
appearances and at the largest Dynamic Type size.

    docs/ui/capture.sh            # -> /tmp/almanac-shots
    docs/ui/capture.sh some/dir   # -> somewhere else

It needs only `xcodebuild` and `xcrun` — no Node, no MCP server. That is the point: it is
the one piece of this loop that can run in CI and on a machine with no extras installed.

## `measure.sh` — checking the capture against the tokens

Photographs nothing. It reads a PNG and reports what is objectively there: every text run
with its size in points, every colour covering more than 0.2% of the screen matched
against `AlmanacPalette`, and every structural band classified as a rule or a panel.

    docs/ui/measure.sh /tmp/almanac-shots/today-light.png
    docs/ui/measure.sh --capture            # capture, then measure all three

It exists because "does this screen obey the design system" has an objective answer, and
answering it by eye is unreliable at exactly the sizes that matter — a rule one shade off,
a hard-coded grey, a caption set at body size. It found the real one on the first run: the
app drew rules with three different weights — 0.33pt, 0.67pt and 1.00pt — on one screen, in
both appearances, which is what makes it a design decision rather than a rendering artifact.
All three are now `AlmanacRule`, and the check that reports it ("rules are drawn at … they
should be one weight") passes on all three captures.

The three weights had three unrelated causes, which is why it survived review: SwiftUI's
`Divider()` draws the system's idea of a hairline, a 1pt stroke centred on a card's edge
antialiases across two device-pixel rows, and a filled `Rectangle` is 1pt by construction.
Each was individually defensible; only the screen they shared was not.

It reads both palettes, and `measure.sh` infers the appearance from the filename, because
`capture.sh` already names its shots `today-light` and `today-dark`. Measuring a dark
capture against the light table called 65% of the screen off-token, every value of it a
correct `AlmanacPalette` colour — so the table is selected, not guessed.

One limit worth stating: it **cannot** tell you whether a screen is *good*. Roughly a fifth
of design review is taste and this measures none of it. It is the four fifths that can be
counted, which is still the part that used to need a person.

## XcodeBuildMCP — the interactive review

Configured in `opencode.json` and `.xcodebuildmcp/config.yaml`. This is what lets a
session *navigate*: `tap`, `swipe`, `drag`, `type_text`, and `snapshot_ui`, which returns
the accessibility tree as text.

`capture.sh` can only photograph the launch screen, because `xcrun simctl` has no tap or
swipe primitive. XcodeBuildMCP reaches the Quick Log sheet, Settings, the exercise picker
and every editor. Prefer it for review; keep the script for the matrix and for measuring.

See `.opencode/CONNECTORS.md` for the full tool list and the three limits worth knowing —
in particular that a shadowed element still appears in `snapshot_ui`, so a stale snapshot
will happily let you tap something the user cannot see.

## Reviewing the output

Hand the paths to `/design-critique`, or open them directly. The largest-type capture is
the one most likely to show a real defect: the app clamps Dynamic Type at four sites, and
three of them are on the rhythm calendar and the tab bar.
