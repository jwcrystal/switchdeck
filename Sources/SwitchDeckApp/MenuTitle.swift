import AppKit

/// Right-aligned grey second column, the way the original menu shows
/// "Keep Awake — Until 18:30" and "Empty Trash — 101 items".
///
/// The tab stop sits at the end of the widest title plus a gap plus the widest
/// subtitle, so a long subtitle such as "Auto-unlocks in 5 min" can never run
/// into the title.
enum MenuTitle {
    static func make(_ title: String, subtitle: String?, column: CGFloat = 220) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )

        guard let subtitle, !subtitle.isEmpty else { return result }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: column, options: [:])]
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

    /// Width in points a string needs with the menu font.
    static func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
    }
}
