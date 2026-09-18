import Testing
@testable import AlmanacCore

/// Appendix B ("Notification Suppression Matrix"), cell by cell — every
/// documented "🚫 suppress" and every documented "✅ send" is asserted
/// explicitly, so the table in the spec and this file can be checked
/// against each other directly.
@Suite("NotificationSuppressionMatrix Tests")
struct NotificationSuppressionMatrixTests {
    private let allClear = NotificationSuppressionContext()

    @Test("Nothing is suppressed when no axis is set")
    func allClearSuppressesNothing() {
        for type in NotificationType.allCases {
            #expect(!NotificationSuppressionMatrix.shouldSuppress(type, in: allClear), "\(type)")
        }
    }

    @Test("Readiness: suppressed post-shift-sleep or once already final; sent during a dry fast, confirmed IF, night shift")
    func readiness() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.readiness,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(NotificationSuppressionMatrix.shouldSuppress(.readiness,
            in: NotificationSuppressionContext(isReadinessAlreadyFinal: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.readiness,
            in: NotificationSuppressionContext(isDryFastActive: true, isConfirmedIFActive: true, isNightShift: true)))
    }

    @Test("Water: suppressed during a dry fast or post-shift sleep; sent during confirmed IF or night shift")
    func water() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.water,
            in: NotificationSuppressionContext(isDryFastActive: true)))
        #expect(NotificationSuppressionMatrix.shouldSuppress(.water,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.water,
            in: NotificationSuppressionContext(isConfirmedIFActive: true, isNightShift: true)))
    }

    @Test("Meal: suppressed during confirmed IF or post-shift sleep; sent during a dry fast or night shift")
    func meal() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.meal,
            in: NotificationSuppressionContext(isConfirmedIFActive: true)))
        #expect(NotificationSuppressionMatrix.shouldSuppress(.meal,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.meal,
            in: NotificationSuppressionContext(isDryFastActive: true, isNightShift: true)))
    }

    @Test("Bedtime: suppressed during night shift or post-shift sleep; sent during a dry fast or confirmed IF")
    func bedtime() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.bedtime,
            in: NotificationSuppressionContext(isNightShift: true)))
        #expect(NotificationSuppressionMatrix.shouldSuppress(.bedtime,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.bedtime,
            in: NotificationSuppressionContext(isDryFastActive: true, isConfirmedIFActive: true)))
    }

    @Test("Supplement: suppressed only by post-shift sleep — every other axis is \"send\"")
    func supplement() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.supplement,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.supplement,
            in: NotificationSuppressionContext(isDryFastActive: true, isConfirmedIFActive: true, isNightShift: true)))
    }

    @Test("Suhoor: the table's only dry-fast 🚫 cell, transcribed as written despite its confusing footnote (see the doc comment)")
    func suhoor() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.suhoor,
            in: NotificationSuppressionContext(isDryFastActive: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.suhoor,
            in: NotificationSuppressionContext(isNightShift: true, isPostShiftSleep: true)))
    }

    @Test("Iftar: never suppressed by any of these five axes")
    func iftar() {
        let everything = NotificationSuppressionContext(isDryFastActive: true, isConfirmedIFActive: true,
            isNightShift: true, isPostShiftSleep: true, isReadinessAlreadyFinal: true)
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.iftar, in: everything))
    }

    @Test("Contextual snack: suppressed during confirmed IF or post-shift sleep; sent during a dry fast or night shift")
    func contextualSnack() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.contextualSnack,
            in: NotificationSuppressionContext(isConfirmedIFActive: true)))
        #expect(NotificationSuppressionMatrix.shouldSuppress(.contextualSnack,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.contextualSnack,
            in: NotificationSuppressionContext(isDryFastActive: true, isNightShift: true)))
    }

    @Test("Contextual hydration: suppressed during a dry fast or post-shift sleep; sent during confirmed IF or night shift")
    func contextualHydration() {
        #expect(NotificationSuppressionMatrix.shouldSuppress(.contextualHydration,
            in: NotificationSuppressionContext(isDryFastActive: true)))
        #expect(NotificationSuppressionMatrix.shouldSuppress(.contextualHydration,
            in: NotificationSuppressionContext(isPostShiftSleep: true)))
        #expect(!NotificationSuppressionMatrix.shouldSuppress(.contextualHydration,
            in: NotificationSuppressionContext(isConfirmedIFActive: true, isNightShift: true)))
    }
}
