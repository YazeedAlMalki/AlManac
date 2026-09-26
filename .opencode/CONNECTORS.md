# Connectors

## What is actually connected to this project

**XcodeBuildMCP is connected and live.** Configured in `opencode.json` (project-scoped),
pinned to `xcodebuildmcp@2.7.0`, with defaults in `.xcodebuildmcp/config.yaml`:

```jsonc
{ "mcp": { "servers": { "XcodeBuildMCP": {
  "type": "local", "command": ["npx", "-y", "xcodebuildmcp@2.7.0", "mcp"] } } } }
```

It exposes 36 tools. `enabledWorkflows` is `simulator` + `ui-automation`, and that second
entry is what makes `snapshot_ui`, `tap`, `swipe`, `drag`, `type_text` and `wait_for_ui`
available — `simulator` alone does not include them. **If a `ui-automation` tool is
missing, check `enabledWorkflows` before anything else.**

Node is installed at `~/.local/node`, symlinked into `~/.local/bin`, which is already on
`PATH` via `~/.zprofile`. Nothing was installed system-wide and no sudo was used. If `npx`
is not found in a fresh shell, that symlink chain is what broke.

Verified end to end: `session_show_defaults` → `build_run_sim` → `snapshot_ui` → `tap` →
`screenshot`, against the `Almanac` scheme on iPhone 16e.

**There is no Figma file, and there is not going to be one.** Almanac's design system is
`Native/Almanac/DesignSystem.swift`, and the rules governing a change live in the
`almanac-design-system` skill. A Figma library would be a second source of truth that
drifts from the code on day one, and the free Figma MCP tier allows about six calls a
month. The skills here read the Swift.

## What each capability is good for

| Need | Tool |
|---|---|
| Ground truth for a screen's structure | `snapshot_ui` — 100+ elements with roles, labels and identifiers, as **text**, so it is readable without image input |
| Reaching a screen | `tap` / `swipe` / `drag` by `elementRef`, or by label and identifier |
| Seeing the pixels | `screenshot` |
| Build, run, test | `build_run_sim`, `test_sim` |
| Device conditions | `set_sim_appearance` (light/dark), content size, increase contrast |
| When something breaks | `start_sim_log_cap`, `stop_sim_log_cap`, the LLDB tools |

`docs/ui/capture.sh` still earns its place: it needs only `xcodebuild` and `xcrun`, so it
works with no MCP server at all, and it is the one thing here that can run in CI. Prefer
XcodeBuildMCP for review; keep the script for the reproducible light/dark/type-size matrix.

## Known limits

- **A shadowed element is still not reachable.** `snapshot_ui` reported a
  `Close` button while the Quick Log sheet covered it, because the Today screen beneath
  was still in the hierarchy. Call `wait_for_ui("settled")` before trusting `elementRef`s,
  and re-snapshot after every state change — refs are regenerated and go stale.
- **A root screen's whole subtree can be one element.** Today reports as a single
  `Saturday 26 September, Today, Good morning, Yazeed` text element, because
  `ReadinessDashboardView` combines its subtree for VoiceOver. The children are still
  listed individually under `capture.text`; only `capture.targets` is flat. Do not read a
  low target count as "this screen is not interactive".
- **VoiceOver is not being driven.** `snapshot_ui` reads the same accessibility tree
  VoiceOver consumes, but it does not simulate the cursor. Reading order and verbosity
  still need a human, or a real VoiceOver pass.

## Categories this repo deliberately does not use

| Category | Why not |
|---|---|
| Design tool (Figma, Sketch) | The design system is code. See above. |
| Chat (Slack, Teams) | Single-user private app. |
| Knowledge base (Notion, Confluence) | Documentation lives in `docs/`, in the repo. |
| Project tracker (Linear, Jira) | No tracker configured; work is tracked in `docs/implementation-status.md`. |
| User feedback (Intercom, Canny) | One user. There is no feedback stream to read. |
| Product analytics (Amplitude, Mixpanel) | Same. Also a privacy question for a health logbook. |
