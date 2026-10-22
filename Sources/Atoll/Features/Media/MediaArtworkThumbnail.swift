import AppKit

/// Artwork pre-scaled on the CPU to the size a view draws it at.
///
/// The adapter delivers ~600 px covers. Handing those straight to `Image` lets
/// Core Animation minify them with plain bilinear sampling, which at 19 pt
/// aliases into visible blocks. A square thumbnail rendered at the display's
/// backing scale and drawn 1:1 stays smooth.
@MainActor
enum MediaArtworkThumbnail {
    private struct Entry {
        let source: NSImage
        let image: NSImage
    }

    /// One entry per requested point size; the source is matched by identity,
    /// so a new track replaces the entry on first draw.
    private static var cache: [CGFloat: Entry] = [:]

    static func image(_ source: NSImage, pointSize: CGFloat) -> NSImage {
        if let entry = cache[pointSize], entry.source === source { return entry.image }
        let image = render(source, pointSize: pointSize)
        // The player card's size follows the nook width, so bound the growth.
        if cache.count >= 8 { cache.removeAll() }
        cache[pointSize] = Entry(source: source, image: image)
        return image
    }

    private static func render(_ source: NSImage, pointSize: CGFloat) -> NSImage {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let pixels = Int((pointSize * scale).rounded(.up))
        guard pixels > 0,
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return source }

        // Aspect-fill crop to a square so non-square art isn't squashed.
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let side = min(width, height)
        let crop = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        guard let square = cg.cropping(to: crop) else { return source }

        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let output = context.makeImage() else { return source }
        return NSImage(cgImage: output, size: NSSize(width: pointSize, height: pointSize))
    }
}
