import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Shared save path: ~/Downloads by default, `SwitchDeck Screenshot <date>.png`
/// unless the two UserDefaults keys are set (Settings will expose them later).
enum ScreenshotSaver {
    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: "ScreenshotFolder"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    static var prefix: String {
        let stored = UserDefaults.standard.string(forKey: "ScreenshotFilenamePrefix") ?? "SwitchDeck"
        return stored.trimmingCharacters(in: .whitespaces)
    }

    static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(formatter.string(from: Date())).png"
        return prefix.isEmpty ? base : "\(prefix) \(base)"
    }

    @discardableResult
    static func save(
        _ image: NSImage,
        watermark: AnnotationRenderer.WatermarkOptions? = nil
    ) -> URL? {
        let directory = folder
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let url = directory.appendingPathComponent(fileName())

        if let watermark,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let destination = CGImageDestinationCreateWithURL(
               url as CFURL,
               UTType.png.identifier as CFString,
               1,
               nil
           ) {
            let properties: [CFString: Any] = [kCGImagePropertyPNGDescription: watermark.text]
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
            return CGImageDestinationFinalize(destination) ? url : nil
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { return nil }

        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
