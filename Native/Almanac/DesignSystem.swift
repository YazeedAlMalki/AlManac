import SwiftUI
import UIKit
import CoreText

/// Shared visual tokens for the first Almanac design-system slice.
/// Values mirror the approved UI Design Reference v1.0; final status colors
/// still need confirmation on physical devices.
enum AlmanacPalette {
    static let canvas = dynamic(light: 0xF4F3EE, dark: 0x14171A)
    static let surface = dynamic(light: 0xFBFAF6, dark: 0x1D2023)
    static let surfaceMuted = dynamic(light: 0xECEBE5, dark: 0x25292E)
    static let textPrimary = dynamic(light: 0x191918, dark: 0xECEAE3)
    static let textSecondary = dynamic(light: 0x64635F, dark: 0x9BA1A8)
    static let divider = dynamic(light: 0xDFDED7, dark: 0x34393F)
    static let accent = dynamic(light: 0x0A5FFF, dark: 0x4C8CFF)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x101214)
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
            case .bodyMedium, .label, .data: return .medium
            default: return .regular
            }
        }

        var usesMediumFamily: Bool {
            switch self {
            case .bodyMedium, .label, .data: return true
            default: return false
            }
        }
    }

    private static let frauncesRegular = ["Fraunces-Regular", "Fraunces"]
    private static let frauncesMedium = ["Fraunces-Medium", "Fraunces-SemiBold", "Fraunces"]
    private static let neueRegular = ["PPNeueMontreal-Regular", "NeueMontreal-Regular", "Neue Montreal"]
    private static let neueMedium = ["PPNeueMontreal-Medium", "NeueMontreal-Medium", "Neue Montreal"]
    private static let almaraiRegular = ["Almarai-Regular", "Almarai"]
    private static let almaraiBold = ["Almarai-Bold", "Almarai"]

    static func font(_ role: Role, locale: Locale = .current) -> Font {
        let candidates: [String]
        if locale.language.languageCode?.identifier == "ar" {
            candidates = role.usesMediumFamily ? almaraiBold : almaraiRegular
        } else {
            switch role {
            case .display, .screenTitle, .sectionTitle:
                candidates = role.usesMediumFamily ? frauncesMedium : frauncesRegular
            case .body, .bodyMedium, .label, .data:
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

enum AlmanacMetrics {
    static let screenInset: CGFloat = 20
    static let regularInset: CGFloat = 28
    static let cardPadding: CGFloat = 24
    static let sectionGap: CGFloat = 32
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 10
    static let chartRadius: CGFloat = 12
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

struct AlmanacCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = AlmanacMetrics.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AlmanacPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
                    .stroke(AlmanacPalette.divider, lineWidth: 1)
            }
    }
}

struct AlmanacSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(AlmanacTypography.font(.label))
                .tracking(1.1)
                .foregroundStyle(AlmanacPalette.textSecondary)
            Spacer(minLength: 16)
            if let detail {
                Text(detail)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
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
    func almanacScreen() -> some View {
        self
            .tint(AlmanacPalette.accent)
            .background(AlmanacPalette.canvas.ignoresSafeArea())
    }
}
