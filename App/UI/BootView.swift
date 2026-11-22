// Opening film ported from RhineDroid web/src/music-opening.ts, music-boot.ts, music-boot.css
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import SwiftUI

/// App time 0 → 8 s. Paper covers the shelf until 3.92 s; at 4 s the native intro starts at scene
/// time 21.92 with speed 1.3, reaching 27.12 exactly at 8 s (ui-spec.md §10).
struct BootView: View {
    let portrait: Bool
    let size: CGSize
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var start = Date()

    static let sceneStart = 4.0, end = 8.0
    #if DEBUG
    /// Screenshot comparison with reference/i-boot-t*.png: SIMCTL_CHILD_RHINE_BOOT_FREEZE=1.02 holds that app time.
    private let frozen = ProcessInfo.processInfo.environment["RHINE_BOOT_FREEZE"].flatMap(Double.init)
    #else
    private let frozen: Double? = nil
    #endif

    var body: some View {
        TimelineView(.animation(paused: frozen != nil)) { context in
            let t = frozen ?? min(Self.end, context.date.timeIntervalSince(start))
            frame(t)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.skipIntro() }
        .task {
            guard frozen == nil else { return }
            start = Date()
            try? await Task.sleep(for: .seconds(Self.sceneStart))
            model.startIntroScene()
            try? await Task.sleep(for: .seconds(Self.end - Self.sceneStart))
            model.finishBoot()
        }
    }

    // MARK: Timeline (music-opening.ts:12-35)

