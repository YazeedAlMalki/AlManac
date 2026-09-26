# UI review

Two tools, for two different jobs.

## `capture.sh` — the reproducible matrix

Builds Almanac, installs it on a simulator, and photographs the launch screen in both
appearances and at the largest Dynamic Type size.

    docs/ui/capture.sh            # -> /tmp/almanac-shots
    docs/ui/capture.sh some/dir   # -> somewhere else

It needs only `xcodebuild` and `xcrun` — no Node, no MCP server. That is the point: it is
the one piece of this loop that can run in CI and on a machine with no extras installed.

## XcodeBuildMCP — the interactive review

Configured in `opencode.json` and `.xcodebuildmcp/config.yaml`. This is what lets a
session *navigate*: `tap`, `swipe`, `drag`, `type_text`, and `snapshot_ui`, which returns
the accessibility tree as text.

`capture.sh` can only photograph the launch screen, because `xcrun simctl` has no tap or
swipe primitive. XcodeBuildMCP reaches the Quick Log sheet, Settings, the exercise picker
and every editor. Prefer it for review; keep the script for the matrix.

See `.opencode/CONNECTORS.md` for the full tool list and the three limits worth knowing —
in particular that a shadowed element still appears in `snapshot_ui`, so a stale snapshot
will happily let you tap something the user cannot see.

## Reviewing the output

Hand the paths to `/design-critique`, or open them directly. The largest-type capture is
the one most likely to show a real defect: the app clamps Dynamic Type at four sites, and
three of them are on the rhythm calendar and the tab bar.
