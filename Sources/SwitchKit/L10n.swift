import Foundation

/// One user-facing string, looked up by its English wording.
///
/// English doubles as the key: the source stays readable, a missing translation
/// falls back to English instead of showing a key, and changing a wording only
/// needs one edit. Translations live in `Resources/<lang>.lproj/Localizable.strings`
/// and are copied into the app bundle by `scripts/build-app.sh`; outside the
/// bundle (unit tests, the CLI runner) every lookup returns the English text.
public func t(_ english: String) -> String {
    NSLocalizedString(english, tableName: nil, bundle: .main, value: english, comment: "")
}

/// `t` for strings with printf placeholders: `tf("%d items", count)`.
///
/// The English format is the key, so a translation must keep the same
/// placeholders; `scripts/check-localizations.sh` verifies that they do.
public func tf(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: t(english), arguments: arguments)
}
