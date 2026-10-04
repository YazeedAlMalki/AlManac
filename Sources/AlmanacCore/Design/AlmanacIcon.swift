import Foundation

/// The app's icon vocabulary — SF Symbol names, named once.
///
/// **This lives in `AlmanacCore` rather than in the view target because the
/// router needs it too.** `AppRoute.icon` is how a cross-tab link labels
/// itself, and a route that could not name its own icon would make every caller
/// repeat the mapping — which is exactly the drift the route enum exists to
/// prevent. The alternative was a second list of the same twenty strings in
/// core, and two lists of one vocabulary is one too many.
///
/// The names are the OS's, not ours: an SF Symbol is a system asset, so this is
/// a naming table rather than a design token. A symbol the OS later renames is a
/// blank icon, not a crash, and the fix is one line here.
public enum AlmanacIcon {
    public static let today = "circle.grid.2x2"
    public static let trends = "chart.xyaxis.line"
    public static let modules = "square.grid.2x2"
    public static let quickAdd = "plus"
    public static let sleep = "bed.double"
    public static let hydration = "drop"
    public static let nutrition = "fork.knife"
    public static let training = "dumbbell"
    public static let body = "ruler"
    public static let supplement = "pills"
    public static let context = "tag"
    public static let digestion = "circle.grid.cross"
    public static let timeline = "list.bullet.rectangle"
    public static let templates = "square.stack.3d.up"
    public static let insights = "point.3.connected.trianglepath.dotted"
    public static let check = "checkmark"
    public static let edit = "pencil"
    public static let previous = "chevron.left"
    public static let next = "chevron.right"
    public static let laboratory = "cross.case"
    public static let profile = "person"
    public static let prayer = "sun.horizon"
    public static let fasting = "moon.stars"
    public static let settings = "gearshape"
    /// Body composition is a card grid, not a ruler — `AlmanacIcon.body` is
    /// circumferences, which is a different screen and has its own route.
    public static let bodyComposition = "figure.stand"
    public static let importHistory = "clock.arrow.circlepath"
    /// Vitals — a heart trace rather than a stethoscope, because the screen is
    /// two numbers read off a measurement, not an examination.
    public static let vitals = "waveform.path.ecg"
}
