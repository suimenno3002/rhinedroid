import CoreText
import SwiftUI

/// MiSans ships as the upstream woff2 files; CoreText registers them unchanged.
enum Fonts {
    static func register() {
        guard let folder = Bundle.main.url(forResource: "fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "woff2" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}

enum MiWeight: String { case light = "Light", regular = "Regular", demibold = "Demibold", bold = "Bold" }

extension Font {
    /// CSS px map 1:1 to points on iPad, so sizes from the upstream stylesheets apply directly.
    static func mi(_ size: CGFloat, _ weight: MiWeight = .regular) -> Font {
        .custom("MiSans-\(weight.rawValue)", fixedSize: size)
    }
}
