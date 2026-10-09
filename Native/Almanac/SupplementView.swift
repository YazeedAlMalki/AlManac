import SwiftUI
import AlmanacCore
import Foundation

/// Supplement plans and today's adherence.
///
/// The screen is about one thing — *did I take what I said I would* — so today's
/// adherence is the one prominent card (doctrine rule 2) and the plan list is
/// ruled beneath it. Reading the screen top to bottom answers the question in
/// the order it gets asked: how am I doing, then what is the plan, then what
/// happened on previous days.
///
/// **Why plans are not hidden once deactivated.** `SupplementPlanStore`
/// deactivates rather than deletes so `supplement_log` keeps pointing at a real
/// plan. A screen that listed only active plans would therefore show a
/// discontinued supplement as though it had never existed, while its adherence
/// history sat in the database unreferenced by anything on screen.
@MainActor
struct SupplementView: View {
    let db: Database
    @ObservedObject var trackingModel: TrackingCalendarModel

    @State private var plans: [SupplementPlan] = []
    @State private var todayEntries: [SupplementLogEntry] = []
    @State private var recentHistory: [SupplementLogEntry] = []
    @State private var editingPlan: SupplementPlan?
    @State private var addingPlan = false
    @State private var error: String?
    @State private var readProblem: String?

    private let timeModel = TimeModel(timeZone: .current)

    /// Days of past adherence shown below the plan list. Bounded on purpose:
    /// this is a logbook, not an analytics screen, and the day-detail surfaces
    /// are where a longer range belongs.
    private static let historyDayCount = 14

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            Section {
                AlmanacCard(prominent: true) { adherenceSummary }
            }

            Section {
                if plans.filter(\.isActive).isEmpty {
                    Text("No supplement plans yet. Add one to start tracking adherence.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(plans) { plan in
                        planRow(plan)
                    }
                }
                Button("Add plan", systemImage: AlmanacIcon.quickAdd) { addingPlan = true }
            } header: {
                AlmanacSectionHeader(title: String(localized: "Plans"))
            } footer: {
                Text("A plan you stop taking is kept rather than removed, so its history stays attached to it.")
            }

