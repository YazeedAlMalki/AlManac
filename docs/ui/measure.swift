// Measure a captured screenshot against Almanac's design tokens.
//
// Answers three questions that are otherwise answered by looking, and looking
// is unreliable at exactly the sizes that matter:
//
//   1. What text is on screen, at what point size, in what colour?
//   2. Is every colour on screen a colour the design system defines?
//   3. Where are the structural rules, and are they the divider token?
//
// The third question is why this exists as a program. A hairline divider and a
// card's fill both span most of the screen's width, so width alone cannot tell
// them apart -- an earlier version of this detector reported the canvas. What
// separates them is height: a 1pt rule is 3 device pixels, a panel is 40.
//
// Usage: measure <image.png> [--scale 3] [--type-size medium]
//
// Compiled by measure.sh; run it via that script rather than directly.

import Foundation
import Vision
import AppKit

// MARK: - Tokens

/// `AlmanacPalette` in both appearances. Copied rather than imported: `Native/`
/// is an app target and cannot be linked from a tool, and a stale copy here
/// fails loudly — the off-token check will name a colour the app no longer
/// uses, which is a question worth asking, not a bug to hide.
///
/// Both halves matter. A light-only table does not merely miss dark colours, it
/// reports them as defects: on a dark-appearance capture it called 65% of the
/// screen off-token, every one of them a correct `AlmanacPalette` value.
let lightTokens: [(name: String, hex: UInt32)] = [
    ("canvas", 0xFCFCFA), ("surface", 0xF1F1ED), ("surfaceMuted", 0xE6E6E1),
    ("divider", 0xDCDCD6), ("textPrimary", 0x1A1A18), ("textSecondary", 0x63635E),
    ("accent", 0x1F4E8C), ("onAccent", 0xFFFFFF), ("good", 0x1E7A4C),
    ("warning", 0x8A5A00), ("critical", 0xB3261E),
]
let darkTokens: [(name: String, hex: UInt32)] = [
    ("canvas", 0x0B0B0C), ("surface", 0x15161A), ("surfaceMuted", 0x1E2024),
    ("divider", 0x2A2C30), ("textPrimary", 0xECECEA), ("textSecondary", 0x9A9C9F),
    ("accent", 0x6FA0D8), ("onAccent", 0x0B0B0C), ("good", 0x63D394),
    ("warning", 0xF2B84B), ("critical", 0xFF7A70),
]
var tokens = lightTokens

func rgb(_ hex: UInt32) -> (Int, Int, Int) {
    (Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF))
}

/// Screenshot colour space is not guaranteed to match the token's, so the
/// comparison is a tolerance rather than an equality. 6/255 absorbs the
/// rounding in a P3 display's sRGB encode without admitting a visible step.
func nearestToken(_ r: Int, _ g: Int, _ b: Int) -> String? {
    var best: (name: String, distance: Int)?
    for t in tokens {
        let (tr, tg, tb) = rgb(t.hex)
        let d = max(abs(r - tr), max(abs(g - tg), abs(b - tb)))
        if d <= 6, best == nil || d < best!.distance { best = (t.name, d) }
    }
    return best?.name
}

// MARK: - Arguments

var path: String?
var scale = 3.0
var typeSize = "medium"
var appearance = "light"
let argv = Array(CommandLine.arguments.dropFirst())
var i = 0
/// The value following a flag, or the fallback if the flag was given last.
func value(_ fallback: String) -> String { i + 1 < argv.count ? argv[i + 1] : fallback }
while i < argv.count {
    switch argv[i] {
    case "--scale": scale = Double(value("3")) ?? 3; i += 2
    case "--type-size": typeSize = value("medium"); i += 2
    case "--appearance": appearance = value("light"); i += 2
    default: if path == nil { path = argv[i] }; i += 1
    }
}
tokens = appearance == "dark" ? darkTokens : lightTokens

guard let path,
      let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: measure <image.png> [--scale 3] [--appearance light|dark]\n".data(using: .utf8)!)
    exit(1)
}

let W = cg.width, H = cg.height
func note(_ s: String) { print(s) }
note("== \(path) == \(W)x\(H)px, scale \(scale)x, \(appearance) appearance")
note(String(format: "   frame %.0f x %.0f pt", Double(W) / scale, Double(H) / scale))

// MARK: - Pixels

let bpr = cg.bytesPerRow
var buf = [UInt8](repeating: 0, count: bpr * cg.height)
guard let ctx = CGContext(data: &buf, width: cg.width, height: cg.height,
                          bitsPerComponent: 8, bytesPerRow: bpr,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("cannot rasterize\n".data(using: .utf8)!); exit(1)
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))

