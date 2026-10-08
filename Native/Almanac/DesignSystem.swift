import SwiftUI
import UIKit
import CoreText
import AlmanacCore

/// Shared visual tokens for the Almanac design system.
///
/// Almanac is a private physiological logbook: one person records sleep, water,
/// food, training, prayer and fasting against days that begin at 04:00, then
/// reads one readiness number back. The palette is instrument-like rather than
/// decorative — neutral paper, hairline rules, and an ink-blue accent that marks
/// something the app *measured* rather than something it wants to look like.
/// Status colors are the only colors allowed to carry judgement.
enum AlmanacPalette {
    /// The page. A true neutral, not a warm tint: a warm cream reads as a
    /// template, and it forced three more near-whites to stay legible.
    static let canvas = dynamic(light: 0xFCFCFA, dark: 0x0B0B0C)
    /// A single step off the page, for a panel or the bar. A second step is
    /// deliberately absent — reaching for a third surface means the hierarchy,
    /// not the color, is wrong.
    static let surface = dynamic(light: 0xF1F1ED, dark: 0x15161A)
    static let surfaceMuted = dynamic(light: 0xE6E6E1, dark: 0x1E2024)
    /// Rules are the structural device. Containers are not.
    ///
    /// The weight is not part of this token but of `AlmanacRule`, which is the
    /// only thing that draws one. This colour was previously applied three
    /// ways at three weights on a single screen: `Divider().overlay(...)`,
    /// which draws the system's idea of a hairline rather than a value in this
    /// file; `Rectangle().fill(...).frame(height: 1)`; and the 1pt stroke on
    /// `AlmanacCard`, which antialiases across two device-pixel rows and so
    /// measured 0.67pt beside a 1pt rule. All three are `AlmanacRule` now.
    static let divider = dynamic(light: 0xDCDCD6, dark: 0x2A2C30)
    static let textPrimary = dynamic(light: 0x1A1A18, dark: 0xECECEA)
    static let textSecondary = dynamic(light: 0x63635E, dark: 0x9A9C9F)
    /// Graphite, not a product blue. It is the colour of a pen in a chart
    /// margin, and it appears only where Almanac recorded something.
    static let accent = dynamic(light: 0x1F4E8C, dark: 0x6FA0D8)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0B0B0C)
    static let good = dynamic(light: 0x1E7A4C, dark: 0x63D394)
    static let warning = dynamic(light: 0x8A5A00, dark: 0xF2B84B)
    static let critical = dynamic(light: 0xB3261E, dark: 0xFF7A70)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum AlmanacFontRegistration {
    static func registerBundledFonts() {
        let resources = [
            "Fraunces-Variable",
            "Almarai-Regular",
            "Almarai-Bold"
        ]
        for resource in resources {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func hasDisplayFont() -> Bool {
        ["Fraunces-Regular", "Fraunces", "Fraunces-SemiBold"].contains {
            UIFont(name: $0, size: 12) != nil
        }
    }
}

enum AlmanacTypography {
    enum Role {
        case display
        case screenTitle
        case sectionTitle
        case body
        case bodyMedium
        case label
        case caption
        case data
        case dayNumber

        var textStyle: Font.TextStyle {
            switch self {
            case .display: return .largeTitle
            case .screenTitle: return .title
            case .sectionTitle: return .title2
            case .body, .bodyMedium, .data: return .body
            case .label, .caption, .dayNumber: return .caption
            }
        }

        var size: CGFloat {
            switch self {
            case .display: return 64
            case .screenTitle: return 34
            case .sectionTitle: return 22
            case .body, .bodyMedium, .data: return 17
            case .label: return 13
            case .caption, .dayNumber: return 12
            }
        }

        var weight: Font.Weight {
            switch self {
            case .bodyMedium, .label, .data, .sectionTitle: return .medium
            default: return .regular
            }
        }

        var usesMediumFamily: Bool {
            switch self {
            case .bodyMedium, .label, .data, .sectionTitle: return true
            default: return false
            }
        }
    }

    private static let frauncesRegular = ["Fraunces-Regular", "Fraunces"]
    private static let neueRegular = ["PPNeueMontreal-Regular", "NeueMontreal-Regular", "Neue Montreal"]
    private static let neueMedium = ["PPNeueMontreal-Medium", "NeueMontreal-Medium", "Neue Montreal"]
    private static let almaraiRegular = ["Almarai-Regular", "Almarai"]
    private static let almaraiBold = ["Almarai-Bold", "Almarai"]

    /// Fraunces is a display face: the screen title and the readiness number,
    /// and nothing else. At 22pt and below its high-contrast strokes are the
    /// thinnest part of the cut, so headings inside content are set in the sans
    /// at medium weight instead.
    static func font(_ role: Role, locale: Locale = .current) -> Font {
        let candidates: [String]
        if locale.language.languageCode?.identifier == "ar" {
            candidates = role.usesMediumFamily ? almaraiBold : almaraiRegular
        } else {
            switch role {
            case .display, .screenTitle:
                candidates = frauncesRegular
            case .sectionTitle, .body, .bodyMedium, .label, .data:
                candidates = role.usesMediumFamily ? neueMedium : neueRegular
            case .caption, .dayNumber:
                candidates = neueRegular
            }
        }

        if let name = candidates.first(where: { UIFont(name: $0, size: role.size) != nil }) {
            return .custom(name, size: role.size, relativeTo: role.textStyle)
        }

        // Neue Montreal is commercially licensed and intentionally is not
        // redistributed here. The system fallback keeps the app readable until
        // licensed font files are supplied; the approved family is picked up
        // automatically once registered.
        return .system(role.textStyle, design: .default, weight: role.weight)
    }
}

enum AlmanacReadinessPresentation {
    static func confidenceLabel(_ confidence: ReadinessConfidence) -> String {
        switch confidence {
        case .high: return String(localized: "High confidence")
        case .medium: return String(localized: "Medium confidence")
        case .low: return String(localized: "Low confidence")
        case .veryLow: return String(localized: "Very low confidence")
        case .insufficient: return String(localized: "Insufficient data")
        }
    }

    static func confidenceTone(_ confidence: ReadinessConfidence) -> AlmanacStatusTone {
        switch confidence {
        case .high, .medium: return .good
        case .low, .veryLow: return .warning
        case .insufficient: return .neutral
        }
    }

    static func tone(for grade: ReadinessColor) -> AlmanacStatusTone {
        switch grade {
        case .green: return .good
        case .yellow: return .warning
        case .red: return .critical
        case .none: return .neutral
        }
    }
}

enum AlmanacNumber {
    /// A whole number as itself, anything else to one decimal, in the app's
    /// digits (`NumberDisplay`). An editor prefilled with this reads it back
    /// through `Double(userInput:)`, which takes either language's digits.
    static func compact(_ value: Double) -> String {
        NumberDisplay.localized(value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value))
    }
}

extension Calendar {
    /// The calendar every date on screen is shown in: Gregorian, whatever the
    /// device's own (#4, decision 3). An Arabic phone set to Saudi Arabia
    /// defaults to Umm al-Qura, and every date Almanac stores is Gregorian, so
    /// a screen in the device's calendar would name a different month from the
    /// one the data is filed under. Month and weekday names, and digits, still
    /// follow the language. Hijri dates the fasting work shows on purpose come
    /// from `HijriDate`, not from this.
    static var almanacDisplay: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}

extension Date {
    /// `formatted(date:time:)`, in `Calendar.almanacDisplay`.
    func almanacFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, calendar: .almanacDisplay))
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// `.dateTime`, in `Calendar.almanacDisplay`.
    static var almanacDateTime: Date.FormatStyle { Date.FormatStyle(calendar: .almanacDisplay) }
}

