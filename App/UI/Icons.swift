// Icon paths copied from RhineDroid web/src/music-app.ts `icons` (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import SwiftUI

/// Minimal SVG path-data parser (M L H V C S A Z, absolute and relative) so upstream icon strings
/// are used verbatim instead of being redrawn by hand.
struct SVGPath: Shape {
    let data: String
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        return Self.parse(data).applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" { flush(); tokens.append(String(ch)) }
            else if ch == "-" && !number.isEmpty && number.last != "e" { flush(); number = "-" }
            else if ch == "." && number.contains(".") { flush(); number = "." }
            else if ch == "," || ch.isWhitespace { flush() }
            else { number.append(ch) }
        }
        flush()
        var i = 0, command: Character = "M"
        var current = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
        func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { command = c; i += 1 }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased().first! {
            case "M":
                current = CGPoint(x: base.x + next(), y: base.y + next()); start = current
                path.move(to: current); command = relative ? "l" : "L"; lastControl = nil
            case "L":
                current = CGPoint(x: base.x + next(), y: base.y + next()); path.addLine(to: current); lastControl = nil
            case "H":
                current.x = (relative ? current.x : 0) + next(); path.addLine(to: current); lastControl = nil
            case "V":
                current.y = (relative ? current.y : 0) + next(); path.addLine(to: current); lastControl = nil
            case "C":
                let c1 = CGPoint(x: base.x + next(), y: base.y + next())
                let c2 = CGPoint(x: base.x + next(), y: base.y + next())
                current = CGPoint(x: base.x + next(), y: base.y + next())
                path.addCurve(to: current, control1: c1, control2: c2); lastControl = c2
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = CGPoint(x: base.x + next(), y: base.y + next())
                current = CGPoint(x: base.x + next(), y: base.y + next())
                path.addCurve(to: current, control1: c1, control2: c2); lastControl = c2
            case "A":
                let rx = next(), ry = next(), rotation = next(), large = next() != 0, sweep = next() != 0
                let end = CGPoint(x: base.x + next(), y: base.y + next())
                arc(&path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end; lastControl = nil
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil
            default:
                i += 1
            }
        }
        return path
    }

    /// SVG endpoint arc → centre parameterisation (SVG 1.1 appendix F.6.5), circular arcs only.
    private static func arc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat,
                            rotation: CGFloat, large: Bool, sweep: Bool) {
        var r = abs(rx)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let d2 = dx * dx + dy * dy
        guard r > 0, d2 > 0 else { path.addLine(to: p1); return }
        r = max(r, sqrt(d2))
        let factor = sqrt(max(0, (r * r - d2) / d2)) * (large == sweep ? -1 : 1)
        let center = CGPoint(x: (p0.x + p1.x) / 2 + factor * dy, y: (p0.y + p1.y) / 2 - factor * dx)
        let a0 = atan2(p0.y - center.y, p0.x - center.x), a1 = atan2(p1.y - center.y, p1.x - center.x)
        // SVG's y axis points down, so a positive sweep is clockwise on screen = !clockwise in Path terms.
        path.addArc(center: center, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: !sweep)
    }
}

/// The 24-unit icon set; `fill` parts are drawn filled, the rest stroked at 1.5 units (music-app.ts svg()).
enum Icon {
    case play, pause, stop, search, settings, previous, next, speaker, folder, grid, chevronLeft

    var strokes: [String] {
        switch self {
        case .play, .pause: []
        case .stop: ["M7 6h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Z"]
        case .search: ["M17 10.5a6.5 6.5 0 1 1-13 0a6.5 6.5 0 1 1 13 0Z", "m16 16 4.5 4.5"]
        case .settings: ["M4 7h16M4 17h16"]
        case .previous: ["M5 5v14M19 5 8 12l11 7Z"]
        case .next: ["M19 5v14M5 5l11 7-11 7Z"]
        case .speaker: ["M4 9h4l5-4v14l-5-4H4Z", "M17 8a6 6 0 0 1 0 8M20 5a10 10 0 0 1 0 14"]
        case .folder: ["M3 7V5h6l2 2h10v13H3Z"]
        case .grid: ["M3 3h6v7H3Z", "M15 3h6v7h-6Z", "M3 14h6v7H3Z", "M15 14h6v7h-6Z"]
        case .chevronLeft: ["M15 5l-7 7 7 7"]
        }
    }

    var fills: [String] {
        switch self {
        case .play: ["m9 5 11 7-11 7Z"]
        case .pause: ["M7 5h3v14H7zM14 5h3v14h-3z"]
        case .previous: ["M19 5 8 12l11 7Z"]
        case .next: ["M5 5l11 7-11 7Z"]
        default: []
        }
    }

    /// Settings knobs are filled with --surface so they mask the rails behind them.
    var knobs: [CGPoint] { self == .settings ? [CGPoint(x: 9, y: 7), CGPoint(x: 15, y: 17)] : [] }
}

struct IconView: View {
    let icon: Icon
    var size: CGFloat = 17
    @Environment(\.palette) private var palette

    var body: some View {
        let style = StrokeStyle(lineWidth: 1.5 * size / 24, lineCap: .round, lineJoin: .round)
        ZStack {
            ForEach(icon.fills, id: \.self) { SVGPath(data: $0).fill(style: FillStyle(eoFill: false)) }
            ForEach(icon.strokes, id: \.self) { SVGPath(data: $0).stroke(style: style) }
            ForEach(Array(icon.knobs.enumerated()), id: \.offset) { _, p in
                let r = 2.5 * size / 24
                Circle().fill(palette.surface).frame(width: r * 2, height: r * 2)
                    .overlay(Circle().stroke(style: style))
                    .position(x: p.x * size / 24, y: p.y * size / 24)
            }
        }
        .frame(width: size, height: size)
    }
}