    private func unit(_ t: Double, _ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
    private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    private func settle(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    @ViewBuilder private func frame(_ t: Double) -> some View {
        let paper = 1 - smooth(unit(t, 3.92, 4.38))
        let markOpacity = smooth(unit(t, 0.2, 0.48)) * (1 - smooth(unit(t, 1.8, 2.26)))
        let contour = settle(unit(t, 0.24, 1.64))
        let symbols = settle(unit(t, 0.84, 1.5))
        let orbitOpacity = smooth(unit(t, 1.64, 2.05)) * (1 - smooth(unit(t, 2.78, 3.28)))
        let orbitDraw = settle(unit(t, 1.64, 2.82))
        let orbitTurn = 190 * smooth(unit(t, 1.64, 3.3))
        let orbitScale = 0.9 + 0.1 * settle(unit(t, 1.64, 2.8))
        let titleIn = settle(unit(t, 2.64, 3.02)), titleOut = smooth(unit(t, 3.58, 4))
        let subtitle = smooth(unit(t, 2.82, 3.16)) * (1 - smooth(unit(t, 3.56, 4)))

        ZStack {
            // .music-opening-paper
            EllipticalGradient(colors: [palette.pageBackground, palette.surface], center: UnitPoint(x: 0.51, y: 0.44))
                .opacity(paper)

            mark(contour: contour, symbols: symbols)
                .opacity(markOpacity * paper)
                .position(x: size.width / 2, y: size.height / 2)

            let orbit = portrait ? min(size.width * 0.86, 500) : min(size.height * 0.66, size.width * 0.54, 520)
            OrbitShape(draw: orbitDraw, turn: orbitTurn, ink: palette.ink, accent: palette.accent)
                .frame(width: orbit, height: orbit)
                .scaleEffect(orbitScale)
                .opacity(orbitOpacity)
                .position(x: size.width / 2, y: size.height * 0.48)

            VStack(spacing: 24) {
                Text("一张一张，慢慢听")
                    .font(.mi(portrait ? 32 : min(48, max(23, size.width * 0.0335))))
                    .tracking((portrait ? 0.015 : 0.045) * (portrait ? 32 : 40))
                    .padding(.vertical, 5)
                    .fixedSize()
                    .mask(alignment: .top) {
                        GeometryReader { g in Rectangle().frame(height: g.size.height * titleIn) }
                    }
                    .offset(y: 18 * (1 - titleIn) - 8 * titleOut)
                    .opacity(titleIn * (1 - titleOut))
                Text("ONE ALBUM AT A TIME").font(.mi(9)).tracking(2.7).foregroundStyle(palette.muted).opacity(subtitle)
            }
            .foregroundStyle(palette.ink)
            .position(x: size.width / 2, y: size.height * 0.48)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(t < Self.end)
    }

    private func mark(contour: Double, symbols: Double) -> some View {
        let width = min(max(320, size.width * 0.4), 560, size.width - 40)
        return VStack(spacing: 17) {
            MarkShape(contour: contour, symbols: symbols, ink: palette.ink, accent: palette.accent)
                .frame(width: width, height: width * 192 / 856)
            Text("RhinePad").font(.mi(10, .demibold)).tracking(3.6).foregroundStyle(palette.ink)
        }
    }
}

/// The infinity contour (pathLength 1, drawn on), the + − symbols and the geometric disc emblem; viewBox 0 64 856 192.
private struct MarkShape: View {
    let contour: Double
    let symbols: Double
    let ink: Color
    let accent: Color

    static let contourPath = SVGPath.parse("M295 73C295 41 273 15 240 15C221 15 207 23 192 38C186 43 181 47 176 52C127 96 103 128 70 128C38 128 15 101 15 70C15 39 37 15 70 15C103 15 127 48 156 75C182 99 208 128 240 128C273 128 295 105 295 73Z")
    static let symbolPath = SVGPath.parse("M44 70h50M69 45v50M219 70h44")

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 856
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: -64)

            var logo = context
            logo.translateBy(x: 112, y: 78)
            logo.scaleBy(x: 1.15, y: 1.15)
            if contour > 0 {
                logo.stroke(Self.contourPath.trimmedPath(from: 0, to: contour), with: .color(ink), style: StrokeStyle(lineWidth: 18))
            }
            logo.opacity = symbols
            logo.stroke(Self.symbolPath, with: .color(ink), style: StrokeStyle(lineWidth: 11))

            var divider = context
            divider.opacity = symbols * 0.35
            divider.stroke(Path { $0.move(to: CGPoint(x: 516, y: 108)); $0.addLine(to: CGPoint(x: 516, y: 212)) },
                           with: .color(ink), lineWidth: 2.5)

            var disc = context
            let center = CGPoint(x: 642, y: 160)
            let outer = Path { $0.addArc(center: center, radius: 74, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false) }
            if contour > 0 {
                disc.stroke(outer.trimmedPath(from: 0, to: contour), with: .color(ink), style: StrokeStyle(lineWidth: 14))
            }
            disc.opacity = symbols
            let groove = Path { $0.addArc(center: center, radius: 46, startAngle: .degrees(-35), endAngle: .degrees(145), clockwise: false) }
            disc.stroke(groove, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            let groove2 = Path { $0.addArc(center: center, radius: 46, startAngle: .degrees(185), endAngle: .degrees(305), clockwise: false) }
            disc.stroke(groove2, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            let spindle = Path(ellipseIn: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30))
            disc.fill(spindle, with: .color(accent))
        }
    }
}

/// `.music-opening-orbit` (viewBox 520): drawn outer ring, dashed inner ring, two dots, fixed crosshair.
private struct OrbitShape: View {
    let draw: Double
    let turn: Double
    let ink: Color
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let s = size.width / 520
            context.scaleBy(x: s, y: s)
            var ring = context
            ring.translateBy(x: 260, y: 260)
            ring.rotate(by: .degrees(turn))
            ring.translateBy(x: -260, y: -260)
            // SVG circles start at 3 o'clock and run clockwise on screen.
            let outer = Path { $0.addArc(center: CGPoint(x: 260, y: 260), radius: 236, startAngle: .zero, endAngle: .degrees(360), clockwise: false) }
            if draw > 0 { ring.stroke(outer.trimmedPath(from: 0, to: draw), with: .color(ink), lineWidth: 1.2) }
            let inner = Path { $0.addArc(center: CGPoint(x: 260, y: 260), radius: 207, startAngle: .zero, endAngle: .degrees(360), clockwise: false) }
            ring.stroke(inner, with: .color(ink), style: StrokeStyle(lineWidth: 1.2, dash: [142, 91, 380, 95]))
            ring.fill(Path(ellipseIn: CGRect(x: 256, y: 20, width: 8, height: 8)), with: .color(ink))
            ring.fill(Path(ellipseIn: CGRect(x: 256, y: 492, width: 8, height: 8)), with: .color(accent))
            context.stroke(Path { $0.move(to: CGPoint(x: 252, y: 260)); $0.addLine(to: CGPoint(x: 268, y: 260))
                $0.move(to: CGPoint(x: 260, y: 252)); $0.addLine(to: CGPoint(x: 260, y: 268)) }, with: .color(ink), lineWidth: 1.1)
        }
    }
}
