import AppKit

/// Vertical scrolling capture: samples the region, finds how far the content
/// moved between frames and appends the new rows.
@MainActor
final class ScrollingCapture {
    private let region: CGRect
    private let capture: () async -> CGImage?
    private let sampleWidth = 320

    private var slices: [CGImage] = []
    private var previousFrame: CGImage?
    private var timer: Timer?
    private var idleTicks = 0
    private var busy = false
    private var finishRequested = false
    private var unmatchedFrames = 0

    private(set) var isRunning = false
    private(set) var totalHeight = 0

    var onUpdate: (() -> Void)?
    var onNeedsOverlap: (() -> Void)?
    var onFinish: ((CGImage?) -> Void)?

    init(region: CGRect, capture: @escaping () async -> CGImage?) {
        self.region = region
        self.capture = capture
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let header = "\(String(format: "%.3f", Date().timeIntervalSince1970)) start region=\(region.integral)\n"
        try? header.write(
            to: URL(fileURLWithPath: "/tmp/switchdeck-scroll.log"),
            atomically: true,
            encoding: .utf8
        )

        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        // Include the frame already being captured when Done was pressed.
        finishRequested = true
        if !busy { complete() }
    }

    func cancel() {
        isRunning = false
        finishRequested = false
        timer?.invalidate()
        timer = nil
        onFinish = nil
        onUpdate = nil
        onNeedsOverlap = nil
    }

    private func complete() {
        finishRequested = false
        log("stop slices=\(slices.count) height=\(totalHeight)")
        onFinish?(compose())
    }

    private func tick() {
        guard isRunning, !busy else { return }
        busy = true

        Task { [weak self] in
            guard let self else { return }
            let frame = await self.capture()
            self.busy = false
            guard self.isRunning || self.finishRequested else { return }
            if let frame {
                self.append(frame)
            } else {
                self.log("frame nil")
            }
            if self.finishRequested { self.complete() }
        }
    }

    private func append(_ frame: CGImage) {
        guard let previous = previousFrame else {
            slices = [frame]
            totalHeight = frame.height
            previousFrame = frame
            onUpdate?()
            return
        }

        guard let fullShift = pixelShift(from: previous, to: frame) else {
            unmatchedFrames += 1
            log("unmatched=\(unmatchedFrames)")
            if unmatchedFrames >= 3 { onNeedsOverlap?() }
            return
        }
        let recoveredOverlap = unmatchedFrames > 0
        unmatchedFrames = 0

        guard fullShift > 0 else {
            idleTicks += 1
            log("shift=0 idle=\(idleTicks)")
            // A pause or an unmatchable animation is not a request to finish.
            // Keep the last accepted frame as the stitching anchor.
            if recoveredOverlap { onUpdate?() }
            return
        }

        idleTicks = 0
        log("full=\(fullShift) of \(frame.height)")
        guard fullShift > 0, fullShift < frame.height - 4 else { return }

        let cropRect = CGRect(
            x: 0,
            y: frame.height - fullShift,
            width: frame.width,
            height: fullShift
        )
        guard let slice = frame.cropping(to: cropRect) else { return }

        slices.append(slice)
        previousFrame = frame
        totalHeight += slice.height
        onUpdate?()
    }

    private func log(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/switchdeck-scroll.log")
        let line = "\(String(format: "%.3f", Date().timeIntervalSince1970)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
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
        debugCompose(frames)?.height ?? 0
    }

    /// Debug: exposes the real compositing path for pixel-level regressions.
    static func debugCompose(_ frames: [CGImage]) -> CGImage? {
        let probe = ScrollingCapture(region: .zero, capture: { nil })
        for frame in frames {
            probe.append(frame)
        }
        return probe.compose()
    }

    /// Debug: reports the detected shift between two frames (full-resolution rows).
    static func detectShift(from previous: CGImage, to current: CGImage) -> Int {
        let probe = ScrollingCapture(region: .zero, capture: { nil })
        return probe.pixelShift(from: previous, to: current) ?? 0
    }

