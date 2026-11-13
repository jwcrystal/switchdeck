import SwitchKit

/// The catalog the app actually runs with: the SwitchKit switches plus the ones
/// that need app-level UI.
@MainActor
enum AppCatalog {
    static func make(screenshot: ScreenshotCoordinator) -> SwitchCatalog {
        var items = SwitchCatalog.standard().items
        let item = screenshot.switchItem

        if let index = items.firstIndex(where: { $0.id == "recording" }) {
            items.insert(contentsOf: [item, screenshot.recognizeTextItem], at: index)
        } else {
            items.append(contentsOf: [item, screenshot.recognizeTextItem])
        }

        return SwitchCatalog(items: items)
    }
}
