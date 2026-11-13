import AVFoundation
import AppKit
import CoreAudio
import Foundation

/// Records audio to `~/Music/SwitchDeck` (or the folder chosen in Settings ›
/// Recording) with one click, and stops with the second. The menu shows the
/// elapsed time while recording.
public final class RecordingSwitch {
    public static let folderDefaultsKey = "RecordingFolder"
    public static let inputDeviceDefaultsKey = "RecordingInputDevice"

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var previousInputDevice: AudioDeviceID?
    private var terminateObserver: NSObjectProtocol?
    public private(set) var lastFileURL: URL?

    public init() {
        // Quitting mid-recording must not leave the system input switched.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreInputDevice()
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        restoreInputDevice()
    }

    public static var defaultFolder: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return music.appendingPathComponent("SwitchDeck")
    }

    public var folder: URL {
        if let path = UserDefaults.standard.string(forKey: Self.folderDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultFolder
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
        restoreInputDevice()
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
                t("Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone.")
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

        applyChosenInputDevice()

        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            restoreInputDevice()
            throw error
        }

        guard recorder.record() else {
            restoreInputDevice()
            throw SwitchDeckError.message(t("The recorder could not start."))
        }

        self.recorder = recorder
        self.startedAt = Date()
        self.lastFileURL = url
    }

    /// `AVAudioRecorder` follows the system default input, so a chosen
    /// microphone is installed for the length of the recording and put back by
    /// `stop()`. A missing device leaves the default alone.
    private func applyChosenInputDevice() {
        let uid = UserDefaults.standard.string(forKey: Self.inputDeviceDefaultsKey) ?? ""
        guard !uid.isEmpty,
              let chosen = AudioInput.devices().first(where: { $0.id == uid }),
              let current = AudioInput.defaultDeviceID(),
              chosen.deviceID != current
        else { return }

        guard AudioInput.setDefaultDevice(chosen.deviceID) else { return }
        previousInputDevice = current
    }

    private func restoreInputDevice() {
        guard let previousInputDevice else { return }
        AudioInput.setDefaultDevice(previousInputDevice)
        self.previousInputDevice = nil
    }
}
