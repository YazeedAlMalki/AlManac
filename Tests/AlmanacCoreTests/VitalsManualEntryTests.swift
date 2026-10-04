import Testing
import Foundation
@testable import AlmanacCore

/// Manual entry for the two vitals a readiness score is made of, and the
/// honesty rules that have to hold around it.
///
/// BRD §6.7 promises resting HR, HRV, steps and active energy arrive
/// "imported (HealthKit-authoritative, Section 5.2) with **manual fallback**".
/// Until this, `vitals_record` had exactly one writer — `VitalsRecordHealthBridge`
/// — so the fallback existed on paper and a person without a watch could never
/// produce a readiness score at all. These tests pin the fallback, and pin the
/// three places where adding it would otherwise let a person be mis-scored:
/// the day a reading belongs to, whether it counts as today's, and whether it
/// can be corrected.
@Suite("Vitals Manual Entry Tests")
struct VitalsManualEntryTests {
    private let zone = TimeZone(identifier: "Europe/London")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func makeStore(_ db: Database, clock: any Clock = SystemClock()) -> VitalsRecordStore {
        VitalsRecordStore(
            db: db,
            clock: clock,
            zone: ZoneContext(zone),
            timeModel: TimeModel(timeZone: zone, boundary: .almanac)
        )
    }

