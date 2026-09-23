import SwiftUI
import WidgetKit

/// The two home-screen widgets Slice 12 ships: today's water total with a
/// quick +250 ml control, and the fasting session's active/countdown state
/// with start and end controls.
///
/// Both widgets read and write the *same* SQLite database as the app, located
/// in the App Group container (`AppGroupDatabase`). A widget extension cannot
/// reach the app's Application Support sandbox, which is why the database
/// lives in the shared container — not a second, widget-local copy that would
/// drift out of step with what the app shows.
@main
struct AlmanacWidgets: WidgetBundle {
    var body: some Widget {
        WaterWidget()
        FastingWidget()
    }
}