@inline(__always) func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let o = y * bpr + x * 4
    return (Int(buf[o]), Int(buf[o + 1]), Int(buf[o + 2]))
}

// MARK: - 1. Text

/// The colour of the ink in a text run, or "off-token".
///
/// Sampling the centre of the box returns background, because a glyph is mostly
/// holes: the middle of a large letter is the page showing through. So the box
/// is sampled on a grid and the pixel furthest from the box's own background is
/// taken as the ink. Distance rather than darkness, so the same code reads dark
/// text on a light page and light text on a dark one.
func glyphToken(x0: Int, y0: Int, w: Int, h: Int) -> String {
    // The status bar is drawn by iOS, not by Almanac. Judging its clock against
    // Almanac's palette would report a defect in code that is not in this repo.
    if Double(y0) < 60 * scale { return "system chrome" }
    var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
    var ink = (d: -1, r: 0, g: 0, b: 0)
    for y in stride(from: y0, to: min(H, y0 + h), by: 2) {
        for x in stride(from: x0, to: min(W, x0 + w), by: 2) {
            let (r, g, b) = px(x, y)
            let k = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            var e = counts[k] ?? (0, 0, 0, 0); e.n += 1; e.r += r; e.g += g; e.b += b
            counts[k] = e
        }
    }
    guard let bg = counts.max(by: { $0.value.n < $1.value.n }) else { return "off-token" }
    let (br, bgc, bb) = (bg.value.r / bg.value.n, bg.value.g / bg.value.n, bg.value.b / bg.value.n)
    for x in stride(from: x0, to: min(W, x0 + w), by: 2) {
        for y in stride(from: y0, to: min(H, y0 + h), by: 2) {
            let (r, g, b) = px(x, y)
            let d = abs(r - br) + abs(g - bgc) + abs(b - bb)
            if d > ink.d { ink = (d, r, g, b) }
        }
    }
    return nearestToken(ink.r, ink.g, ink.b) ?? "off-token"
}

var runs: [(String, Int, Int, Int, Int, Float)] = []
let ocr = VNRecognizeTextRequest { req, _ in
    guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
    for o in obs {
        guard let c = o.topCandidates(1).first else { continue }
        let b = o.boundingBox
        runs.append((c.string, Int(b.origin.x * Double(W)),
                     Int((1 - b.origin.y - b.height) * Double(H)),
                     Int(b.width * Double(W)), Int(b.height * Double(H)), c.confidence))
    }
}
ocr.recognitionLevel = .accurate
ocr.usesLanguageCorrection = false
do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([ocr]) }
catch { FileHandle.standardError.write("Vision: \(error)\n".data(using: .utf8)!); exit(1) }

note("")
note("== TEXT (\(runs.count) runs, box height / point size) ==")
// Vision's box is the full line box, ascender to descender, which is taller
// than the point size by a font-dependent factor. Calibrating on the largest
// run — the screen title — is the only anchor available without the font, so
// the ratio is stated and every size is relative to it. Treat the absolute
// point values as approximate and the *ratios* between runs as exact, which is
// what a type-scale check actually needs.
let capRatio = 1.18  // .largeTitle 34pt measured against a typical SF line box
for r in runs.sorted(by: { $0.1 < $1.1 }) {
    let pts = Double(r.4) / scale / capRatio
    let tok = glyphToken(x0: r.1, y0: r.2, w: r.3, h: r.4)
    note(String(format: "  x=%4d y=%4d w=%4d  %5.1fpt  %-14@  c=%.2f  %@",
                r.1, r.2, r.3, pts, tok as NSString, r.5, r.0 as NSString))
}
if let lg = runs.max(by: { $0.4 < $1.4 }) {
    note(String(format: "  (largest run %.0fpx = %.1fpt; every size above is calibrated to it)",
                Double(lg.4), Double(lg.4) / scale / capRatio))
}

// MARK: - 2. Palette

note("")
note("== PALETTE ==")
var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
for y in stride(from: 0, to: H, by: 2) {
    for x in stride(from: 0, to: W, by: 2) {
        let (r, g, b) = px(x, y)
        let k = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
        var e = bins[k] ?? (0, 0, 0, 0)
        e.count += 1; e.r += r; e.g += g; e.b += b
        bins[k] = e
    }
}
let total = Double(bins.values.reduce(0) { $0 + $1.count })
var offToken = 0.0
for (_, e) in bins.sorted(by: { $0.value.count > $1.value.count }).prefix(12) {
    let (r, g, b) = (e.r / e.count, e.g / e.count, e.b / e.count)
    let pct = 100 * Double(e.count) / total
    if let t = nearestToken(r, g, b) {
        note(String(format: "  %6.2f%%  #%02X%02X%02X  %@", pct, r, g, b, t as NSString))
    } else if pct > 0.2 {
        offToken += pct
        note(String(format: "  %6.2f%%  #%02X%02X%02X  ** no token **", pct, r, g, b))
    }
}
note(offToken == 0
     ? "  every colour above 0.2% is a design-system token"
     : String(format: "  %.2f%% of the screen is not a design-system colour", offToken))