enum AlmanacMetrics {
    static let screenInset: CGFloat = 20
    static let cardPadding: CGFloat = 24
    static let sectionGap: CGFloat = 32
    /// Rules now do the separating, so the radius no longer has to be soft to
    /// make a panel read as a panel.
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let minimumControl: CGFloat = 50
    /// The weight of a rule. One value, because rules are the structural
    /// device and a screen showing them at two weights has no hierarchy —
    /// `docs/ui/measure.sh` reported 0.33pt, 0.67pt and 1.00pt on Today.
    ///
    /// It is 1pt rather than a true device-pixel hairline (1/3pt) because
    /// 1/3pt is not a portable value: it is one device pixel at 3x but half of
    /// one at 2x, so the app's structural device would change weight with the
    /// display it happened to ship on.
    static let ruleWeight: CGFloat = 1
}

enum AlmanacAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Temporary icon vocabulary. The approved custom icon sheet is a separate
/// deliverable; centralizing SF Symbols keeps that replacement isolated.
// `AlmanacIcon` moved to `Sources/AlmanacCore/Design/AlmanacIcon.swift`. The
// router in `AppRoute` names its own icons, and a route that could not label
// itself would make every caller repeat the mapping — so the vocabulary has to
// be reachable from the core module. It is still one list, not two.