    /// 2026-10-03 03:30 London — after midnight, before the 04:00 boundary, so
    /// §7.1's rule says it belongs to 2026-10-02.
    private func instantAt0330() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 3; c.hour = 3; c.minute = 30
        return calendar.date(from: c)!
    }

    /// 2026-10-03 09:00 London — unambiguously today's.
    private func instantAt0900() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 3; c.hour = 9
        return calendar.date(from: c)!
    }

    private var todayStart: Date {
        TimeModel(timeZone: zone, boundary: .almanac).start(of: LogicalDay("2026-10-03"))!
    }

    private var yesterdayStart: Date {
        TimeModel(timeZone: zone, boundary: .almanac).start(of: LogicalDay("2026-10-02"))!
    }

    // MARK: - The vocabulary is the synced vocabulary

    @Test("The hand-entered vocabulary is the one HealthKit writes, checked through the bridge")
    func theVocabularyMatchesTheSyncedVocabulary() throws {
        let db = try TestDatabase()
        let bridge = VitalsRecordHealthBridge(db: db, timeModel: TimeModel(timeZone: zone, boundary: .almanac))
        // `unit: nil` on purpose: the bridge then stores the unit from its own
        // `metricMap`, which is the thing under test. Passing a unit would let
        // the test agree with itself instead of with the bridge.
        let when = instantAt0900()
        let samples = [
            HealthSample(externalID: "hk-rhr-1", domain: .heartRate, start: when, end: when, value: 52, unit: nil),
            HealthSample(externalID: "hk-hrv-1", domain: .hrv, start: when, end: when, value: 48, unit: nil),
        ]
        try bridge.apply(HealthChangeSet(added: samples, deletedExternalIDs: [], nextAnchor: nil), in: db)

        for metric in VitalsMetric.allCases {
            let synced = try #require(
                try db.query("SELECT metric, unit FROM vitals_record WHERE metric = ?;", [.text(metric.rawValue)]).first,
                "the bridge wrote no \(metric.rawValue) row"
            )
            #expect(synced.string("metric") == metric.rawValue)
            #expect(synced.string("unit") == metric.unit)
        }

        // And the other direction: nothing hand-enterable is a metric the bridge
        // leaves out, so adding a case to `VitalsMetric` cannot drift away from
        // the table the readiness engine already reads.
        #expect(Set(VitalsMetric.allCases.map(\.rawValue)) == ["rhr", "hrv"])
    }

    // MARK: - Writing

    @Test("A hand-entered reading lands on the day §7.1 says, not the calendar's")
    func manualEntryUsesTheAlmanacBoundary() throws {
        let db = try TestDatabase()
        let store = makeStore(db)

        let early = try store.recordManual(metric: .restingHeartRate, value: 54,
                                           measuredAt: instantAt0330())
        let late = try store.recordManual(metric: .restingHeartRate, value: 51,
                                          measuredAt: instantAt0900())

        let beforeBoundary = try #require(try store.record(id: early))
        #expect(beforeBoundary.logicalDay == "2026-10-02",
                "03:30 on the 3rd is still the 2nd's night")
        #expect(beforeBoundary.source == VitalsRecordStore.manualSource)

        let afterBoundary = try #require(try store.record(id: late))
        #expect(afterBoundary.logicalDay == "2026-10-03")

        // The store stamps the metric's own unit, so a hand-entered 54 and a
        // synced 54 are the same row to every reader.
        #expect(beforeBoundary.unit == "bpm")
        #expect(beforeBoundary.healthKitUUID == nil)
    }

    @Test("Back-dating is allowed, because the reading was taken then")
    func backDatingKeepsTheInstantItWasTaken() throws {
        let db = try TestDatabase()
        let store = makeStore(db)

        let id = try store.recordManual(metric: .heartRateVariability, value: 44,
                                        measuredAt: instantAt0330())
        let stored = try #require(try store.record(id: id))

        #expect(abs(stored.timestamp.timeIntervalSince(instantAt0330())) < 1,
                "the instant recorded is when the reading was taken, not when it was typed")
        #expect(stored.logicalDay == "2026-10-02")
    }

    @Test("A value that is not a reading is refused")
    func refusesNonReadings() throws {
        let db = try TestDatabase()
        let store = makeStore(db)

        for bad in [0.0, -48.0, Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: VitalsEntryError.invalidValue(.restingHeartRate)) {
                try store.recordManual(metric: .restingHeartRate, value: bad, measuredAt: instantAt0900())
            }
        }
        #expect(throws: VitalsEntryError.invalidValue(.heartRateVariability)) {
            try store.recordManual(metric: .heartRateVariability, value: 0, measuredAt: instantAt0900())
        }
        // Nothing was written by any of those attempts.
        #expect(try store.records(for: "2026-10-03").isEmpty)
    }

    @Test("An out-of-band value is refused, then accepted when the person insists")
    func unusualValuesNeedAnExplicitYes() throws {
        let db = try TestDatabase()
        let store = makeStore(db)

        // A typo guard, not a clinical claim: the bound exists to catch 540 and
        // 5, and "save anyway" exists so a real reading is never blocked by a
        // number this repository made up.
        #expect(throws: VitalsEntryError.unusuallySized) {
            try store.recordManual(metric: .restingHeartRate, value: 640, measuredAt: instantAt0900())
        }
        #expect(throws: VitalsEntryError.unusuallySized) {
            try store.recordManual(metric: .heartRateVariability, value: 0.4, measuredAt: instantAt0900())
        }

        let id = try store.recordManual(metric: .restingHeartRate, value: 640,
                                        measuredAt: instantAt0900(), allowUnusualValue: true)
        #expect(try #require(try store.record(id: id)).value == 640)

        // "Save anyway" waives the range. It does not waive being a number:
        // NaN compares false against everything, so an unguarded range check
        // would have stored a value no score can interpret.
        #expect(throws: VitalsEntryError.invalidValue(.restingHeartRate)) {
            try store.recordManual(metric: .restingHeartRate, value: .nan,
                                   measuredAt: instantAt0900(), allowUnusualValue: true)
        }
    }

    // MARK: - Correcting

    @Test("A correction moves the value and nothing else")
    func correctionKeepsInstantMetricAndUnit() throws {
        let db = try TestDatabase()
        let store = makeStore(db)
        let id = try store.recordManual(metric: .restingHeartRate, value: 52,
                                        measuredAt: instantAt0330())
        let before = try #require(try store.record(id: id))

        try store.update(id: id, value: 56)

        let after = try #require(try store.record(id: id))
        #expect(after.value == 56)
        #expect(after.metric == before.metric)
        #expect(after.unit == before.unit)
        #expect(after.logicalDay == before.logicalDay,
                "a correction may not move a reading into another day, and out of the score it was part of")
        #expect(abs(after.timestamp.timeIntervalSince(before.timestamp)) < 1)
    }

    @Test("A correction is validated exactly as a new entry is")
    func correctionIsValidated() throws {
        let db = try TestDatabase()
        let store = makeStore(db)
        let id = try store.recordManual(metric: .restingHeartRate, value: 52, measuredAt: instantAt0900())

        #expect(throws: VitalsEntryError.invalidValue(.restingHeartRate)) {
            try store.update(id: id, value: 0)
        }
        #expect(throws: VitalsEntryError.unusuallySized) {
            try store.update(id: id, value: 400)
        }
        try store.update(id: id, value: 400, allowUnusualValue: true)
        #expect(try #require(try store.record(id: id)).value == 400)
    }

    @Test("Apple Health owns its own rows")
    func syncedRowsRefuseCorrectionAndDeletion() throws {
        let db = try TestDatabase()
        let bridge = VitalsRecordHealthBridge(db: db, timeModel: TimeModel(timeZone: zone, boundary: .almanac))
        let when = instantAt0900()
        try bridge.apply(
            HealthChangeSet(
                added: [HealthSample(externalID: "hk-rhr-1", domain: .heartRate,
                                     start: when, end: when, value: 52, unit: nil)],
                deletedExternalIDs: [], nextAnchor: nil
            ),
            in: db
        )
        let store = makeStore(db)
        let synced = try #require(try store.records(metric: "rhr", from: "2026-10-03", to: "2026-10-04").first)

        #expect(throws: VitalsEntryError.notManual) { try store.update(id: synced.id, value: 40) }
        #expect(throws: VitalsEntryError.notManual) { try store.delete(id: synced.id) }
        #expect(try #require(try store.record(id: synced.id)).value == 52, "the refusal wrote nothing")

        // And a hand-entered row sits alongside it, editable, without displacing
        // it — the two are different measurements, not two copies of one.
        let manualId = try store.recordManual(metric: .restingHeartRate, value: 60, measuredAt: when)
        try store.update(id: manualId, value: 58)
        #expect(try store.records(for: "2026-10-03").count == 2)
    }

    @Test("Correcting or deleting nothing says so rather than blaming Apple Health")
    func missingRowIsItsOwnError() throws {
        let db = try TestDatabase()
        let store = makeStore(db)

        #expect(throws: VitalsEntryError.notFound) { try store.update(id: 4_242, value: 50) }
        #expect(throws: VitalsEntryError.notFound) { try store.delete(id: 4_242) }
    }

    @Test("Deleting a hand-entered reading removes it")
    func deleteRemovesManualRows() throws {
        let db = try TestDatabase()
        let store = makeStore(db)
        let id = try store.recordManual(metric: .heartRateVariability, value: 44, measuredAt: instantAt0900())

        try store.delete(id: id)

        #expect(try store.record(id: id) == nil)
        #expect(try store.records(for: "2026-10-03").isEmpty)
        // Deleting twice is not a way to delete somebody else's row later.
        #expect(throws: VitalsEntryError.notFound) { try store.delete(id: id) }
    }

    @Test("A hand-entered row of a metric with no editor cannot be corrected through this one")
    func refusesUntypedManualMetrics() throws {
        let db = try TestDatabase()
        // A `steps` row written as a draft before `VitalsMetric` existed. The
        // vocabulary is deliberately smaller than the table, and the gap has to
        // fail loudly rather than be validated as if it were an HRV reading —
        // `steps` has no plausible range to validate against, and borrowing
        // HRV's would reject a perfectly ordinary step count.
        let draft = VitalsRecordDraft(metric: "steps", value: 8_400, unit: "count",
                                      timestamp: instantAt0900(), source: VitalsRecordStore.manualSource)
        let store = makeStore(db)
        let id = try store.record(draft, logicalDay: "2026-10-03")

        #expect(throws: VitalsEntryError.notHandEnterable) { try store.update(id: id, value: 9_000) }

        // Removal is the other way round: it validates nothing, so there is no
        // range to borrow and nothing to mis-assert. A hand-entered row is
        // still the person's own row to remove.
        try store.delete(id: id)
        #expect(try store.record(id: id) == nil)
    }

    // MARK: - Today's reading is today's reading

    @Test("A reading from yesterday is not today's input")
    func boundedLatestValueIgnoresOlderReadings() throws {
        let db = try TestDatabase()
        let store = makeStore(db)

        // The situation manual entry creates: last night's resting HR typed in
        // this morning, so the row is yesterday's but it is the newest row in
        // the table.
        try store.recordManual(metric: .restingHeartRate, value: 58, measuredAt: instantAt0330())
        try store.recordManual(metric: .restingHeartRate, value: 52, measuredAt: instantAt0900())

        #expect(try store.latestValue(for: .restingHeartRate, since: todayStart)?.value == 52)
        #expect(try store.latestValue(for: .restingHeartRate, since: yesterdayStart)?.value == 52)

        // With only yesterday's reading, today's is absent rather than borrowed.
        let db2 = try TestDatabase()
        let store2 = makeStore(db2)
        try store2.recordManual(metric: .restingHeartRate, value: 58, measuredAt: instantAt0330())
        #expect(try store2.latestValue(for: .restingHeartRate, since: todayStart) == nil)
        #expect(try store2.latestValue(for: .restingHeartRate, since: yesterdayStart)?.value == 58)

        // The window is inclusive of its own instant, so a reading taken exactly
        // at the start of the day is today's.
        #expect(try store2.latestValue(for: .restingHeartRate, since: instantAt0330())?.value == 58)
    }

    @Test("A deleted HealthKit reading is not resurrected as an input")
    func boundedLatestValueSkipsRetractedRows() throws {
        let db = try TestDatabase()
        let bridge = VitalsRecordHealthBridge(db: db, timeModel: TimeModel(timeZone: zone, boundary: .almanac))
        let when = instantAt0900()
        try bridge.apply(
            HealthChangeSet(
                added: [HealthSample(externalID: "hk-rhr-1", domain: .heartRate,
                                     start: when, end: when, value: 52, unit: nil)],
                deletedExternalIDs: [], nextAnchor: nil
            ),
            in: db
        )
        try bridge.apply(
            HealthChangeSet(added: [], deletedExternalIDs: ["hk-rhr-1"], nextAnchor: nil),
            in: db
        )
        let store = makeStore(db)

        #expect(try store.latestValue(for: .restingHeartRate, since: instantAt0900()) == nil)
    }

    @Test("A day's hand-entered readings are readable as the editor shows them")
    func manualRecordsArePerMetricAndPerDay() throws {
        let db = try TestDatabase()
        let store = makeStore(db)
        try store.recordManual(metric: .restingHeartRate, value: 52, measuredAt: instantAt0330())
        try store.recordManual(metric: .restingHeartRate, value: 51, measuredAt: instantAt0900())
        try store.recordManual(metric: .heartRateVariability, value: 44, measuredAt: instantAt0900())

        // Newest first, and each day holds only its own readings — the 03:30 one
        // is the 2nd's, so the 3rd has exactly one despite two rows existing.
        #expect(try store.manualRecords(metric: .restingHeartRate, for: "2026-10-03")
            .map(\.value) == [51])
        #expect(try store.manualRecords(metric: .restingHeartRate, for: "2026-10-02")
            .map(\.value) == [52])
        #expect(try store.manualRecords(metric: .heartRateVariability, for: "2026-10-02").isEmpty)
        #expect(try store.manualRecords(metric: .heartRateVariability, for: "2026-10-03")
            .map(\.value) == [44])
    }
}

