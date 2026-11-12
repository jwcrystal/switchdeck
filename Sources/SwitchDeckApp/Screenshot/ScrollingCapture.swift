import AppKit

/// Vertical scrolling capture: samples the region, finds how far the content
/// moved between frames and appends the new rows.
@MainActor
final class ScrollingCapture {
    private let region: CGRect
    private let capture: () async -> CGImage?
    private let sampleWidth = 240

    private var slices: [CGImage] = []
    private var previousGray: ([UInt8], Int, Int)?
    private var timer: Timer?
    private var idleTicks = 0
    private var busy = false

    private(set) var isRunning = false
    private(set) var totalHeight = 0

    var onUpdate: (() -> Void)?
    var onFinish: ((CGImage?) -> Void)?

    init(region: CGRect, capture: @escaping () async -> CGImage?) {
        self.region = region
        self.capture = capture
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        onFinish?(compose())
    }

    private func tick() {
        guard isRunning, !busy else { return }
        busy = true

        Task { [weak self] in
            guard let self else { return }
            let frame = await self.capture()
            self.busy = false
            guard let frame else { return }
            self.append(frame)
        }
    }

    private func append(_ frame: CGImage) {
        let gray = grayscale(frame)
        guard let previous = previousGray else {
            slices = [frame]
            totalHeight = frame.height
            previousGray = gray
            onUpdate?()
            return
        }

        let shift = verticalShift(previous: previous, current: gray)
        previousGray = gray

        guard shift > 0 else {
            idleTicks += 1
            if !slices.isEmpty, idleTicks >= 8 {
                stop()
            }
            return
        }

        idleTicks = 0
        let fullShift = Int(
            Double(shift) * Double(frame.height) / Double(max(1, gray.2))
        )
        guard fullShift > 0, fullShift < frame.height - 4 else { return }

        let cropRect = CGRect(
            x: 0,
            y: frame.height - fullShift,
            width: frame.width,
            height: fullShift
        )
        guard let slice = frame.cropping(to: cropRect) else { return }

        slices.append(slice)
        totalHeight += slice.height
        onUpdate?()
    }

    private func compose() -> CGImage? {
        guard let first = slices.first else { return nil }
        let height = slices.reduce(0) { $0 + $1.height }
        guard height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: first.width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var y = height
        for slice in slices {
            y -= slice.height
            context.draw(slice, in: CGRect(x: 0, y: y, width: slice.width, height: slice.height))
        }

        return context.makeImage()
    }

    // MARK: - Matching

    /// Debug: stitches frames and reports the composed height.
    static func debugStitch(_ frames: [CGImage]) -> Int {
        let probe = ScrollingCapture(region: .zero, capture: { nil })
        for frame in frames {
            probe.append(frame)
        }
        return probe.compose()?.height ?? 0
    }

    /// Debug: reports the detected shift between two frames (full-resolution rows).
    static func detectShift(from previous: CGImage, to current: CGImage) -> Int {
        let probe = ScrollingCapture(region: .zero, capture: { nil })
        let a = probe.grayscale(previous)
        let b = probe.grayscale(current)
        let shift = probe.verticalShift(previous: a, current: b)
        return Int(Double(shift) * Double(current.height) / Double(max(1, b.2)))
    }

    private func grayscale(_ image: CGImage) -> ([UInt8], Int, Int) {
        let ratio = CGFloat(image.height) / max(1, CGFloat(image.width))
        let width = sampleWidth
        let height = max(1, Int(CGFloat(width) * ratio))

        var data = [UInt8](repeating: 0, count: width * height)
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width, height)
    }

    /// How many (downscaled) rows the content moved between the two frames.
    /// Positive means the content moved up (normal scrolling down).
    private func verticalShift(
        previous: ([UInt8], Int, Int),
        current: ([UInt8], Int, Int)
    ) -> Int {
        let width = min(previous.1, current.1)
        let height = min(previous.2, current.2)
        let band = min(24, max(4, height / 3))
        let anchor = height / 4
        let maxShift = min(height - band - anchor, height / 2)
        guard maxShift > 0 else { return 0 }

        var bestShift = 0
        var bestDifference = Int.max

        for shift in -maxShift...maxShift {
            let previousStart = anchor + shift
            guard previousStart >= 0, previousStart + band <= height else { continue }

            var difference = 0
            for y in 0..<band {
                let currentRow = (anchor + y) * width
                let previousRow = (previousStart + y) * width
                for x in stride(from: 0, to: width, by: 3) {
                    difference += abs(Int(current.0[currentRow + x]) - Int(previous.0[previousRow + x]))
                }
            }

            if difference < bestDifference {
                bestDifference = difference
                bestShift = shift
            }
        }

        // Reject matches that are barely better than noise.
        let samples = band * ((width + 2) / 3)
        let average = bestDifference / max(1, samples)
        return average < 12 ? -bestShift : 0
    }
}
