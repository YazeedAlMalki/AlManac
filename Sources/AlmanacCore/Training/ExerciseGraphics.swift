import Foundation

/// Locates an exercise's demonstration graphic inside AlmanacCore's resource
/// bundle. The files are copied, not processed, so the path is stable. A bare
/// file name is workout-guide's (its rows were stored before there was a
/// second source); any other source's path names its folder
/// (`free-exercise-db/Air_Bike.jpg`).
public enum ExerciseGraphics {
    public static let directory = "workout-guide"

    public static func url(named name: String) -> URL? {
        let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
        let (folder, file) = parts.count == 2 ? (parts[0], parts[1]) : (directory, name)
        return Bundle.module.url(forResource: file, withExtension: nil, subdirectory: folder)
    }

    public static func data(named name: String) -> Data? {
        guard let url = url(named: name) else { return nil }
        return try? Data(contentsOf: url)
    }
}

public struct MissingExerciseGraphic: Error, CustomStringConvertible, Sendable {
    public let exerciseId: String
    public let graphicPath: String?
    public init(exerciseId: String, graphicPath: String?) {
        self.exerciseId = exerciseId
        self.graphicPath = graphicPath
    }
    public var description: String {
        if let graphicPath {
            return "BUILD FAILURE: exercise '\(exerciseId)' names graphic '\(graphicPath)', which is not in the bundle."
        }
        return "BUILD FAILURE: exercise '\(exerciseId)' would ship without a demonstration graphic."
    }
}

/// The "graphic per exercise" rule as a build failure rather than a content
/// gap discovered after release: every row given to it must name a graphic
/// that is actually bundled. Mirrors `AttributionAudit` / `BundleGuard`.
public enum ExerciseGraphicAudit {
    public static func assertEveryExerciseHasGraphic<S: Sequence>(_ entries: S) throws
    where S.Element == ExerciseCatalogEntry {
        for entry in entries {
            guard let path = entry.graphicPath, ExerciseGraphics.url(named: path) != nil else {
                throw MissingExerciseGraphic(exerciseId: entry.exerciseId, graphicPath: entry.graphicPath)
            }
        }
    }
}
