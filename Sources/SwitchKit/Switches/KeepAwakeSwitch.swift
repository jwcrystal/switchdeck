import Foundation

/// Keeps the Mac awake with a power assertion, optionally for a fixed duration.
///
/// `ProcessInfo.beginActivity` gives us a real assertion (visible in `pmset -g
/// assertions`), so nothing sleeps while it runs. The duration timer only ends
/// the assertion; it does not wake anything.
public final class KeepAwakeSwitch {
    public struct Duration {
        public let title: String
        public let minutes: Int?
    }

    public static let durations: [Duration] = [
        Duration(title: "Indefinitely", minutes: nil),
        Duration(title: "5 minutes", minutes: 5),
        Duration(title: "10 minutes", minutes: 10),
        Duration(title: "15 minutes", minutes: 15),
        Duration(title: "30 minutes", minutes: 30),
        Duration(title: "45 minutes", minutes: 45),
        Duration(title: "1 hour", minutes: 60),
        Duration(title: "2 hours", minutes: 120),
        Duration(title: "4 hours", minutes: 240),
    ]

    private var activity: NSObjectProtocol?
    private var expiry: Date?
    private var expiryTimer: Timer?
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    public init() {}

    public var isOn: Bool { activity != nil }

    public var subtitle: String? {
        guard isOn else { return nil }
        guard let expiry else { return t("Until turned off") }
        return tf("Until %@", Self.clock.string(from: expiry))
    }

    public func start(minutes: Int?) {
        stop()

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "SwitchDeck: Keep Awake"
        )

        guard let minutes else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        expiry = deadline
        expiryTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    public func stop() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        expiry = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
    }
}
