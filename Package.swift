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
        .target(name: "AlmanacCore", dependencies: ["CSQLite"], path: "Sources/AlmanacCore"),
        .testTarget(name: "AlmanacCoreTests", dependencies: ["AlmanacCore"], path: "Tests/AlmanacCoreTests")
    ]
)
