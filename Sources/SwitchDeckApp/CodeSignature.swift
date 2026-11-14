import Security

/// Whether the running app carries only an ad-hoc signature. macOS ties
/// privacy grants to the signing identity, so an ad-hoc build can lose them
/// after an update.
enum CodeSignature {
    static let isAdHoc: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return true }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return true }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any],
              dict[kSecCodeInfoIdentifier as String] != nil,
              let raw = dict[kSecCodeInfoFlags as String] as? UInt32 else { return true }

        return raw & SecCodeSignatureFlags.adhoc.rawValue != 0
    }()
}
