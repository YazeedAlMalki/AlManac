import Testing
import Foundation

/// A day key is a `yyyy-MM-dd` string that other code looks up by equality,
/// so it must be ASCII whatever the phone's language. A `DateFormatter` left on
/// the device locale writes `٢٠٢٦-١٠-٠٥` under Arabic, and that key matches
/// nothing: suhoor and iftar go missing, the fasting screen's prayer times come
/// up empty, night-shift suppression stops working.
///
/// The suite cannot switch its own locale mid-run, so this checks the source
/// instead: every formatter that writes or reads a day key pins `en_US_POSIX`.
/// To run the behavioural suite under Arabic on a Mac, launch the test bundle
/// with `-AppleLocale ar_SA` (`swift test` does not pass it through, nor `LANG`).
@Suite("Day key locale")
struct DayKeyLocaleTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // AlmanacCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // package root

    @Test("Every yyyy-MM-dd formatter in the app pins en_US_POSIX")
    func everyDayKeyFormatterIsPOSIX() throws {
        var checked = 0
        var unpinned: [String] = []
        for directory in ["Sources", "Native"] {
            let base = Self.root.appendingPathComponent(directory)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() where line.contains("dateFormat = \"yyyy-MM-dd\"") {
                    checked += 1
                    // The formatter's own setup: the few lines either side.
                    let nearby = lines[max(0, index - 6)...min(lines.count - 1, index + 6)]
                    if !nearby.contains(where: { $0.contains("en_US_POSIX") }) {
                        unpinned.append("\(file.path.replacingOccurrences(of: Self.root.path + "/", with: "")):\(index + 1)")
                    }
                }
            }
        }
        #expect(checked > 0, "found no day-key formatters at all; the scan is looking in the wrong place")
        #expect(unpinned.isEmpty, "day-key formatters on the device locale: \(unpinned)")
    }
}
