// Cover preparation from RhineDroid VulkanArchiveRenderer.coverBitmap (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import CoreGraphics
import CoreText
import Foundation
import ImageIO

public enum CoverArt {
    /// Decodes straight to `size` with ImageIO's thumbnailer (never the full-resolution bitmap), then
    /// draws it aspect-fit with a 2 px inset over the #C2C3BB insert paper. Returns RGBA8 sRGB rows, top first.
    public static func pixels(_ data: Data?, size: Int, title: String? = nil) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = Data(count: size * size * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(red: 194 / 255, green: 195 / 255, blue: 187 / 255, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            if let image = data.flatMap({ thumbnail($0, maxPixel: size) }) {
                let scale = CGFloat(size - 4) / CGFloat(max(image.width, image.height))
                let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2, width: w, height: h))
            } else {
                // Upstream fallback: the first 12 characters of the title in #485553.
                let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, CGFloat(size) / 12, nil)
                let text = String((title ?? "LOCAL COLLECTION").prefix(12))
                let attributed = NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 72 / 255, green: 85 / 255, blue: 83 / 255, alpha: 1),
                ])
                context.textPosition = CGPoint(x: CGFloat(size) / 16, y: CGFloat(size) * (1 - 0.53))
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
        return bytes
    }

    public static func thumbnail(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}
