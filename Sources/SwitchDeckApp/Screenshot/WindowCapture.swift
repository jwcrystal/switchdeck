import AppKit

/// A window the user picked, in the overlay's screen coordinates
/// (bottom-left origin), so the editor's selection and the composer share one
/// coordinate space.
struct CaptureWindowTarget: Equatable {
    let id: CGWindowID
    let rect: CGRect
}

/// Composes one capture per window into a single image, keeping the windows at
/// their on-screen positions and drawing the shadow itself.
///
/// ScreenCaptureKit can include a window's own shadow, but it then shrinks the
/// window to fit the requested buffer. Drawing the shadow here keeps the window
/// content at native resolution and gives one predictable canvas for both a
/// single window and several.
enum WindowComposer {
    static let shadowBlur: CGFloat = 18
    /// The drawing context has a bottom-left origin, so negative height moves
    /// the shadow down while the window keeps its on-screen position.
    static let shadowOffset = NSSize(width: 0, height: -6)
    static let shadowOpacity: CGFloat = 0.35

    /// Match the selected window bounds exactly. Shadows may draw inside this
    /// canvas but never add blank margins outside the selection.
    static func canvas(for targets: [CaptureWindowTarget], screenBounds: CGRect) -> CGRect? {
        guard let first = targets.first else { return nil }
        let union = targets.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        let clipped = union.intersection(screenBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped
    }

    /// `shots` carry the window rects in the same space as `canvas`.
    static func compose(
        shots: [(image: CGImage, rect: CGRect)],
        canvas: CGRect,
        scale: CGFloat
    ) -> CGImage? {
        let safeScale = max(1, scale)
        let pixelWidth = Int((canvas.width * safeScale).rounded())
        let pixelHeight = Int((canvas.height * safeScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: safeScale, y: safeScale)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        for shot in shots {
            // Both the window rect and CGContext use bottom-left coordinates.
            // Flipping y here would mirror the layout within the selection.
            let drawRect = shot.rect.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
            guard drawRect.width >= 1, drawRect.height >= 1 else { continue }

            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: shadowOpacity)
            shadow.shadowBlurRadius = shadowBlur
            shadow.shadowOffset = shadowOffset
            shadow.set()

            NSImage(cgImage: shot.image, size: drawRect.size).draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        return context.makeImage()
    }
}
