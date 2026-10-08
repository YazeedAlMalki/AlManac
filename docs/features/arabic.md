# Almanac — Arabic

**Status (2026-10-08):** the whole app has Arabic, switched by iOS's own
per-app Language setting. Slices 0–4 of #4 are on master (PR #9), after the
owner's read-through. The first screenshot pass ran on an empty database and
its findings are fixed (below). The owner's call, 2026-10-07: "the whole app
gets Arabic". That brings BRD v1.6's deferred "Arabic UI" into scope.

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
  keys a view compares ("Unassigned"), and audit reasons (lab corrections,
  "Set on the Fasting screen") stay English. So do stored vocabularies: prayer
  keys (`fajr`), calculation methods (`umm_al_qura`) and fast-schedule types,
  whose labels are translated where they are shown.

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

## Dates and numbers (slice 4)

**Dates are Gregorian on screen, whatever the device's calendar** (#4,
decision 3). An Arabic phone set to Saudi Arabia defaults to Umm al-Qura, and
everything Almanac stores is Gregorian, so a date in the device's calendar
would name a different month from the one its data is filed under. Every
formatting call that includes a date goes through `almanacFormatted(date:time:)`
or `.almanacDateTime` (`DesignSystem.swift`), which use
`Calendar.almanacDisplay`: Gregorian, in the app's locale, so month names and
digits are still Arabic. The root view sets `\.calendar` for date pickers and
chart axes. Time-only formatting does not depend on the calendar and is left
alone. The fasting screens' Hijri dates are deliberate and come from
`HijriDate`.

**Digits follow the locale.** SwiftUI's own interpolations already write
Arabic-Indic digits. Text built with `String(_:)` or `String(format:)` goes
through `NumberDisplay.localized` (AlmanacCore). It swaps the digits and the
decimal point for the locale's, only when those digits are not ASCII, and
changes nothing else. `AlmanacNumber.compact` and the core's numbers in
sentences use it.

**Typed numbers are read in either language's digits.** The number pad types
٧٢٫٥ in Arabic, which `Double(_:)` refuses. Every numeric field parses through
`Double(userInput:)` / `Int(userInput:)` (`NumberInput`). They read
Arabic-Indic and Persian digits, the Arabic decimal separator and direction
marks, so whatever `NumberDisplay` writes reads back. The date of birth is
stored in ASCII digits whichever keyboard typed it.

**Direction.** Chevrons are `chevron.forward`, which mirrors. Insights' trend
arrows (`arrow.up.right`) are left as they are until a screenshot with data
shows which way the charts' time axis runs in Arabic.

## Tests

- `ArabicUITests.testTheAppRunsInArabicRightToLeft` launches in Arabic. It
  checks that the tab bar reads اليوم / الاتجاهات / الأقسام (AlmanacCore's
  path), that the bar runs right to left, and that the Modules screen's title
  is Arabic (the app catalog's path). Every other UI suite pins
  `-AppleLanguages (en)`.
- `ArabicUITests.testScreenshotEveryScreenInArabic` is the screenshot pass.
  It opens Today, the quick-log sheet, Trends, Insights, the Modules menu and
  every module in Arabic, scrolls each, and writes nothing. Each page's
  screenshot is kept. CI uploads them as plain PNGs in the `arabic-screenshots`
  artifact. Each page's Latin-script text, any element outside the window and
  any system alert are printed as `ARABIC-PASS` lines, which the "Arabic pass
  report" step gathers at the end of the log. Both are reports, not
  assertions, since some Latin text is meant to stay (below).
- `LocalizationTableTests`: the table parses, has no empty value, and covers
  every source key with the same specifiers. It also checks argument
  substitution.
- `ReadinessTextTests`: every engine sentence comes back unchanged.
- `NumberInputTests`: Arabic-Indic and Persian digits, the separators and
  direction marks parse; letters do not; an English run displays numbers
  unchanged, and whatever is displayed reads back.

## Open

- **A screenshot pass with data.** The first pass (run 37821810861,
  2026-10-08) ran first in the suite, on a virgin simulator, so it saw empty
  states. It found nothing off screen and no system alert. The English it
  found was in `String`s the app built and showed verbatim: Today's greeting
  and its "Still needed: …" line, the readiness duration labels, the Trends
  and Insights range pickers ("30 days"), and Vitals' history footer. All of
  these now have Arabic. The rest of the Latin text it reported is meant to
  stay: Almanac, HRV, HealthKit, CSV, the stored default name "User" and the
  fixture laboratory's name. Screens with entries in them (charts, logged
  sessions, meals) and the trend arrows' direction still need a run on a
  populated simulator.

The owner's read-through of the translations is done (2026-10-08). They are
Modern Standard Arabic with one glossary throughout (سجّل for log, قراءة for
reading, مخزن المطبخ for pantry, المقرَّر for prescription).
