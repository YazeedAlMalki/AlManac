import Foundation

/// Locates an exercise's demonstration graphic inside AlmanacCore's resource
/// bundle. The PNGs are copied, not processed, so the path is stable.
public enum ExerciseGraphics {
    public static let directory = "workout-guide"

    public static func url(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: directory)
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
