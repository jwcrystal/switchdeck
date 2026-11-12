import AppKit

/// Right-aligned grey second column, the way the original menu shows
/// "Keep Awake — Until 18:30" and "Empty Trash — 101 items".
///
/// The column is a fixed width so the menu does not grow with the longest label.
/// A subtitle that would not fit is shortened with an ellipsis, which keeps a
/// 24pt gap to the title and the menu width stable between opens.
enum MenuTitle {
    static let column: CGFloat = 230
    private static let minimumGap: CGFloat = 24

    static func make(_ title: String, subtitle: String?) -> NSAttributedString {
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        let result = NSMutableAttributedString(string: title, attributes: titleAttributes)

        guard let subtitle, !subtitle.isEmpty else { return result }

        let allowedWidth = max(40, column - width(of: title) - minimumGap)
        let fitted = fittedSubtitle(subtitle, maxWidth: allowedWidth)

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: column, options: [:])]

        result.append(NSAttributedString(
            string: "\t" + fitted,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        result.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    /// Width in points a string needs with the menu font.
    static func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }

    private static func fittedSubtitle(_ text: String, maxWidth: CGFloat) -> String {
        guard width(of: text) > maxWidth else { return text }

        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters).trimmingCharacters(in: .whitespaces) + "…"
            if width(of: candidate) <= maxWidth {
                return candidate
            }
        }
        return "…"
    }
}
