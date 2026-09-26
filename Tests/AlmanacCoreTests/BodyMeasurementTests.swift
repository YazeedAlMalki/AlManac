import Foundation
import Testing
@testable import AlmanacCore

@Suite("Body measurements")
struct BodyMeasurementTests {
    let db = try! TestDatabase()
    let time = TimeModel.riyadh()
    let date = ISO8601DateFormatter().date(from: "2026-09-25T00:30:00Z")! // 03:30 Riyadh
    var store: BodyMeasurementStore { BodyMeasurementStore(db: db, timeModel: time) }

    @Test("Migration upgrades an existing profile without replacing it and is idempotent")
    func migrationUpgrade() throws {
        let existing = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all.filter { $0.version < 41 }).migrate(existing)
        try existing.run("INSERT INTO profile (id, displayName, createdAt, updatedAt) VALUES (1, 'Existing user', 'before', 'before');")
        let runner = try MigrationRunner(migrations: AlmanacMigrations.all)
        // Written as a literal rather than derived from `AlmanacMigrations.all`:
        // a derived `.map(...).filter(...)` expression inside this `#expect`
        // crashes swift-frontend during AST lowering. The literal also states
        // the point of the test more plainly — these are the migrations a
        // profile predating 041 has to be upgraded through, and adding a
        // migration should make a human edit this line on purpose.
        #expect(try runner.migrate(existing) == [41, 42, 43])
        #expect(try runner.migrate(existing).isEmpty)
        let profile = try ProfileStore(db: existing).profile()
        #expect(profile.displayName == "Existing user")
        #expect(profile.bodyMeasurementTrackSides == false)
        #expect(profile.createdAt == "before")
    }

    @Test("Toggle off uses unsided rows; on requires a side for arms and thighs only")
    func sideToggle() throws {
        let profile = ProfileStore(db: db)
        #expect(try profile.profile().bodyMeasurementTrackSides == false)
        for type in BodyMeasurementType.allCases {
            let value = type.plausibleRange.lowerBound
            let id = try store.log(.init(measuredAt: date, measurementType: type, valueCm: value))
            #expect(try store.entry(id: id)?.side == nil)
            #expect(throws: BodyMeasurementError.invalidSide) {
                try store.log(.init(measuredAt: date, measurementType: type, side: .left, valueCm: value))
            }
        }
        try profile.updateBodyMeasurementTrackSides(true)
        for type in BodyMeasurementType.allCases {
            let value = type.plausibleRange.lowerBound
            if type.supportsSides {
                #expect(throws: BodyMeasurementError.invalidSide) {
                    try store.log(.init(measuredAt: date, measurementType: type, valueCm: value))
                }
                for side in BodyMeasurementSide.allCases {
                    let id = try store.log(.init(measuredAt: date, measurementType: type, side: side, valueCm: value))
                    #expect(try store.entry(id: id)?.side == side)
                }
            } else {
                #expect(throws: BodyMeasurementError.invalidSide) {
                    try store.log(.init(measuredAt: date, measurementType: type, side: .right, valueCm: value))
                }
                _ = try store.log(.init(measuredAt: date, measurementType: type, valueCm: value))
            }
        }
        let before = try store.recentEntries()
        try profile.updateBodyMeasurementTrackSides(false)
        #expect(try store.recentEntries() == before) // OI-1 reversible stub: no rewrite.
        let unsided = try store.log(.init(measuredAt: date, measurementType: .arm, valueCm: 30))
        #expect(try store.entry(id: unsided)?.side == nil)
    }

    @Test("TimeModel assigns both sides of 04:00, preserves repeats and supports range queries")
    func logicalDaysAndRepeats() throws {
        let first = try store.log(.init(measuredAt: date, measurementType: .waist, valueCm: 85))
        let second = try store.log(.init(measuredAt: date, measurementType: .waist, valueCm: 86))
        let boundary = date.addingTimeInterval(30 * 60)
        let third = try store.log(.init(measuredAt: boundary, measurementType: .waist, valueCm: 87))
        #expect(try store.entries(for: "2026-09-24").map(\.id) == [first, second])
        #expect(try store.entries(for: "2026-09-25").map(\.id) == [third])
        #expect(try store.entries(from: date, to: boundary).map(\.id) == [first, second])
    }

    @Test("Manual corrections preserve identity; unusual values need confirmation, invalid numbers cannot be saved")
    func correctionsAndValidation() throws {
        let draft = BodyMeasurementDraft(measuredAt: date, measurementType: .neck, valueCm: 80)
        #expect(throws: BodyMeasurementError.unusuallySized) { try store.log(draft) }
        let id = try store.log(draft, allowUnusualValue: true)
        try store.edit(id: id, valueCm: 40, note: "corrected")
        let edited = try #require(try store.entry(id: id))
        #expect(edited.isEdited && edited.valueCm == 40 && edited.note == "corrected")
        #expect(edited.measuredAt == date)
        for value in [Double.nan, .infinity, 0, -10] {
            #expect(throws: BodyMeasurementError.invalidValue) {
                try store.log(.init(measuredAt: date, measurementType: .waist, valueCm: value), allowUnusualValue: true)
            }
        }
        try store.delete(id: id)
        #expect(try store.entry(id: id) == nil)
    }

    private func waist(_ id: String, value: Double = 85, at: Date? = nil) -> HealthSample {
        HealthSample(externalID: id, domain: .waistCircumference, start: at ?? date, end: at ?? date,
                     value: value, unit: "cm")
    }

    @Test("Waist sync dedups by source_identifier, retains distinct same-day samples and handles deletions")
    func inboundSync() async throws {
        let provider = FakeHealthProvider()
        try await provider.requestAuthorisation(for: [.waistCircumference])
        let sync = HealthSyncService(db: db, provider: provider, writer: BodyMeasurementHealthBridge(timeModel: time),
                                     healthDomain: .waistCircumference)
        let batch = HealthChangeSet(added: [waist("a"), waist("b")], deletedExternalIDs: [], nextAnchor: [1])
        provider.enqueue(batch, for: .waistCircumference)
        provider.enqueue(batch, for: .waistCircumference)
        try await sync.syncOnce()
        try await sync.syncOnce()
        let rows = try store.entries(for: "2026-09-24")
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.source == .healthkit && $0.side == nil && !$0.isEdited })
        #expect(Set(rows.compactMap(\.sourceIdentifier)) == ["a", "b"])
        #expect(try sync.currentAnchor() == [1])
        let id = try #require(rows.first?.id)
        #expect(throws: BodyMeasurementError.notManual) { try store.edit(id: id, valueCm: 90, note: nil) }
        #expect(throws: BodyMeasurementError.notManual) { try store.delete(id: id) }
        provider.enqueue(.init(added: [waist("a", value: 90, at: date.addingTimeInterval(1800))],
                               deletedExternalIDs: ["b"], nextAnchor: [2]), for: .waistCircumference)
        try await sync.syncOnce()
        #expect(try store.entries(for: "2026-09-24").isEmpty)
        #expect(try store.entries(for: "2026-09-25").first?.valueCm == 90)
    }

    @Test("A failed batch rolls back rows and anchor together")
    func syncAtomicity() async throws {
        let provider = FakeHealthProvider()
        try await provider.requestAuthorisation(for: [.waistCircumference])
        let sync = HealthSyncService(db: db, provider: provider, writer: BodyMeasurementHealthBridge(timeModel: time),
                                     healthDomain: .waistCircumference)
        provider.enqueue(.init(added: [waist("good")], deletedExternalIDs: [], nextAnchor: [1]), for: .waistCircumference)
        try await sync.syncOnce()
        provider.enqueue(.init(added: [waist("another"), waist("bad", value: .nan)],
                               deletedExternalIDs: [], nextAnchor: [2]), for: .waistCircumference)
        await #expect(throws: BodyMeasurementError.invalidValue) { try await sync.syncOnce() }
        #expect(try sync.currentAnchor() == [1])
        #expect(try store.recentEntries().count == 1)
    }

    @Test("Only manual waist exports; retries preserve pending rows and echoes never duplicate or overwrite manual data")
    func outboundSync() async throws {
        let id = try store.log(.init(measuredAt: date, measurementType: .waist, valueCm: 85))
        for type in BodyMeasurementType.allCases where type != .waist {
            try store.log(.init(measuredAt: date, measurementType: type, valueCm: type.plausibleRange.lowerBound))
        }
        let bridge = BodyMeasurementHealthBridge(timeModel: time)
        _ = try bridge.apply(.init(added: [waist("inbound")], deletedExternalIDs: [], nextAnchor: nil), in: db)
        let writer = FakeHealthWriter()
        writer.nextID = { "exported" }
        writer.shouldFail = true
        let outbound = BodyMeasurementWriteback(db: db, writer: writer)
        await #expect(throws: FakeHealthWriter.WriteFailure.self) { try await outbound.drainOnce() }
        #expect(try store.entry(id: id)?.sourceIdentifier == nil)
        writer.shouldFail = false
        #expect(try await outbound.drainOnce() == 1)
        #expect(try await outbound.drainOnce() == 0)
        #expect(writer.written.count == 1)
        #expect(writer.written.first?.domain == .waistCircumference)
        #expect(writer.written.first?.unit == "cm")
        try store.edit(id: id, valueCm: 86, note: nil)
        _ = try bridge.apply(.init(added: [waist("exported")], deletedExternalIDs: ["exported"], nextAnchor: nil), in: db)
        let entry = try #require(try store.entry(id: id))
        #expect(entry.source == .manual && entry.sourceIdentifier == "exported" && entry.valueCm == 86)
        #expect(try store.recentEntries().count == 8)
    }
}
