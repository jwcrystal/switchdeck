import AVFoundation
import Foundation

/// Records audio to `~/Music/SwitchDeck` with one click, and stops with the
/// second. The menu shows the elapsed time while recording.
public final class RecordingSwitch {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    public private(set) var lastFileURL: URL?

    public init() {}

    public var folder: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return music.appendingPathComponent("SwitchDeck")
    }

    public var isRecording: Bool { recorder?.isRecording ?? false }

    public var subtitle: String? {
        guard let startedAt else { return nil }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    public func toggle() throws {
        if isRecording {
            stop()
        } else {
            try requestPermissionAndStart()
        }
    }

    public func stop() {
        recorder?.stop()
        recorder = nil
        startedAt = nil
    }

    private func requestPermissionAndStart() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            try start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    try? self?.start()
                }
            }
        default:
            throw SwitchDeckError.message(
                "Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone."
            )
        }
    }

    private func start() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("Recording \(formatter.string(from: Date())).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else {
            throw SwitchDeckError.message("The recorder could not start.")
        }

        self.recorder = recorder
        self.startedAt = Date()
        self.lastFileURL = url
    }
}
