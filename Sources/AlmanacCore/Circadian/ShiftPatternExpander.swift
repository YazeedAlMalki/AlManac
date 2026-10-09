import Foundation

/// Turns a stored recurrence rule (§5.5 `shift_recurrence_pattern`) into the
/// dated shifts the rest of the app reads.
///
/// `shiftSequence` is a JSON array with one `ShiftType` raw value per day,
/// repeating from `startDate`. A weekly pattern is seven entries; "four on,
/// four off" is eight.
public enum ShiftPatternExpander {

    /// One draft per day from the pattern's start through `last` (or the
    /// pattern's own end date, whichever comes first).
    public static func occurrences(for pattern: ShiftRecurrencePatternDraft,
                                   patternId: Int64? = nil,
                                   through last: LogicalDay,
                                   timeModel: TimeModel) throws -> [ShiftOccurrenceDraft] {
        guard pattern.patternType != "monthly_rotation" else {
            throw ShiftPatternError.unsupportedPatternType(pattern.patternType)
        }
        // Strict, not `compactMap`: dropping an unrecognised name would pull
        // every later day one place forward and nothing would say so.
        let sequence = try JSONDecoder().decode([String].self, from: Data(pattern.shiftSequence.utf8))
            .map { name -> ShiftType in
                guard let shift = ShiftType(rawValue: name) else { throw ShiftPatternError.unknownShiftType(name) }
                return shift
            }

        guard !sequence.isEmpty else { throw ShiftPatternError.emptySequence }

        let finalDay = pattern.endDate.map { min(LogicalDay($0), last) } ?? last
        var drafts: [ShiftOccurrenceDraft] = []
        var cursor: LogicalDay? = LogicalDay(pattern.startDate)
        while let day = cursor, day <= finalDay {
            drafts.append(ShiftOccurrenceDraft(scheduleId: pattern.scheduleId, date: day.value,
                                               shiftType: sequence[drafts.count % sequence.count],
                                               recurrencePatternId: patternId))
            cursor = timeModel.day(after: day)
        }
        return drafts
    }
}

public enum ShiftPatternError: Error, Equatable {
    case unsupportedPatternType(String)
    case unknownShiftType(String)
    case emptySequence
}

extension ShiftRecurrencePatternDraft {
    /// A day-by-day rotation from the shifts themselves, so a caller never
    /// writes the JSON `shiftSequence` holds.
    public init(scheduleId: Int64, shifts: [ShiftType], startDate: String, endDate: String? = nil) {
        // Encoding an array of plain strings cannot fail; "[]" is the honest
        // fallback and `ShiftPatternExpander` refuses it by name.
        let json = (try? JSONEncoder().encode(shifts.map(\.rawValue)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.init(scheduleId: scheduleId, patternType: "custom", shiftSequence: json,
                  startDate: startDate, endDate: endDate)
    }
}
