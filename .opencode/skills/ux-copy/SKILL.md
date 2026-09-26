---
name: ux-copy
description: Write or review UX copy — microcopy, error messages, empty states, CTAs. Trigger with "write copy for", "what should this button say?", "review this error message", or when naming a CTA, wording a confirmation dialog, filling an empty state, or writing onboarding text.
argument-hint: "<context or copy to review>"
---

# /ux-copy

> If you see unfamiliar placeholders or need to check which tools are connected, see [CONNECTORS.md](../../CONNECTORS.md).

Write or review UX copy for any interface context.

## Usage

```
/ux-copy $ARGUMENTS
```

## What I Need From You

- **Context**: What screen, flow, or feature?
- **User state**: What is the user trying to do? How are they feeling?
- **Tone**: Formal, friendly, playful, reassuring?
- **Constraints**: Character limits, platform guidelines?

## Principles

1. **Clear**: Say exactly what you mean. No jargon, no ambiguity.
2. **Concise**: Use the fewest words that convey the full meaning.
3. **Consistent**: Same terms for the same things everywhere.
4. **Useful**: Every word should help the user accomplish their goal.
5. **Human**: Write like a helpful person, not a robot.

## Copy Patterns

### CTAs
- Start with a verb: "Start free trial", "Save changes", "Download report"
- Be specific: "Create account" not "Submit"
- Match the outcome to the label

### Error Messages
Structure: What happened + Why + How to fix
- "Payment declined. Your card was declined by your bank. Try a different card or contact your bank."

### Empty States
Structure: What this is + Why it's empty + How to start
- "No projects yet. Create your first project to start collaborating with your team."

### Confirmation Dialogs
- Make the action clear: "Delete 3 files?" not "Are you sure?"
- Describe consequences: "This can't be undone"
- Label buttons with the action: "Delete files" / "Keep files" not "OK" / "Cancel"

### Tooltips
- Concise, helpful, never obvious

### Loading States
- Set expectations, reduce anxiety

### Onboarding
- Progressive disclosure, one concept at a time

## Voice and Tone

Adapt tone to context:
- **Success**: Celebratory but not over the top
- **Error**: Empathetic and helpful
- **Warning**: Clear and actionable
- **Neutral**: Informative and concise

## Output

```markdown
## UX Copy: [Context]

### Recommended Copy
**[Element]**: [Copy]

### Alternatives
| Option | Copy | Tone | Best For |
|--------|------|------|----------|
| A | [Copy] | [Tone] | [When to use] |
| B | [Copy] | [Tone] | [When to use] |
| C | [Copy] | [Tone] | [When to use] |

### Rationale
[Why this copy works — user context, clarity, action-orientation]

### Localization Notes
[Anything translators should know — idioms to avoid, character expansion, cultural context]
```

## Where the copy lives

- `Native/Almanac/*.swift` — every user-facing string is a literal in the view, or a
  formatted result beside it. **There is no string catalogue**: 0 `.strings` / `.xcstrings`,
  0 `NSLocalizedString`, `knownRegions = (en, Base)`. So copy is edited in place, and a
  string used in two places is two literals that can drift.
- `AlmanacApp.swift`'s `editorError(_:)` is the one error surface. Its `errorTitle(_:)`
  derives a title from the store's own first sentence, so **a store's error wording is
  user-facing copy** — changing it changes the alert title.
- `AlmanacReadinessPresentation` holds the confidence labels; `readable(_:)` and
  `dateLabel(_:)` are the shared formatters.
- XcodeBuildMCP's `snapshot_ui` gives you the strings as VoiceOver will announce them,
  which is the fastest way to hear a whole screen's copy at once. See
  `.opencode/CONNECTORS.md`.

## Notes for this app

- The voice is plain, specific and instrument-like. It states the reading and its limits:
  "Waiting on signals", "More signals are needed", "Still needed: sleep, sleep quality,
  resting heart rate, HRV." It does not reassure, congratulate, or use a mascot.
- It never invents precision. If a value is unknown the copy says so rather than rounding
  to something plausible.
- Prefer naming the specific failure over a generic one. "Could not complete the action"
  for every error is the failure mode `editorError` exists to prevent.
- Watch for hand-rolled English pluralisation inside interpolated strings — several exist
  and they will not survive a second language.

## Tips

1. **Be specific about context** — "Error message when payment fails" is better than "error message."
2. **Share your brand voice** — "We're professional but warm" helps me match your tone.
3. **Consider the user's emotional state** — Error messages need empathy. Success messages can celebrate.
