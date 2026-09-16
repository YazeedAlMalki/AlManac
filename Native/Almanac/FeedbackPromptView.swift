import SwiftUI
import AlmanacCore

/// §9.10's feedback question, shown for a *previous* cycle's outcome — never
/// directly under today's score, which is the one thing the spec explicitly
/// forbids ("NEVER shown immediately after the readiness score is
/// displayed"). `ReadinessModel.pendingFeedback` only ever holds a past,
/// already-scored, not-yet-rated cycle, so this view has nothing to check
/// beyond "is there one to show."
@MainActor
struct FeedbackPromptView: View {
    @ObservedObject var model: ReadinessModel
    @State private var error: String?

    var body: some View {
        if let record = model.pendingFeedback {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Was \(record.anchorDate)'s guidance helpful?")
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        Button {
                            submit("thumbs_up")
                        } label: {
                            Label("Yes", systemImage: "hand.thumbsup")
                        }.buttonStyle(.bordered)
                        Button {
                            submit("thumbs_down")
                        } label: {
                            Label("No", systemImage: "hand.thumbsdown")
                        }.buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            .editorError($error)
        }
    }

    private func submit(_ value: String) {
        do { try model.submitFeedback(value) }
        catch { self.error = String(describing: error) }
    }
}
