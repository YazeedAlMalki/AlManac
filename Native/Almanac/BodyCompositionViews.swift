import SwiftUI
import AlmanacCore

/// One metric's card: a name, a number, a meter, and one sentence.
///
/// ## The card is one accessibility element, and its text comes from core
///
/// `progress.accessibilityDescription` is used verbatim as the label, with the
/// children ignored. That is the whole reason those strings live in
/// `BodyCompositionProgress` rather than being assembled here: a screen-reader
/// user and a sighted user are then reading the *same sentence*, produced by the
/// same code, and a change to one cannot leave the other describing a different
/// number. The alternative — letting SwiftUI combine a title, a value and a
/// status line — is what this component would have done before, and it announced
/// as "Weight, 72.5 kg, 5.5 kg to go" with the target missing, because the
/// target was never a child of anything.
///
/// The children are ignored rather than combined, following the note on
/// `AlmanacProblemNote`: `.combine` over children that are already the whole
/// content re-announces the container, and a card that speaks twice is worse
/// than one that speaks once and says more.
struct BodyCompositionCard: View {
    let progress: BodyCompositionProgress

    var body: some View {
        AlmanacCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(progress.metric.title)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // The reading, or the fact that there is none. A card whose big
                // number is missing looks broken, so "Nothing recorded" is set in
                // the data font like a value rather than as an empty state.
                Text(progress.currentText ?? "—")
                    .font(AlmanacTypography.font(.data).monospacedDigit())
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                AlmanacMeter(fraction: progress.fraction, tone: meterTone)

                // `statusText` is the sentence that makes an absent meter legible.
                // It is always present, including "No target set" — a card with an
                // empty meter and no explanation reads as a lost reading.
                Text(progress.statusText)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(progress.accessibilityDescription))
    }

    /// Ink until the goal is reached, green once it is.
    ///
    /// **Not the accent.** The accent means "Almanac recorded something", and
    /// spending it on a progress bar fills the screen with a colour that carries
    /// no information. `textSecondary` keeps the grid monochrome — a page of
    /// cards that is only interesting where something has been achieved.
    private var meterTone: AlmanacStatusTone {
        progress.isTargetMet ? .good : .neutral
    }
}

/// The card grid.
///
/// ## Two columns, and the count is not a magic number
///
/// `GridItem(.adaptive(minimum: 160))` rather than a fixed two. A fixed two is
/// right on a phone and wrong on every other width the app will run at — an iPad
/// at full width with two 300pt cards and a river of canvas between them, and a
/// 320pt-wide SE in landscape with two cards too narrow for a target sentence.
/// `adaptive` gives two on a phone, four on an iPad, and never a card narrower
/// than the value can be read at.
struct BodyCompositionGrid: View {
    let cards: [BodyCompositionProgress]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                  spacing: 12) {
            ForEach(cards) { card in
                BodyCompositionCard(progress: card)
            }
        }
    }
}