enum AlmanacStatusTone {
    case neutral
    case good
    case warning
    case critical

    var color: Color {
        switch self {
        case .neutral: return AlmanacPalette.textSecondary
        case .good: return AlmanacPalette.good
        case .warning: return AlmanacPalette.warning
        case .critical: return AlmanacPalette.critical
        }
    }

    var symbol: String {
        switch self {
        case .neutral: return "minus.circle"
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

/// Which way a rule runs. Almanac is overwhelmingly horizontal — rules separate
/// rows of a daybook. A vertical rule exists for the one place a row of cells
/// is split side by side.
enum AlmanacRuleAxis {
    case horizontal
    case vertical
}

/// A rule: the app's structural device, and the only thing that draws one.
///
/// Rules are a filled `Rectangle` at `AlmanacMetrics.ruleWeight`, never
/// SwiftUI's `Divider()`. `Divider()` looks like the obvious choice and is the
/// wrong one: its weight is the system's idea of a hairline rather than a value
/// in this file, so the app's primary structural device weighed whatever the OS
/// decided and could change between releases. That is what put 0.33pt rules
/// beside a 1pt one on the same screen.
///
/// It takes an `inset` rather than expecting a surrounding `padding` so that the
/// indent is part of the rule's definition: a rule inside a metric list is
/// supposed to start at the text column, and a caller reaching for `.padding`
/// would have to know that 62 is what that column costs.
struct AlmanacRule: View {
    /// Lines a rule up with an `AlmanacMetricRow`'s text column: the row's
    /// 20pt inset, its 28pt icon well, and the 14pt gap after it.
    static let metricTextInset: CGFloat = 62

    var axis: AlmanacRuleAxis = .horizontal
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(AlmanacPalette.divider)
            .frame(
                width: axis == .vertical ? AlmanacMetrics.ruleWeight : nil,
                height: axis == .horizontal ? AlmanacMetrics.ruleWeight : nil
            )
            .padding(axis == .vertical ? .vertical : .horizontal, inset)
    }
}

/// A panel. Most panels are ruled areas of the page rather than boxes stacked on
/// top of it: a daybook separates its entries with a rule, and a screen where
/// every block is an identical filled card has no hierarchy at all. The one
/// object a screen is about passes `prominent: true` and gets the filled
/// surface, so the emphasis lands in a single place.
struct AlmanacCard<Content: View>: View {
    private let padding: CGFloat
    private let prominent: Bool
    private let content: Content

    init(
        padding: CGFloat = AlmanacMetrics.cardPadding,
        prominent: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.prominent = prominent
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(prominent ? AlmanacPalette.surface : AlmanacPalette.canvas)
            .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous))
            .overlay {
                // A card is delineated by a rule, not a fill — doctrine rule 1.
                // The stroke is inset by half its width so the whole rule lands
                // inside the shape: centred on the edge it would straddle it,
                // antialias across two device-pixel rows, and measure 0.67pt
                // next to an `AlmanacRule`'s 1pt.
                RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
                    .inset(by: AlmanacMetrics.ruleWeight / 2)
                    .stroke(AlmanacPalette.divider, lineWidth: AlmanacMetrics.ruleWeight)
            }
    }
}