    private func grayscale(_ image: CGImage, nativeRows: Bool = false) -> ([UInt8], Int, Int) {
        let scale = min(1, Double(sampleWidth) / Double(image.width), 480.0 / Double(image.height))
        let width = nativeRows ? min(512, image.width) : max(1, Int(Double(image.width) * scale))
        let height = nativeRows ? image.height : max(1, Int(Double(image.height) * scale))

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
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width, height)
    }

    /// Compare the entire overlap, not one band that might contain only blank
    /// space. Buffers use top-left image rows: current[y] == previous[y + shift].
    private func difference(
        previous: ([UInt8], Int, Int),
        current: ([UInt8], Int, Int),
        shift: Int
    ) -> Double {
        let width = min(previous.1, current.1)
        let height = min(previous.2, current.2)
        let overlap = height - shift
        guard overlap > 0 else { return .infinity }
        var total = 0, count = 0
        for y in stride(from: 0, to: overlap, by: max(1, overlap / 96)) {
            for x in stride(from: 0, to: width, by: max(1, width / 64)) {
                total += abs(Int(current.0[y * current.1 + x]) - Int(previous.0[(y + shift) * previous.1 + x]))
                count += 1
            }
        }
        return Double(total) / Double(max(1, count))
    }

    private func pixelShift(from previous: CGImage, to current: CGImage) -> Int? {
        guard previous.width == current.width, previous.height == current.height else { return nil }
        let a = grayscale(previous), b = grayscale(current)
        let stationary = difference(previous: a, current: b, shift: 0)
        guard stationary > 0.5 else { return 0 }
        // At least a quarter of the frame must still overlap. Searching only
        // around height/4 silently lost ordinary, faster wheel gestures.
        let maxShift = b.2 - max(12, b.2 / 4)
        guard maxShift > 0 else { return nil }
        var candidates: [(shift: Int, score: Double)] = [(0, stationary)]
        for shift in 1...maxShift {
            let score = difference(previous: a, current: b, shift: shift)
            candidates.append((shift, score))
        }
        candidates.sort {
            $0.score == $1.score ? $0.shift < $1.shift : $0.score < $1.score
        }

        // Refine at native vertical resolution to avoid accumulating several
        // pixels of rounding error per frame on Retina displays.
        let scale = Double(current.height) / Double(b.2)
        let radius = Int(ceil(scale)) + 1
        let nativeA = grayscale(previous, nativeRows: true)
        let nativeB = grayscale(current, nativeRows: true)
        let zeroScore = difference(previous: nativeA, current: nativeB, shift: 0)
        var pixelShift = 0
        var pixelScore = zeroScore
        // Keep several coarse candidates: resampling can alias a one-pixel
        // displacement. Always include small native movements near zero.
        var shifts = Set(1...radius)
        let limit = current.height - max(12, current.height / 4)
        for candidate in candidates.prefix(4) {
            let estimate = Int((Double(candidate.shift) * scale).rounded())
            let lower = max(1, estimate - radius)
            let upper = min(limit, estimate + radius)
            if lower <= upper { shifts.formUnion(lower...upper) }
        }
        for shift in shifts.sorted() where shift <= limit {
            let score = difference(previous: nativeA, current: nativeB, shift: shift)
            if score < pixelScore {
                pixelScore = score
                pixelShift = shift
            }
        }
        guard pixelScore < 12, pixelScore < zeroScore * 0.75 else { return nil }
        let mismatch = edgeMismatch(previous: nativeA, current: nativeB, shift: pixelShift)
        guard mismatch.overall < 0.10, mismatch.worstTile < 0.35 else { return nil }
        return pixelShift
    }

    /// Normalise edge mismatch by actual content contrast. Large blank/dark
    /// areas must not make unrelated text look like a good overlapping match.
    private func edgeMismatch(
        previous: ([UInt8], Int, Int), current: ([UInt8], Int, Int), shift: Int
    ) -> (overall: Double, worstTile: Double) {
        let width = min(previous.1, current.1)
        let overlap = min(previous.2, current.2) - shift
        guard width > 2, overlap > 2 else { return (1, 1) }
        var error = 0, contrast = 0
        var tileErrors = [Int](repeating: 0, count: 128)
        var tileContrasts = [Int](repeating: 0, count: 128)
        for y in stride(from: 1, to: overlap - 1, by: max(1, overlap / 192)) {
            for x in stride(from: 1, to: width - 1, by: max(1, width / 256)) {
                let p = (y + shift) * previous.1 + x
                let c = y * current.1 + x
                let px = Int(previous.0[p + 1]) - Int(previous.0[p - 1])
                let cx = Int(current.0[c + 1]) - Int(current.0[c - 1])
                let py = Int(previous.0[p + previous.1]) - Int(previous.0[p - previous.1])
                let cy = Int(current.0[c + current.1]) - Int(current.0[c - current.1])
                let difference = abs(px - cx) + abs(py - cy)
                let signal = abs(px) + abs(cx) + abs(py) + abs(cy)
                error += difference
                contrast += signal
                let tile = (y * 8 / overlap) * 16 + x * 16 / width
                tileErrors[tile] += difference
                tileContrasts[tile] += signal
            }
        }
        // A mostly repeated paragraph can have a low overall error while one
        // distinctive word/number is different. Verify local tiles as well.
        var worst = 0.0
        for tile in 0..<128 where tileContrasts[tile] > max(200, contrast / 500) {
            worst = max(worst, Double(tileErrors[tile]) / Double(tileContrasts[tile]))
        }
        return contrast > 0 ? (Double(error) / Double(contrast), worst) : (1, 1)
    }
}
