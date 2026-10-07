import Foundation
@testable import AlmanacCore

/// Migration versions taken by work that exists but has not merged into this
/// branch, so this branch numbers its own migrations past them.
///
/// **050 — fasting and prayer (prayer preferences).** On 2026-10-06 that work
/// was uncommitted on the owner's iMac and due to land on master first, with its
/// migration already named 050 in its code, tests and docs, and possibly already
/// applied to a simulator's database. `MigrationRunner` refuses a migration whose
/// stored name differs, so giving 050 to anything else here would break every
/// database that has run the fasting work. Kitchen's pantry therefore took 051,
/// and the list has a hole at 050 until the merge fills it.
///
/// The contiguity tests subtract this set instead of dropping the invariant, and
/// `testNoReservedVersionHasLanded` fails the moment a reserved version appears
/// in `AlmanacMigrations.all`. **When the fasting work merges, empty this set.**
/// **Emptied 2026-10-07:** the fasting work merged, and 050 is
/// `Migration050_PrayerPreferences`, ahead of Kitchen's 051.
let reservedUnmergedMigrationVersions: Set<Int> = []

/// `start...end`, less the reserved versions: what a contiguous list would hold
/// once every reservation has merged.
func contiguousMigrationVersions(_ start: Int, through end: Int) -> [Int] {
    guard start <= end else { return [] }
    return (start...end).filter { !reservedUnmergedMigrationVersions.contains($0) }
}
