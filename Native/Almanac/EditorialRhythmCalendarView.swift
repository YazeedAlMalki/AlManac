import SwiftUI
import AlmanacCore

/// Editorial rendering of the existing activity-ring month. It deliberately
/// reuses `TrackingCalendarModel` and `ActivityRingDayEditor`; only the visual
/// layer is new.
struct EditorialRhythmCalendarView: View {
    @ObservedObject var model: TrackingCalendarModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        AlmanacCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader

                if dynamicTypeSize.isAccessibilitySize {
                    accessibleDayList
                } else {
                    monthGrid
                }

                if model.isLoading {
                    ProgressView("Updating rhythm")
                        .font(AlmanacTypography.font(.caption))
                        .tint(AlmanacPalette.accent)
                        .frame(maxWidth: .infinity)
                } else if let error = model.error {
                    Text(error)
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.critical)
                } else if let day = model.selectedActivity {
                    Divider().overlay(AlmanacPalette.divider)
                    selectedDay(day)
                }

                Text("Almanac days begin at 04:00 local time.")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            model.tick()
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            monthButton(systemName: AlmanacIcon.previous, label: "Previous month", action: model.previousMonth)

            Spacer(minLength: 4)
            Text(model.monthTitle)
                .font(AlmanacTypography.font(.sectionTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .multilineTextAlignment(.center)
                .id(model.month.id)
                .accessibilityIdentifier("activity-ring-month-title")
            Spacer(minLength: 4)

            monthButton(systemName: AlmanacIcon.next, label: "Next month", action: model.nextMonth)
        }
    }

    private func monthButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<model.leadingBlankCount, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }
                ForEach(model.month.days) { day in
                    Button {
                        model.select(day)
                    } label: {
                        EditorialActivityRingDayCell(
                            day: day,
                            isToday: day.day == model.todayDay,
                            isSelected: day.day == model.selectedDay
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .accessibilityIdentifier("activity-ring-day-\(day.day.value)")
                    .accessibilityLabel(accessibilityLabel(for: day))
                }
            }
        }
    }

    private var accessibleDayList: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.month.days) { day in
                Button {
                    model.select(day)
                } label: {
                    HStack(spacing: 14) {
                        Text(displayDay(day.day))
                            .font(AlmanacTypography.font(.data))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                            .frame(width: 118, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(accessibilityLabel(for: day))
                                .font(AlmanacTypography.font(.body))
                                .foregroundStyle(AlmanacPalette.textPrimary)
                                .multilineTextAlignment(.leading)
                            if day.isGolden {
                                Text("All visible rings complete")
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.good)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: day.day == model.selectedDay ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(day.day == model.selectedDay ? AlmanacPalette.accent : AlmanacPalette.textSecondary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity-ring-day-\(day.day.value)")
                Divider().overlay(AlmanacPalette.divider)
            }
        }
    }

    private func selectedDay(_ day: ActivityRingDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rings for \(displayDay(day.day))")
                .font(AlmanacTypography.font(.sectionTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)

            ringRow(
                title: "Hydration",
                state: day.hydration == .complete ? "Target met" : "Target not met",
                detail: "\(AlmanacNumber.compact(day.hydrationTotalMilliliters.value)) of \(AlmanacNumber.compact(day.hydrationTargetMilliliters.value)) mL",
                complete: day.hydration == .complete
            )
            ringRow(
                title: "Training",
                state: day.training == .complete ? "Logged" : "Not logged",
                detail: nil,
                complete: day.training == .complete
            )
            let nutrition = nutritionPresentation(day.nutrition)
            ringRow(
                title: "Nutrition",
                state: nutrition.state,
                detail: nutrition.detail,
                complete: nutrition.complete
            )
            if day.nutrition == .dietProfileRequired {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-value status")
                        .font(AlmanacTypography.font(.bodyMedium))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    ForEach(["Calories", "Carbohydrates", "Protein", "Fat", "Fiber"], id: \.self) { name in
                        HStack(spacing: 8) {
                            Text(name)
                                .font(AlmanacTypography.font(.body))
                                .foregroundStyle(AlmanacPalette.textPrimary)
                            Spacer(minLength: 8)
                            Text("Not set")
                                .font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AlmanacPalette.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            ringRow(
                title: "Digestion",
                state: day.digestion == .disabled ? "Off" : "Fill rule unavailable",
                detail: nil,
                complete: false
            )

            NavigationLink {
                ActivityRingDayEditor(db: model.database, day: day.day) {
                    model.refresh()
                }
            } label: {
                Label("Edit selected day's logs", systemImage: AlmanacIcon.edit)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AlmanacSecondaryButtonStyle())
            .disabled(model.database == nil)

            if day.isGolden {
                AlmanacStatusMark(text: "Golden day, every visible ring complete", tone: .good)
            }

            if model.summary.isEmpty {
                Text("No other tracked records on \(displayDay(LogicalDay(model.summary.day))).")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                DisclosureGroup("Tracked records") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.summary.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(AlmanacTypography.font(.bodyMedium))
                                    .foregroundStyle(AlmanacPalette.textPrimary)
                                if let value = item.value, !value.isEmpty {
                                    Text(value)
                                        .font(AlmanacTypography.font(.body).monospacedDigit())
                                        .foregroundStyle(AlmanacPalette.textSecondary)
                                }
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(AlmanacTypography.font(.caption))
                                        .foregroundStyle(AlmanacPalette.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 12)
                }
                // Disclosure chrome is navigation, not a reading, so it keeps
                // the ink colors; the accent is reserved for measured state.
                .font(AlmanacTypography.font(.bodyMedium))
                .tint(AlmanacPalette.textPrimary)
            }
        }
    }

    private func ringRow(title: String, state: String, detail: String?, complete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(complete ? AlmanacPalette.accent : AlmanacPalette.textSecondary)
                .font(.system(size: 18, weight: .medium))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text(state)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(AlmanacTypography.font(.caption).monospacedDigit())
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func nutritionPresentation(_ state: ActivityRingNutritionState) -> (state: String, detail: String?, complete: Bool) {
        switch state {
        case .hit: return ("Targets hit", nil, true)
        case .off: return ("Outside target", nil, false)
        case .mess: return ("Well outside target", nil, false)
        case .notLogged: return ("No nutrition logged", "No nutrition ring", false)
        case .dietProfileRequired:
            return ("No targets yet", "Add a Diet Profile to set nutrition targets", false)
        }
    }

    private func accessibilityLabel(for day: ActivityRingDay) -> String {
        let hydration = day.hydration == .complete ? "complete" : "incomplete"
        let training = day.training == .complete ? "complete" : "incomplete"
        let nutrition = nutritionPresentation(day.nutrition).state
        let digestion = day.digestion == .disabled ? "off" : "fill rule unavailable"
        var parts = [displayDay(day.day), "Hydration \(hydration)", "Training \(training)", "Nutrition \(nutrition)", "Digestion \(digestion)"]
        if day.isGolden { parts.append("golden day") }
        if day.day == model.todayDay { parts.append("today") }
        if day.day == model.selectedDay { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    private func displayDay(_ day: LogicalDay) -> String {
        let parts = day.value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day.value }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        guard let date else { return day.value }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

private struct EditorialActivityRingDayCell: View {
    let day: ActivityRingDay
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AlmanacPalette.surfaceMuted : Color.clear)

            ring(
                diameter: 31,
                complete: day.hydration == .complete,
                color: AlmanacPalette.accent,
                dash: nil
            )
            ring(
                diameter: 22,
                complete: day.training == .complete,
                color: AlmanacPalette.textPrimary,
                dash: nil
            )

            nutritionRing

            if day.digestion == .fillRuleUnavailable {
                Circle()
                    .strokeBorder(AlmanacPalette.textSecondary, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                    .frame(width: 10, height: 10)
            }

            if isToday {
                Circle()
                    .strokeBorder(AlmanacPalette.accent, lineWidth: 1.5)
                    .frame(width: 39, height: 39)
            }

            Text(String(day.dayNumber))
                .font(AlmanacTypography.font(.dayNumber).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textPrimary)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .topTrailing) {
            if day.isGolden {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AlmanacPalette.good)
                    .offset(x: 1, y: -1)
            }
        }
    }

    private func ring(diameter: CGFloat, complete: Bool, color: Color, dash: [CGFloat]?) -> some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(complete ? 0.95 : 0.16), style: StrokeStyle(lineWidth: 2.4, dash: dash ?? []))
                .frame(width: diameter, height: diameter)
            if complete {
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
            }
        }
    }

    @ViewBuilder
    private var nutritionRing: some View {
        switch day.nutrition {
        case .hit:
            ring(diameter: 13, complete: true, color: AlmanacPalette.good, dash: nil)
        case .off:
            ring(diameter: 13, complete: true, color: AlmanacPalette.warning, dash: [2.5, 2])
        case .mess:
            ring(diameter: 13, complete: true, color: AlmanacPalette.critical, dash: [1.5, 2])
        case .dietProfileRequired:
            ring(diameter: 13, complete: false, color: AlmanacPalette.warning, dash: [2, 2])
        case .notLogged:
            EmptyView()
        }
    }
}