// MARK: - 3. Rules and panel edges
//
// Group consecutive rows that share a dominant colour. A 1pt rule is three
// device pixels and owns its rows outright, so it shows up as a short band
// whose colour is `divider`; a panel is a tall band of `surface`. Height, not
// width, is what separates them — an earlier version of this detector keyed on
// the longest run per row and reported the canvas every time.

note("")
note("== STRUCTURAL BANDS (a rule is ~1pt tall; taller is a panel) ==")
struct Band { var y0: Int; var y1: Int; var r: Int; var g: Int; var b: Int; var cover: Double }
var bands: [Band] = []

for y in 0..<H {
    var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
    var sampled = 0
    for x in stride(from: 0, to: W, by: 2) {
        let (r, g, b) = px(x, y)
        let k = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
        var e = counts[k] ?? (0, 0, 0, 0); e.n += 1; e.r += r; e.g += g; e.b += b
        counts[k] = e; sampled += 1
    }
    guard let top = counts.max(by: { $0.value.n < $1.value.n }), sampled > 0 else { continue }
    let r = top.value.r / top.value.n, g = top.value.g / top.value.n, b = top.value.b / top.value.n
    let cover = Double(top.value.n) / Double(sampled)

    // A row of text is background with a few glyphs on it, so it is grouped
    // with the background rather than becoming a band of its own.
    if cover < 0.55 { continue }

    if var last = bands.last, last.y1 == y, abs(last.r - r) <= 8, abs(last.g - g) <= 8, abs(last.b - b) <= 8 {
        last.y1 = y + 1; last.cover = max(last.cover, cover)
        bands[bands.count - 1] = last
    } else {
        bands.append(Band(y0: y, y1: y + 1, r: r, g: g, b: b, cover: cover))
    }
}

let ptPx = scale
var rules = 0, panels = 0
var ruleHeights: [Int] = []
for b in bands {
    let h = b.y1 - b.y0
    let token = nearestToken(b.r, b.g, b.b) ?? "** no token **"
    // A 1pt rule at 3x is 3px. Allow 1.5pt before calling something a panel,
    // because a hairline can round to 4px and still be a hairline.
    let isRule = h <= Int(1.5 * ptPx) && token == "divider"
    let isPanel = h > Int(4 * ptPx)
    let kind = isRule ? "rule" : (isPanel ? "panel" : "edge")
    if isRule { rules += 1; ruleHeights.append(h) }
    if isPanel { panels += 1 }
    note(String(format: "  %-5s y=%4d..%-4d  h=%3dpx (%.2fpt)  #%02X%02X%02X  %@",
                (kind as NSString).utf8String!, b.y0, b.y1, h, Double(h) / ptPx,
                b.r, b.g, b.b, token as NSString))
}
note("  \(rules) rule(s), \(panels) panel(s)")

// MARK: - Verdict

note("")
var problems: [String] = []
if offToken > 0 { problems.append(String(format: "%.1f%% of the screen is not a design-system colour", offToken)) }
for b in bands {
    let h = b.y1 - b.y0
    let token = nearestToken(b.r, b.g, b.b)
    if h <= Int(1.5 * ptPx), h > 1, token != "divider" {
        problems.append(String(format: "a %dpx hairline at y=%d is %@, not divider",
                              h, b.y0, token ?? "a colour with no token"))
    }
}
if rules == 0 {
    problems.append("no divider rule found — the design system makes rules the structural device, so a sectioned screen should show at least one")
}
// Rules are one weight. A screen drawing them at two weights is a visible
// inconsistency, and it is exactly the sort of thing that is obvious in a
// screenshot and invisible in a code review.
let weights = Set(ruleHeights)
if weights.count > 1 {
    problems.append("rules are drawn at \(weights.sorted().map { String(format: "%.2fpt", Double($0) / ptPx) }.joined(separator: ", ")) — they should be one weight")
}
for p in problems { note("  FINDING: \(p)") }
if problems.isEmpty { note("  no findings") }
