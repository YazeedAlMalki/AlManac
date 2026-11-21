// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlmanacCore",
    // Interface text AlmanacCore writes is English-keyed with an Arabic table
    // (`Sources/AlmanacCore/Localization`, #4).
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AlmanacCore", targets: ["AlmanacCore"])
    ],
    targets: [
        // Vendored SQLite amalgamation (public domain).
        // Vendored rather than system-linked so the Linux core and the iOS app
        // compile against a byte-identical SQLite. Swap for a systemLibrary
        // target if you decide the iOS app should link the OS copy instead.
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            sources: ["sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                // FTS5 is not enabled: nothing in the app or its bundled
                // databases uses it, and every module compiled in is attack
                // surface for a database file the app did not write (a
                // restored backup). The restore also refuses any schema the
                // migrations do not define. (Audit findings S-01, S-05.)
                .define("SQLITE_ENABLE_JSON1"),
                .define("SQLITE_DQS", to: "0"),
                .define("SQLITE_DEFAULT_FOREIGN_KEYS", to: "1"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_OMIT_DEPRECATED"),
                // No runtime extension loading: the app never uses it, and the
                // amalgamation only omits it by default on VxWorks. (S-04.)
                .define("SQLITE_OMIT_LOAD_EXTENSION")
            ]
        ),
        // Vendored batoulapps/adhan-swift (MIT) — prayer-time astronomical
        // calculations. Vendored as source rather than an SPM dependency,
        // same reasoning as CSQLite above. See Sources/Adhan/VENDORED.md for
        // the exact commit and files.
        .target(
            name: "Adhan",
            path: "Sources/Adhan",
            exclude: ["LICENSE", "VENDORED.md"]
        ),
        .target(name: "AlmanacCore", dependencies: ["CSQLite", "Adhan"], path: "Sources/AlmanacCore",
                resources: [.copy("Nutrition/Resources/almanac.sqlite"),
                            .copy("Prayer/Resources/manual-cities.json"),
                            .copy("Training/Resources/workout-guide"),
                            .copy("Training/Resources/free-exercise-db"),
                            .copy("Training/Resources/exercise-library.json"),
                            .copy("Kitchen/Resources/wikibooks-recipes.json"),
                            .copy("Nutrition/Resources/open-food-facts.sqlite"),
                            .copy("Nutrition/Resources/food-merges.json"),
                            .process("Localization/Resources")]),
        .testTarget(name: "AlmanacCoreTests", dependencies: ["AlmanacCore"], path: "Tests/AlmanacCoreTests")
    ]
)
