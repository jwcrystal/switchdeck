import AppKit

/// Right-aligned grey second column, the way the original menu shows
/// "Keep Awake — Until 18:30" and "Empty Trash — 101 items".
enum MenuTitle {
    static func make(_ title: String, subtitle: String?) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )

        guard let subtitle, !subtitle.isEmpty else { return result }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 220, options: [:])]
        result.append(NSAttributedString(
            string: "\t" + subtitle,
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
}