            if !recentHistory.isEmpty {
                Section {
                    ForEach(recentHistory) { entry in
                        historyRow(entry)
                    }
                } header: {
                    AlmanacSectionHeader(title: String(localized: "Recent history"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Supplements")
        .task { reload() }
        .sheet(isPresented: $addingPlan) {
            SupplementPlanEditor(db: db, plan: nil) { reload() }
        }
        .sheet(item: $editingPlan) { plan in
            SupplementPlanEditor(db: db, plan: plan) { reload() }
        }
        .editorError($error)
    }

    // MARK: - Adherence

    /// The day's position, in words.
    ///
    /// Two claims, kept apart on purpose (doctrine rule 10): "you took 2 of 3"
    /// is a reading, and "nothing is due yet" is an absence of one. A custom
    /// frequency has no computable due count, so it says so rather than
    /// dividing by a number it made up.
    private var adherenceSummary: some View {
        let active = plans.filter(\.isActive)
        let due = dueCountToday(active)
        let taken = todayEntries.filter(\.taken).count

        return VStack(alignment: .leading, spacing: 10) {
            AlmanacEyebrow(text: String(localized: "Today"))
            Text(headline(due: due, taken: taken))
                .font(AlmanacTypography.font(.sectionTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = readProblem {
                Text(problem)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            if !active.isEmpty {
                AlmanacRule()
                VStack(spacing: 0) {
                    ForEach(active) { plan in
                        Button { toggle(plan) } label: {
                            adherenceToggle(plan)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("supplement-toggle-\(plan.id)")
                        if plan.id != active.last?.id { AlmanacRule(inset: AlmanacRule.metricTextInset) }
                    }
                }
            }
        }
    }

    private func adherenceToggle(_ plan: SupplementPlan) -> some View {
        let state = state(for: plan)
        // `AlmanacMetricRow` rather than a hand-built HStack: it is the design
        // system's row, so this gets the icon well, the monospaced reading and
        // the accessibility-size reflow (where the value moves to its own line)
        // for free instead of re-deriving all three.
        //
        // The tone is always passed rather than nil for "not logged": a nil tone
        // falls back to the accent for the icon, and an unlogged supplement is
        // not something Almanac measured. `.neutral`'s colour is `textSecondary`,
        // which is the right reading for it.
        return AlmanacMetricRow(icon: state.symbol,
                                title: plan.name,
                                value: state.label,
                                detail: plan.timingNotes ?? SupplementSchedule.title(plan.frequency),
                                tone: state.tone)
            .contentShape(Rectangle())
    }

    /// Only a plan whose frequency states a count can say "1 of 2". For the rest
    /// the honest reading is whether *anything* was logged, because the plan's
    /// own notes are the only statement of how often it is due.
    private func headline(due: Int?, taken: Int) -> String {
        guard due != 0 else { return String(localized: "Nothing due yet today") }
        guard let due else {
            if taken == 0 { return String(localized: "Nothing logged today") }
            return taken == 1 ? "1 logged today" : "\(taken) logged today"
        }
        if taken >= due { return String(localized: "All \(due) taken") }
        if taken == 0 { return String(localized: "None of \(due) taken") }
        return "\(taken) of \(due) taken"
    }

    private func state(for plan: SupplementPlan) -> (symbol: String, label: String, tone: AlmanacStatusTone) {
        let entries = todayEntries.filter { $0.planId == plan.id }
        if entries.contains(where: { !$0.taken }) {
            return ("xmark.circle.fill", String(localized: "Logged as not taken"), .warning)
        }
        if !entries.isEmpty {
            let count = entries.filter(\.taken).count
            return ("checkmark.circle.fill",
                    count == 1 ? String(localized: "Taken") : String(localized: "Taken \(count)×"),
                    .good)
        }
        return ("circle", String(localized: "Not logged"), .neutral)
    }

    private func dueCountToday(_ active: [SupplementPlan]) -> Int? {
        // Every plan here is either "due a countable number of times" or "due
        // according to notes this screen cannot read". Mixing the two into one
        // number would be the average of a fact and a guess, so the mixed case
        // reports nil and `headline` words it.
        let counts = active.map { SupplementSchedule.expectedPerDay($0.frequency) }
        guard !counts.isEmpty, !counts.contains(where: { $0 == nil }) else { return nil }
        return counts.reduce(0) { $0 + ($1 ?? 0) }
    }

    private func toggle(_ plan: SupplementPlan) {
        do {
            let existing = todayEntries.first { $0.planId == plan.id }
            if let existing {
                try SupplementLogStore(db: db).delete(id: existing.id)
            } else {
                let now = Date()
                _ = try SupplementLogStore(db: db).log(
                    SupplementLogDraft(planId: plan.id, timestamp: now),
                    logicalDay: timeModel.logicalDay(now).value)
            }
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Plans

    private func planRow(_ plan: SupplementPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(plan.isActive ? AlmanacPalette.textPrimary : AlmanacPalette.textSecondary)
                Spacer(minLength: 12)
                Text(verbatim: "\(AlmanacNumber.compact(plan.doseAmount)) \(UnitDisplay.localized(plan.doseUnit))")
                    .font(AlmanacTypography.font(.data).monospacedDigit())
                    .foregroundStyle(AlmanacPalette.textPrimary)
            }
            HStack(spacing: 6) {
                Text(SupplementSchedule.title(plan.frequency))
                if !plan.isActive {
                    Text("·")
                    Text("Discontinued")
                }
                if plan.reminderEnabled {
                    Text("·")
                    Text("Reminder at \(reminderTime(plan))")
                }
            }
            .font(AlmanacTypography.font(.caption))
            .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .contentShape(Rectangle())
        .onTapGesture { editingPlan = plan }
        .swipeActions(edge: .trailing) {
            Button("Edit") { editingPlan = plan }
            if plan.isActive {
                Button("Discontinue", role: .destructive) { deactivate(plan) }
            }
        }
        .contextMenu {
            Button("Edit") { editingPlan = plan }
            if plan.isActive {
                Button("Discontinue", role: .destructive) { deactivate(plan) }
            }
        }
    }

    private func deactivate(_ plan: SupplementPlan) {
        do {
            try SupplementPlanStore(db: db).deactivate(id: plan.id)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func reminderTime(_ plan: SupplementPlan) -> String {
        guard let minute = plan.reminderMinuteOfDay else { return "—" }
        return NumberDisplay.localized(String(format: "%02d:%02d", minute / 60, minute % 60))
    }

    // MARK: - History

    private func historyRow(_ entry: SupplementLogEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(planName(entry.planId))
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text(entry.timestamp.almanacFormatted(date: .abbreviated, time: .shortened))
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Spacer(minLength: 12)
            Text(entry.taken ? String(localized: "Taken") : String(localized: "Not taken"))
                .font(AlmanacTypography.font(.label))
                .foregroundStyle(entry.taken ? AlmanacPalette.good : AlmanacPalette.warning)
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .swipeActions {
            Button("Delete", role: .destructive) { delete(entry) }
        }
    }

    private func delete(_ entry: SupplementLogEntry) {
        do {
            try SupplementLogStore(db: db).delete(id: entry.id)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// A plan that has been discontinued is still in `plans`, so a historical
    /// entry always has a name to show. The fallback is a real possibility
    /// though — a plan row could be removed out from under its log — and showing
    /// the raw id would be worse than saying so.
    private func planName(_ id: Int64) -> String {
        plans.first { $0.id == id }?.name ?? String(localized: "Unknown plan")
    }

    // MARK: - Load

    private func reload() {
        do {
            plans = try SupplementPlanStore(db: db).allPlans()
            let log = SupplementLogStore(db: db)
            let today = timeModel.logicalDay(Date())
            todayEntries = try log.entries(for: today.value)
            let start = timeModel.day(before: today, count: Self.historyDayCount - 1)
            let end = timeModel.day(after: today)
            recentHistory = try log.entries(from: (start ?? today).value, to: (end ?? today).value)
            readProblem = nil
            trackingModel.refresh()
        } catch {
            // The note clears itself the moment a read succeeds, so a screen that
            // is merely empty and a screen that could not be read never look the
            // same — the same distinction `AlmanacProblemNote` exists for.
            self.error = String(describing: error)
            readProblem = String(localized: "Could not read your supplement plans.")
        }
    }
}

private extension TimeModel {
    /// `count` logical days before `day`, or nil if the calendar runs out.
    func day(before day: LogicalDay, count: Int) -> LogicalDay? {
        var cursor = day
        for _ in 0..<count {
            guard let previous = self.day(before: cursor) else { return nil }
            cursor = previous
        }
        return cursor
    }
}
