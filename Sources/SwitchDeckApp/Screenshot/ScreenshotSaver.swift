import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Writes what the editor composed to the folder and format Settings ›
/// Screenshot picked.
enum ScreenshotSaver {
    @discardableResult
    static func save(
        _ image: NSImage,
        watermark: AnnotationRenderer.WatermarkOptions? = nil
    ) -> URL? {
        write(
            image,
            watermark: watermark,
            folder: ScreenshotPreferences.folder,
            format: ScreenshotPreferences.imageFormat,
            quality: ScreenshotPreferences.quality
        )
    }

    /// The seam tests use: settings are passed in rather than read.
    @discardableResult
    static func write(
        _ image: NSImage,
        watermark: AnnotationRenderer.WatermarkOptions?,
        folder: URL,
        format: ScreenshotPreferences.ImageFormat,
        quality: Double,
        date: Date = Date()
    ) -> URL? {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let url = folder.appendingPathComponent(
            ScreenshotPreferences.fileName(prefix: ScreenshotPreferences.prefix, at: date, format: format)
        )

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  format.utType.identifier as CFString,
                  1,
                  nil
              )
        else { return nil }

        var properties: [CFString: Any] = [:]
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        // The signature is burned into the pixels; these keys only keep the
        // text findable in the file's metadata.
        if let watermark {
            switch format {
            case .png:
                properties[kCGImagePropertyPNGDescription] = watermark.text
            case .jpeg, .heic:
                properties[kCGImagePropertyExifDictionary] = [
                    kCGImagePropertyExifUserComment: watermark.text,
                ] as CFDictionary
            }
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
