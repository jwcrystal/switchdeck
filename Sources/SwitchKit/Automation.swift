import Foundation

/// Thin wrapper around `NSAppleScript`.
///
/// A few system settings (appearance, the Trash, some Focus states) have no
/// public API, but Finder and System Events expose them. The app is not
/// sandboxed, so it only needs the user's Automation permission the first time.
public enum Automation {
    @discardableResult
    public static func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw SwitchDeckError.automation("Could not compile the AppleScript.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            throw SwitchDeckError.automation(
                "macOS refused the AppleScript: \(message ?? "unknown error") (code \(number.map(String.init) ?? "?"))."
            )
        }

        return result
    }
}
