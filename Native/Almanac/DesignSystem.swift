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
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        case .veryLow: return "Very low confidence"
        case .insufficient: return "Insufficient data"
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
    static func compact(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
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
}

enum AlmanacAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
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
enum AlmanacIcon {
    static let today = "circle.grid.2x2"
    static let trends = "chart.xyaxis.line"
    static let modules = "square.grid.2x2"
    static let quickAdd = "plus"
    static let sleep = "bed.double"
    static let hydration = "drop"
    static let nutrition = "fork.knife"
    static let training = "dumbbell"
    static let body = "ruler"
    static let check = "checkmark"
    static let edit = "pencil"
    static let previous = "chevron.left"
    static let next = "chevron.right"
    static let laboratory = "cross.case"
    static let profile = "person"
    static let prayer = "sun.horizon"
    static let fasting = "moon.stars"
    static let settings = "gearshape"
}

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
                RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
                    .stroke(AlmanacPalette.divider, lineWidth: 1)
            }
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
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

    private var iconView: some View {
        Image(systemName: icon)
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

struct AlmanacPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
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
                    .stroke(AlmanacPalette.divider, lineWidth: 1)
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
