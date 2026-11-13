import SwiftUI

/// music.css theme variables; every colour lerps day → night with one `night` value (0…1),
/// like the CSS @property interpolation (650 ms, cubic-bezier(0.4, 0, 0.2, 1)).
struct Palette {
    var night: Double

    static let themeAnimation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.65)

    private static func mix(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double), _ t: Double) -> Color {
        // Premultiplied interpolation, as CSS does for <color> custom properties.
        let pa = (a.0 * a.3, a.1 * a.3, a.2 * a.3), pb = (b.0 * b.3, b.1 * b.3, b.2 * b.3)
        let alpha = a.3 + (b.3 - a.3) * t
        guard alpha > 0 else { return .clear }
        return Color(.sRGB,
                     red: (pa.0 + (pb.0 - pa.0) * t) / alpha / 255,
                     green: (pa.1 + (pb.1 - pa.1) * t) / alpha / 255,
                     blue: (pa.2 + (pb.2 - pa.2) * t) / alpha / 255,
                     opacity: alpha)
    }

    var ink: Color { Self.mix((0x23, 0x27, 0x22, 1), (0xe9, 0xee, 0xf2, 1), night) }
    var muted: Color { Self.mix((0x74, 0x78, 0x6f, 1), (0x9c, 0xaa, 0xbd, 1), night) }
    var line: Color { Self.mix((42, 49, 42, 0.18), (208, 226, 243, 0.20), night) }
    var accent: Color { Self.mix((0xb5, 0x68, 0x34, 1), (0xd9, 0xad, 0x7d, 1), night) }
    var surface: Color { Self.mix((0xef, 0xed, 0xe7, 1), (0x16, 0x22, 0x34, 1), night) }
    var panel: Color { Self.mix((245, 244, 239, 0.97), (17, 27, 42, 0.97), night) }
    var pageBackground: Color { Self.mix((0xe8, 0xe5, 0xe1, 1), (0x08, 0x12, 0x1f, 1), night) }
    var veil: Color { Self.mix((236, 233, 225, 0.72), (10, 21, 37, 0.75), night) }
    var statusInk: Color { Self.mix((0x74, 0x78, 0x6f, 1), (0xe9, 0xee, 0xf2, 1), night) }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette(night: 0) }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// `.music-vignette` (music.css:114-126, music-theme.css:115-159, android.css:184-186).
struct Vignette: View {
    var night: Double
    var detail: Bool
    var portrait: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let night5 = Color(.sRGB, red: 5 / 255, green: 13 / 255, blue: 25 / 255)
        let side: (Double, Double, Double) = portrait ? (0.24, 0.48, 0.70) : detail ? (0.24, 0.48, 0.70) : (0.32, 0.58, 0.78)
        let sideOpacity = portrait ? 0.0 : 1.0
        ZStack {
            LinearGradient(stops: [
                .init(color: palette.veil, location: 0), .init(color: .clear, location: 0.23),
                .init(color: .clear, location: 0.75), .init(color: palette.veil, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .opacity(1 - night)
            ZStack {
                LinearGradient(stops: [
                    .init(color: night5.opacity(0.4), location: 0), .init(color: .clear, location: 0.24),
                    .init(color: .clear, location: 0.73), .init(color: night5.opacity(0.72), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                LinearGradient(stops: [
                    .init(color: .clear, location: side.0),
                    .init(color: night5.opacity(0.28 * sideOpacity), location: side.1),
                    .init(color: night5.opacity(0.78 * sideOpacity), location: side.2),
                    .init(color: night5.opacity(0.84 * sideOpacity), location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
            .opacity(night)
        }
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.1),
            .init(color: .black, location: 0.9), .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}