/// The wake-time marker is not a night of zero minutes.
///
/// `SleepEpisodeStore.upsertManualWake` writes `durationMinutes = 0`, which used
/// to be indistinguishable from a measured night of zero length — and zero is a
/// scorable reading of the worst band, so a person who recorded only *when* they
/// woke up was prescribed against as though they had not slept at all.
@Suite("Manual Wake Marker Is Not Zero Sleep")
struct ManualWakeMarkerTests {
    private let db = try! TestDatabase()
    private var store: SleepEpisodeStore { SleepEpisodeStore(db: db) }

    @Test("A measured night keeps its duration")
    func measuredNightIsUnchanged() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let id = try store.upsert(
            SleepEpisode(start: start, end: start.addingTimeInterval(8 * 3600), type: .primary,
                         source: .healthkit, asleepMinutes: 480, sourceApp: "com.apple.health",
                         healthKitUUIDs: ["hk-night"]),
            timezoneOffset: 0, logicalDay: "2026-10-02"
        )
        let stored = try #require(try store.episode(id: id))
        #expect(stored.durationMinutes == 480)
        #expect(stored.measuredDurationMinutes == 480)
    }

    @Test("A wake marker reads as no measurement, not as no sleep")
    func wakeMarkerIsNotZeroMinutes() throws {
        let wake = Date(timeIntervalSince1970: 1_000_000)
        let id = try store.upsertManualWake(wakeTime: wake, logicalDay: "2026-10-02")
        let marker = try #require(try store.episode(id: id))

        #expect(marker.durationMinutes == 0, "the stored value is unchanged for anyone reading the raw column")
        #expect(marker.measuredDurationMinutes == nil)
    }

    @Test("A wake marker cannot be scored as the worst night")
    func wakeMarkerDoesNotScoreAsZeroSleep() throws {
        let wake = Date(timeIntervalSince1970: 1_000_000)
        let id = try store.upsertManualWake(wakeTime: wake, logicalDay: "2026-10-02")
        let marker = try #require(try store.episode(id: id))

        let baseline = ReadinessBaseline(restingHeartRate: 55, hrv: 50)
        let withoutMeasurement = ReadinessEngine.evaluate(
            state: .provisional,
            inputs: ReadinessInputs(restingHeartRate: 55, hrv: 50),
            baseline: baseline
        )
        let fromMarker = ReadinessEngine.evaluate(
            state: .provisional,
            inputs: ReadinessInputs(sleepDurationMinutes: marker.measuredDurationMinutes,
                                    restingHeartRate: 55, hrv: 50),
            baseline: baseline
        )

        #expect(withoutMeasurement.missingInputs.contains(.sleep),
                "§9.2 imputes the neutral 50 and flags the gap for a duration nobody measured")
        #expect(fromMarker.score == withoutMeasurement.score)
        #expect(fromMarker.missingInputs == withoutMeasurement.missingInputs)
        #expect(ReadinessFormula.sleepDurationScore(minutes: marker.durationMinutes) == 10,
                "the defect this guards: the raw value would have scored as the worst night")
    }
}
