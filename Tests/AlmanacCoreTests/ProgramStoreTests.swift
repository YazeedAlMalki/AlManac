import Testing
import Foundation
@testable import AlmanacCore

/// The two thin stores above the pool: `trainingProgram` and `programDay`.
///
/// Thin means the tests here are about the things that are easy to get subtly
/// wrong in a store that looks like it does nothing — soft delete against a
/// point-read, authoring order against alphabetical order, and the decision not
/// to cascade. Nothing here is about training; that lives in the pool store and
/// the two engines.
@Suite("Program and program-day stores")
struct ProgramStoreTests {
    let db = try! TestDatabase()
    private var programs: ProgramStore { ProgramStore(db: db) }
    private var days: ProgramDayStore { ProgramDayStore(db: db) }

    // MARK: - Programs

    @Test("A created program reads back with its name and notes")
    func createAndFetch() throws {
        let id = try programs.create(name: "My PPL", notes: "6 days a week")

        let program = try programs.program(id: id)
        #expect(program?.name == "My PPL")
        #expect(program?.notes == "6 days a week")
        #expect(program?.isDeleted == false)
    }

    @Test("A program with no name is refused rather than stored blank")
    func refusesEmptyName() throws {
        // A program with an empty name cannot be chosen at session start, and a
        // blank row in a picker is worse than a refusal where it was typed.
        #expect(throws: ProgramStoreError.emptyName) {
            _ = try programs.create(name: "")
        }
        #expect(throws: ProgramStoreError.emptyName) {
            _ = try programs.create(name: "   \n ")
        }
        #expect(try programs.programs().isEmpty)
    }

    @Test("A name is trimmed, so a stray space is not part of it")
    func trimsName() throws {
        let id = try programs.create(name: "  My PPL  ")
        #expect(try programs.program(id: id)?.name == "My PPL")
    }

    @Test("Update rewrites the name and notes, and reports whether it hit anything")
    func update() throws {
        let id = try programs.create(name: "Old name")
        #expect(try programs.update(id: id, name: "New name", notes: "notes") == true)

        let program = try programs.program(id: id)
        #expect(program?.name == "New name")
        #expect(program?.notes == "notes")
        // Nothing else exists to update.
        #expect(try programs.update(id: 9999, name: "Nope", notes: nil) == false)
    }

    @Test("Update will not make a program nameless")
    func updateRefusesEmptyName() throws {
        let id = try programs.create(name: "My PPL")
        #expect(throws: ProgramStoreError.emptyName) {
            _ = try programs.update(id: id, name: "  ", notes: nil)
        }
        #expect(try programs.program(id: id)?.name == "My PPL")
    }

    @Test("Deleting a program is soft, and the row is still readable afterwards")
    func softDelete() throws {
        // The asymmetry is the point: a past session can name a program that has
        // since been retired, and the review screen has to be able to say which
        // one that was.
        let id = try programs.create(name: "Retired split")
        #expect(try programs.delete(id: id) == true)

        let deleted = try programs.program(id: id)
        #expect(deleted?.isDeleted == true)
        #expect(deleted?.name == "Retired split")
        #expect(try programs.programs().isEmpty)
    }

    @Test("Deleting twice changes nothing the second time")
    func deleteIsIdempotent() throws {
        let id = try programs.create(name: "My PPL")
        #expect(try programs.delete(id: id) == true)
        #expect(try programs.delete(id: id) == false)
        #expect(try programs.update(id: id, name: "Back again", notes: nil) == false)
    }

    @Test("Deleting a program leaves its days alone")
    func deleteDoesNotCascade() throws {
        // The days carry no independent meaning once the program is gone, but the
        // prescription a past session ran against must survive its retirement —
        // so the program is retired and nothing under it is touched.
        let programId = try programs.create(name: "My PPL")
        let dayId = try days.create(programId: programId, label: "Push")

        _ = try programs.delete(id: programId)

        let day = try days.day(id: dayId)
        #expect(day?.isDeleted == false)
        #expect(day?.label == "Push")
    }

    @Test("Several programs can be in use at once, and none of them is 'the' active one")
    func severalProgramsCoexist() throws {
        // Decision 6. There is deliberately no is-active column, so the assertion
        // that would fail is "one of these is marked active" — and there is no
        // column that could say it.
        _ = try programs.create(name: "My PPL")
        _ = try programs.create(name: "Mobility")
        #expect(try programs.programs().count == 2)

        let columns = try db.query("PRAGMA table_info(trainingProgram);")
            .compactMap { $0.string("name") }
        #expect(!columns.contains("isActive"))
    }

    @Test("Programs are listed by name, ignoring case")
    func programsAreOrderedByName() throws {
        _ = try programs.create(name: "push")
        _ = try programs.create(name: "Mobility")
        _ = try programs.create(name: "Arms")

        #expect(try programs.programs().map(\.name) == ["Arms", "Mobility", "push"])
    }

    // MARK: - Days

    @Test("A created day reads back, with its label trimmed")
    func createDay() throws {
        let programId = try programs.create(name: "My PPL")
        let id = try days.create(programId: programId, label: "  Push  ")

        let day = try days.day(id: id)
        #expect(day?.label == "Push")
        #expect(day?.programId == programId)
        #expect(day?.isDeleted == false)
    }

    @Test("A day with no label is refused")
    func refusesEmptyLabel() throws {
        let programId = try programs.create(name: "My PPL")
        for blank in ["", "   ", "\n\t"] {
            #expect(throws: ProgramDayStoreError.emptyLabel) {
                _ = try days.create(programId: programId, label: blank)
            }
        }
        #expect(try days.days(programId: programId).isEmpty)
    }

    @Test("Days come back in the order they were written, not alphabetically")
    func daysAreInAuthoringOrder() throws {
        // "Legs / Pull / Push" sorted by name is not a training split, it is a
        // coincidence.
        let programId = try programs.create(name: "My PPL")
        for label in ["Push", "Pull", "Legs"] {
            _ = try days.create(programId: programId, label: label)
        }
        #expect(try days.days(programId: programId).map(\.label) == ["Push", "Pull", "Legs"])
    }

    @Test("A program's days never include another program's")
    func daysAreScopedToTheirProgram() throws {
        let ppl = try programs.create(name: "My PPL")
        let mobility = try programs.create(name: "Mobility")
        _ = try days.create(programId: ppl, label: "Push")
        _ = try days.create(programId: mobility, label: "Hips")

        #expect(try days.days(programId: ppl).map(\.label) == ["Push"])
    }

    @Test("Renaming a day works, and a deleted day cannot be renamed")
    func updateDay() throws {
        let programId = try programs.create(name: "My PPL")
        let id = try days.create(programId: programId, label: "Push")

        #expect(try days.update(id: id, label: "Push A") == true)
        #expect(try days.day(id: id)?.label == "Push A")
        #expect(try days.update(id: 9999, label: "Nope") == false)

        _ = try days.delete(id: id)
        #expect(try days.update(id: id, label: "Back") == false)
        #expect(try days.day(id: id)?.label == "Push A")
    }

    @Test("Deleting a day is soft and hides it from the list but not from a read")
    func softDeleteDay() throws {
        let programId = try programs.create(name: "My PPL")
        let id = try days.create(programId: programId, label: "Pull")

        #expect(try days.delete(id: id) == true)
        #expect(try days.day(id: id)?.isDeleted == true)
        #expect(try days.days(programId: programId).isEmpty)
        #expect(try days.delete(id: id) == false)
    }

    // MARK: - The picker read

    @Test("Days come back grouped under their programs, for the session-start picker")
    func daysWithPrograms() throws {
        let ppl = try programs.create(name: "My PPL")
        let mobility = try programs.create(name: "Mobility")
        _ = try days.create(programId: ppl, label: "Push")
        _ = try days.create(programId: ppl, label: "Pull")
        _ = try days.create(programId: mobility, label: "Hips")

        let grouped = try days.daysWithPrograms()
        #expect(grouped.count == 2)
        #expect(grouped[0].program.name == "Mobility")
        #expect(grouped[0].days.map(\.label) == ["Hips"])
        #expect(grouped[1].program.name == "My PPL")
        #expect(grouped[1].days.map(\.label) == ["Push", "Pull"])
    }

    @Test("A program with no live day is left out of the picker rather than shown empty")
    func pickerSkipsEmptyAndDeleted() throws {
        let withDays = try programs.create(name: "My PPL")
        _ = try programs.create(name: "Not started yet")
        _ = try days.create(programId: withDays, label: "Push")

        let gone = try programs.create(name: "Retired")
        let goneDay = try days.create(programId: gone, label: "Old")
        _ = try days.delete(id: goneDay)
        _ = try programs.delete(id: gone)

        let grouped = try days.daysWithPrograms()
        #expect(grouped.map(\.program.name) == ["My PPL"])
    }
}