/// Something went wrong, said in words, in the place it happened.
///
/// This exists because the same note was being written six times inline, and
/// every one of the six picked its colour by hand — four `.red`, one `.orange`,
/// one `.green` — rather than taking it from `AlmanacPalette`. So the one
/// colour allowed to carry judgement was being chosen by eye, six times, and
/// had drifted to SwiftUI's defaults rather than Almanac's. It is a component
/// rather than a snippet because the *wording* matters more than the paint, and
/// the wording is the part that was being wrong.
///
/// A note is not an empty state. "Nothing logged yet today." and "couldn't
/// read your log" are different claims, and a screen that shows the first when
/// the second is true is lying by omission — the same failure as substituting a
/// zero for a missing reading, which the design doctrine's rule 10 ("never
/// replace a missing reading with zero", in
/// `.opencode/skills/almanac-design-system/SKILL.md`) forbids for values. So this
/// never substitutes for an empty state; it sits beside one.
struct AlmanacProblemNote: View {
    let text: String
    /// What the user can do. Omitted when there is nothing useful to offer,
    /// which is better than offering "try again" where retrying cannot help.
    var action: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.screenInset / 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.critical)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.critical)
                if let action {
                    Text(action)
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.ignore` plus an explicit label, not `.combine`. When the only
        // labelled child is the note's own `Text` — which is the case whenever
        // `action` is nil — `.combine` leaves the container carrying the same
        // label as the child it swallowed, and the note then exists *twice* in
        // the accessibility tree. VoiceOver reads it twice, and any lookup by
        // that label raises "Multiple matching elements found" rather than
        // answering. Ignoring the children and setting the label here makes it
        // exactly one element, and lets the action be appended in the same pass.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text, action].compactMap { $0 }.joined(separator: ". "))
    }
}

/// A section heading. Sentence case, no tracking, no uppercase: a daybook
/// separates its entries with a plain name, and a tracked-out all-caps eyebrow
/// above every heading is the oldest template tell there is. `detail` carries
/// real information only — a range, a count, a time window — never decoration.
struct AlmanacSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(AlmanacTypography.font(.sectionTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Spacer(minLength: 16)
            if let detail {
                Text(detail)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
    }
}

/// The caption above a reading, e.g. the date on Today or the state of the
/// readiness score. Sentence case and no tracking — a tracked-out all-caps
/// eyebrow above every heading is the oldest template tell there is. It stays
/// ink-coloured by default: the accent means Almanac recorded something, so
/// tinting a label with it would spend the one color that carries meaning.
struct AlmanacEyebrow: View {
    let text: String
    var color: Color = AlmanacPalette.textSecondary

    var body: some View {
        Text(text)
            .font(AlmanacTypography.font(.label))
            .foregroundStyle(color)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

struct AlmanacMetricRow: View {
    let icon: String
    let title: String
    let value: String
    var detail: String?
    var tone: AlmanacStatusTone?
    /// What tapping the row does, or `nil` when the row is a reading rather
    /// than a door.
    ///
    /// The action lives on the row itself rather than in a `.onTapGesture` on
    /// whatever contains it, for three reasons that all show up as bugs
    /// otherwise. It gets the button trait and the "double-tap to activate"
    /// hint for free, so VoiceOver does not read a non-interactive row as an
    /// image and a string. It gets the pressed feedback, which a tap gesture
    /// does not. And it keeps the hit target on the row instead of on the
    /// container's padding, so a row inside a card with a footer is not tappable
    /// through the footer.
    var action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(AlmanacMetricRowStyle())
                // A hint is the one thing the label cannot carry, so it is the
                // one thing set here.
                //
                // The label is deliberately *not* set. Measured on a simulator,
                // a tappable row announces as "Hydration, of 2000 mL, 0 mL" —
                // title, detail, value, in reading order, which is what was
                // wanted. Forcing it with `accessibilityElement(children:`
                // `.ignore)` plus an explicit label was tried first and changed
                // nothing: SwiftUI computes a button's label from its own
                // content and does not let the caller restate it that way. The
                // natural label is already right, so the code that pretended to
                // control it is gone rather than left in as a no-op that looks
                // load-bearing.
                .accessibilityHint(Text("Opens \(title)"))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        iconView
                        Text(title)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Spacer(minLength: 0)
                    }
                    Text(value)
                        .font(AlmanacTypography.font(.data).monospacedDigit())
                        .foregroundStyle(valueColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    iconView

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                    }

                    Spacer(minLength: 12)

                    Text(value)
                        .font(AlmanacTypography.font(.data).monospacedDigit())
                        .foregroundStyle(valueColor)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
    }

    private var iconView: some View {        Image(systemName: icon)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tone?.color ?? AlmanacPalette.accent)
            .frame(width: 28, height: 28)
            .background(AlmanacPalette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var valueColor: Color {
        tone == nil ? AlmanacPalette.textPrimary : tone!.color
    }
}

/// A bar showing how far a reading has travelled towards a target.
///
/// ## The fill is a value, and nothing here animates it
///
/// A meter's obvious implementation is a `withAnimation` on the fraction, or a
/// `ProgressView` tinted and trusted. Both animate. On a card grid of five that
/// is five independent animations starting whenever the view re-renders — which
/// on a body-composition screen is whenever a reading is saved, the unit basis
/// changes, or a target lands. The screen is then doing work the user did not
/// ask for, on a surface they are trying to read a number off.
///
/// So the width is a `GeometryReader` read and a `frame`, and the fraction is
/// whatever `BodyCompositionProgress` computed. There is no `animation`
/// modifier, no `ProgressView`, and no state to drive one. The bar changes when
/// the value changes, which is the same as saying it does not change when
/// nothing has.
///
/// ## `nil` draws nothing, and says so
///
/// `fraction` is `nil` for five different reasons — no target, no reading, fewer
/// than two readings, no span to measure from, target already met — and
/// collapsing them into "draw an empty bar" would leave a card showing a
/// half-filled track that reads as "0% of the way there" for someone who is
/// actually at their goal. A full bar and an empty bar are both claims. So a
/// `nil` fraction renders no track at all, and the card's own status line is what
/// says why.
struct AlmanacMeter: View {
    /// 0…1, or `nil` for "there is no progress to show".
    let fraction: Double?
    var tone: AlmanacStatusTone = .neutral
    /// The thickness of the filled part. 8pt reads as a bar rather than a hairline
    /// at arm's length without becoming a chart.
    private let thickness: CGFloat = 8

    var body: some View {
        if let fraction {
            GeometryReader { geometry in
                // Clamped here as well as in core. The core value is already
                // clamped, and this is not a second rule — it is what stops a
                // future caller of this view from drawing a track that overflows
                // its card.
                let width = geometry.size.width * min(max(fraction, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(AlmanacPalette.surfaceMuted)
                    Capsule().fill(tone.color).frame(width: width)
                }
            }
            .frame(height: thickness)
            .accessibilityHidden(true)
        }
    }
}

struct AlmanacStatusMark: View {
    let text: String
    let tone: AlmanacStatusTone

    var body: some View {
        // A wrapped continuation line aligns with the word, not the icon: the
        // title is laid out after the symbol, so at accessibility type sizes
        // "Insufficient data" puts "data" under "Insufficient" rather than
        // under the left edge of the mark. That is the correct reading of the
        // row, so do not "fix" it by centring.
        Label(text, systemImage: tone.symbol)
            .font(AlmanacTypography.font(.label))
            .foregroundStyle(tone.color)
            .labelStyle(.titleAndIcon)
    }
}

/// The pressed state for a tappable metric row.
///
/// A row inside a card that grows a full-width accent fill on press reads as a
/// button, which is what it now is — but the fill is a *tint* of the surface,
/// not the accent. Solid accent on press would put the accent behind a row of
/// text and spend the one color that means "Almanac recorded something" on
/// "you are touching this".
struct AlmanacMetricRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AlmanacPalette.surfaceMuted : Color.clear)
            .contentShape(Rectangle())
            // 0.12s, and no scale. A row is already 64pt tall; shrinking it on
            // press moves the text above the finger and reads as a glitch
            // rather than as feedback.
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AlmanacPrimaryButtonStyle: ButtonStyle {    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AlmanacTypography.font(.bodyMedium))
            .foregroundStyle(AlmanacPalette.onAccent)
            .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumControl)
            .padding(.horizontal, 18)
            .background(AlmanacPalette.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AlmanacSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AlmanacTypography.font(.bodyMedium))
            .foregroundStyle(AlmanacPalette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumControl)
            .padding(.horizontal, 18)
            .background(AlmanacPalette.surface.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AlmanacMetrics.controlRadius, style: .continuous)
                    .inset(by: AlmanacMetrics.ruleWeight / 2)
                    .stroke(AlmanacPalette.divider, lineWidth: AlmanacMetrics.ruleWeight)
            }
    }
}

extension View {
    @ViewBuilder
    func almanacNavigationHost(_ embedded: Bool) -> some View {
        if embedded {
            self
        } else {
            NavigationStack { self }
        }
    }

    func almanacModuleSurface() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AlmanacPalette.canvas)
            .tint(AlmanacPalette.accent)
    }

    func almanacScreen() -> some View {
        self
            .tint(AlmanacPalette.accent)
            .background(AlmanacPalette.canvas.ignoresSafeArea())
    }
}
