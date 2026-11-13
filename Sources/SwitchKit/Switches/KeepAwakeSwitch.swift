import Foundation

/// Keeps the Mac awake with a power assertion, optionally for a fixed duration.
///
/// `ProcessInfo.beginActivity` gives us a real assertion (visible in `pmset -g
/// assertions`), so nothing sleeps while it runs. The duration timer only ends
/// the assertion; it does not wake anything.
///
/// By default only the system is kept awake and the display may still dim and
/// turn off. `keepsDisplayOn` adds a display assertion as well; it is
/// remembered across launches.
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

    static let keepsDisplayOnDefaultsKey = "keepAwake.keepsDisplayOn"

    /// The assertion options for a run, kept separate so they can be tested.
    static func activityOptions(keepsDisplayOn: Bool) -> ProcessInfo.ActivityOptions {
        var options: ProcessInfo.ActivityOptions = [.idleSystemSleepDisabled, .userInitiated]
        if keepsDisplayOn {
            options.insert(.idleDisplaySleepDisabled)
        }
        return options
    }

    private let defaults: UserDefaults
    private var activity: NSObjectProtocol?
    private(set) var activeOptions: ProcessInfo.ActivityOptions?
    private(set) var expiry: Date?
    private var expiryTimer: Timer?
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isOn: Bool { activity != nil }

    /// Also keep the display from sleeping. Changing it while a run is active
    /// swaps the assertion and keeps the same end time.
    public var keepsDisplayOn: Bool {
        get { defaults.bool(forKey: Self.keepsDisplayOnDefaultsKey) }
        set {
            guard newValue != keepsDisplayOn else { return }
            defaults.set(newValue, forKey: Self.keepsDisplayOnDefaultsKey)
            if isOn {
                beginActivity()
            }
        }
    }

    public var subtitle: String? {
        guard isOn else { return nil }
        guard let expiry else { return t("Until turned off") }
        return tf("Until %@", Self.clock.string(from: expiry))
    }

    public func start(minutes: Int?) {
        stop()
        beginActivity()

        guard let minutes else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        expiry = deadline
        expiryTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes) * 60, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    public func stop() {
        endActivity()
        expiry = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    /// Starts (or replaces) the assertion with the current options. The new
    /// one is taken before the old one is released, so there is no gap.
    private func beginActivity() {
        let options = Self.activityOptions(keepsDisplayOn: keepsDisplayOn)
        let previous = activity
        activity = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: "SwitchDeck: Keep Awake"
        )
        activeOptions = options
        if let previous {
            ProcessInfo.processInfo.endActivity(previous)
        }
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        activeOptions = nil
    }
}
