import Foundation

/// Locks the screen.
///
/// Preferred path is the private `SACLockScreenImmediate` in `login.framework`,
/// which locks instantly with no UI scripting. If the symbol ever disappears,
/// the fallback is the ⌃⌘Q keystroke through System Events.
public final class LockScreenSwitch {
    private typealias LockFunction = @convention(c) () -> Int32

    private static let frameworkPaths = [
        "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
        "/System/Library/PrivateFrameworks/login.framework/login",
    ]

    public init() {}

    public func lock() throws {
        if let lock = Self.lockFunction() {
            _ = lock()
            return
        }
        try Automation.run("""
        tell application "System Events" to keystroke "q" using {command down, control down}
        """)
    }

    private static func lockFunction() -> LockFunction? {
        for path in frameworkPaths {
            guard let handle = dlopen(path, RTLD_NOW),
                  let symbol = dlsym(handle, "SACLockScreenImmediate")
            else {
                continue
            }
            return unsafeBitCast(symbol, to: LockFunction.self)
        }
        return nil
    }
}
