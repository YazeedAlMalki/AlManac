import Foundation

/// Spec §5.21 `fasting_session.sessionType`.
public enum FastingSessionType: String, Sendable, Hashable, Codable {
    case ifPlanned = "if_planned"
    case ifConfirmedSuggestion = "if_confirmed_suggestion"
    case religious
}

/// One correction applied to an already-recorded session by a backdated
/// calorie entry — spec §11.1's `correctionHistory` audit trail.
public struct FastingCorrection: Sendable, Hashable, Codable {
    public enum Action: String, Sendable, Hashable, Codable {
        case invalidated
        case shortened
        case extended
    }

    public let action: Action
    public let entryTimestamp: Date
    public let previousEndTimestamp: Date?
    public let recordedAt: Date

    public init(action: Action, entryTimestamp: Date, previousEndTimestamp: Date?, recordedAt: Date) {
        self.action = action
        self.entryTimestamp = entryTimestamp
        self.previousEndTimestamp = previousEndTimestamp
        self.recordedAt = recordedAt
    }
}

/// A fasting session not yet written to storage.
public struct FastingSessionDraft: Sendable {
    public var startTimestamp: Date
    public var sessionType: FastingSessionType
    public var isDryFast: Bool
    public var protocolName: String?  // 16_8 | 18_6 | omad | custom | nil
    public var windowHours: Double?
    public var timezoneOffset: Int?

    public init(startTimestamp: Date, sessionType: FastingSessionType, isDryFast: Bool = false,
                protocolName: String? = nil, windowHours: Double? = nil, timezoneOffset: Int? = nil) {
        self.startTimestamp = startTimestamp
        self.sessionType = sessionType
        self.isDryFast = isDryFast
        self.protocolName = protocolName
        self.windowHours = windowHours
        self.timezoneOffset = timezoneOffset
    }
}

/// A fasting session read from storage.
public struct FastingSession: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let startTimestamp: Date
    public let endTimestamp: Date?
    public let logicalDay: String
    public let sessionType: FastingSessionType
    public let isDryFast: Bool
    public let protocolName: String?
    public let windowHours: Double?
    public let isActive: Bool
    public let isInvalidated: Bool
    public let finalDurationMinutes: Int?
    public let correctionHistory: [FastingCorrection]
    public let createdAt: Date
    public let updatedAt: Date
}

/// The result of logging a calorie-bearing entry against fasting state —
/// spec §11.1's fast-breaking and backdating rules.
public enum FastingBreakOutcome: Sendable, Hashable {
    /// Zero calories (water, black coffee/tea), or no session was affected.
    case noOp
    /// The active session was broken at `at`, in the normal, non-backdated flow.
    case ended(sessionId: Int64, durationMinutes: Int)
    /// A backdated entry landed inside an already-ended session's span, moving its end earlier.
    case shortened(sessionId: Int64, durationMinutes: Int)
    /// A backdated entry landed before a session's start — the session never really happened as recorded.
    case invalidated(sessionId: Int64)
    /// An edit removed the calorie-bearing entry that had ended this session.
    case restored(sessionId: Int64)
}

/// Spec §11.1: "No calories have been logged for [N] hours. Are you
/// currently fasting?" Pure decision, same shape as `SleepClassifier` —
/// the caller supplies the elapsed gap (from `NutritionLogStore`), this
/// just applies the threshold.
public enum IFSuggestion {
    public static func shouldSuggest(hoursSinceLastCalorieEntry: Double, thresholdHours: Double = 14) -> Bool {
        hoursSinceLastCalorieEntry >= thresholdHours
    }
}
