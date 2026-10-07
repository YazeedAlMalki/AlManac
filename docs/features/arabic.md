# Almanac — Arabic

**Status (2026-10-07):** the whole app has Arabic, switched by iOS's own
per-app Language setting. Slices 0–3 of #4 are built on
`claude/arabic-2026-10-07`. Slice 4 (formatting and right-to-left review) and
the owner's read-through are open. The owner's call, 2026-10-07: "the whole
app gets Arabic". That brings BRD v1.6's deferred "Arabic UI" into scope.

## How text reaches the screen

There are two paths, and each has a gate that fails CI when a string has no
Arabic.

| Where the English is written | How it is translated | What fails CI when Arabic is missing |
|---|---|---|
| A SwiftUI literal (`Text("…")`, `Button("…")`, `Section("…")`), or `String(localized: "…")` in the app or the widget | `Native/Almanac/Localizable.xcstrings`, and `Native/AlmanacWidgets/Localizable.xcstrings` for the widget, whose extension reads its own bundle | The app build runs with `SWIFT_EMIT_LOC_STRINGS=YES`, so the compiler lists every key exactly as SwiftUI will look it up, interpolations included (`%lld`, `%@`, `%lf` by the value's real type). `tools/localization/check_catalog.py --strict` fails on any key without Arabic, naming its file and line. |
| AlmanacCore (`localized("…")`, `localized("… %@ …", value)`) | `Sources/AlmanacCore/Localization/Resources/ar.lproj/Localizable.strings`, a SwiftPM resource (`defaultLocalization: "en"`) | `LocalizationTableTests` (Linux) scans the module's source for every `localized("…")` key and fails on any without Arabic. |

Both gates also fail on an Arabic value whose format specifiers differ from
its key's. A `%lld` turned into `%@` is a crash on an Arabic phone, and a
dropped one is a wrong sentence.

The English text is the key in both tables, so English is never in a table,
and a string with no Arabic shows in English rather than as a key. The tests
run in the development language, so every test that asserts an English
sentence still does, unchanged.

`localized(_:_:)` substitutes its string arguments itself, both `%@` in order
and `%1$@` by position for a translation that needs another order. The reason
is that `String(format:)` cannot take a Swift `String` on Linux, where the core
is tested. Numbers are formatted by the caller. `localizedList` joins "A, B
and C" with translatable connectors, so in Arabic the same list reads
"أ، ب وج".

## What stays English, and why

**Stored text never changes with the language.** A database written in
Arabic must read the same in English, and the reverse (#4, decision 2). So:

- **Readiness.** The engine writes its description and recommendation in
  English, and `readiness_record` stores them. `ReadinessText.display`
  translates them where they are shown: today's on the dashboard, stored
  ones on the trend. It knows the shapes the engine composes, and
  `ReadinessTextTests` checks every one comes back unchanged in English.
- **Catalog drinks.** A catalog drink's English name is written into
  `drink_entry`, so `Drink.displayName` translates it only at display. A
  drink the person named is shown exactly as typed. Brand names (Pepsi, Red
  Bull) have no Arabic entry and stay as they are.
- **Day keys** are pinned to `en_US_POSIX` (PR #2, merged into this branch
  first).
- Default names written to the database ("My Schedule", "User"), grouping
  keys a view compares ("Unassigned"), and lab audit reasons stay English.

**Data has no Arabic source.** Food names (USDA, CIQUAL, CoFID, AFCD),
exercise and muscle names, and lab analyte names are shown as stored.
Attribution notices are licence wording and stay verbatim.

## The toggle

There is no language setting in Almanac. iOS shows Settings › Almanac ›
Language once the app ships two localisations (`knownRegions` has `ar`).
**Settings › Language** in Almanac opens that page, and shows the language
the app is running in. iOS relaunches the app on a change.

## Plurals

Six call sites used to build English plurals by hand (`tag\(n == 1 ? "" :
"s")`), which in Arabic would have left a stray English "s". They are now
plain counted keys ("%lld tags") with plural variations in the catalog:
English one/other, and Arabic zero/one/two/few/many/other where the noun
agrees with the number. "This is pass %lld through %lld exercises."
pluralises on its second count through a substitution. Other counts use
phrasings that do not need agreement ("الأطعمة المحتسبة: %@").

## Tests

- `ArabicUITests.testTheAppRunsInArabicRightToLeft` launches in Arabic. It
  checks that the tab bar reads اليوم / الاتجاهات / الأقسام (AlmanacCore's
  path), that the bar runs right to left, and that the Modules screen's title
  is Arabic (the app catalog's path). Every other UI suite pins
  `-AppleLanguages (en)`.
- `LocalizationTableTests`: the table parses, has no empty value, and covers
  every source key with the same specifiers. It also checks argument
  substitution.
- `ReadinessTextTests`: every engine sentence comes back unchanged.

## Open

- **Slice 4: formatting and RTL review.** This covers dates (an `ar_SA`
  device may default to the Umm al-Qura calendar, and `ContextTagsView`
  formats with the device calendar), digits (they follow the locale), units
  inside sentences, charts' direction, and a screenshot pass of every
  screen. A few strings are still built in English outside the gates:
  lowercase-first fragments ("last %lld days" as a header detail),
  `.map { "…" }` closures, and the import summary's joined parts.
- **The owner's read-through.** All translations are Modern Standard Arabic
  written in the build, with one glossary throughout (سجّل for log, قراءة for
  reading, مخزن المطبخ for pantry, المقرَّر for prescription). They count as done
  only once the owner has read them.
