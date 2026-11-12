import Foundation
import ObjectiveC

/// Night Shift through `CoreBrightness`'s `CBBlueLightClient`.
///
/// There is no public API for Night Shift. This is the same private class the
/// original app drives; macOS 27 still ships it in the dyld shared cache, so the
/// path resolves through `dlopen` even though the file is not on disk.
///
/// `getBlueLightStatus:` fills a struct whose second byte is the enabled flag;
/// byte 0 is the return value of the same call. If a future macOS changes that
/// layout, this switch reports "not available" or simply does nothing visible.
public final class NightShiftSwitch {
    @objc private protocol BlueLightClientAPI {
        func setEnabled(_ enabled: Bool) -> Bool
        func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    }

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    private var client: BlueLightClientAPI?
    /// Keeps the Objective-C object alive; `client` is an unretained bit cast.
    private var object: NSObject?

    public init() {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else {
            return
        }
        let instance = cls.init()
        object = instance
        client = unsafeBitCast(instance, to: BlueLightClientAPI.self)
    }

    public var isAvailable: Bool { client != nil }

    public var isOn: Bool {
        guard let client else { return false }
        var buffer = [UInt8](repeating: 0, count: 64)
        let succeeded = buffer.withUnsafeMutableBytes { raw in
            client.getBlueLightStatus(raw.baseAddress!)
        }
        guard succeeded else { return false }
        return buffer[1] != 0
    }

    public func set(_ on: Bool) throws {
        guard let client else {
            throw SwitchDeckError.message("Night Shift is not available on this macOS version.")
        }
        guard client.setEnabled(on) else {
            throw SwitchDeckError.message("CoreBrightness refused to change Night Shift.")
        }
    }

    public func toggle() throws {
        try set(!isOn)
    }
}
