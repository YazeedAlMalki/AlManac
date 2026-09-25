import SwiftUI
import AlmanacCore

/// §9.10's feedback question, shown for a *previous* cycle's outcome — never
/// directly under today's score, which is the one thing the spec explicitly
/// forbids. The rendering is a standalone card so it can live in Today’s
/// scrolling editorial layout without depending on `List` sections.
@MainActor
struct FeedbackPromptView: View {
    @ObservedObject var model: ReadinessModel
    @State private var error: String?

    var body: some View {
        if let record = model.pendingFeedback {
            AlmanacCard {
                VStack(alignment: .leading, spacing: 14) {
                    AlmanacSectionHeader(title: "A note from yesterday")
                    Text("Was \(record.anchorDate)’s guidance helpful?")
                        .font(AlmanacTypography.font(.bodyMedium))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    HStack(spacing: 12) {
                        Button {
                            submit("thumbs_up")
                        } label: {
                            Label("Yes", systemImage: "hand.thumbsup")
                        }
                        .buttonStyle(AlmanacSecondaryButtonStyle())

                        Button {
                            submit("thumbs_down")
                        } label: {
                            Label("No", systemImage: "hand.thumbsdown")
                        }
                        .buttonStyle(AlmanacSecondaryButtonStyle())
                    }
                }
            }
            .editorError($error)
        }
    }

    private func submit(_ value: String) {
        do { try model.submitFeedback(value) }
        catch { self.error = String(describing: error) }
    }
}
