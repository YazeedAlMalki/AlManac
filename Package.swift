// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlmanacCore",
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
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_ENABLE_JSON1"),
                .define("SQLITE_DQS", to: "0"),
                .define("SQLITE_DEFAULT_FOREIGN_KEYS", to: "1"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_OMIT_DEPRECATED")
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
                            .copy("Training/Resources/workout-guide")]),
        .testTarget(name: "AlmanacCoreTests", dependencies: ["AlmanacCore"], path: "Tests/AlmanacCoreTests")
    ]
)
