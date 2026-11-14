import XCTest
@testable import SwitchDeckApp

/// Runs against the test process's own defaults domain, restored afterwards.
final class RecognitionPreferencesTests: XCTestCase {
    private let keys = [
        ScreenshotPreferences.qrLinkActionKey,
        ScreenshotPreferences.toastSecondsKey,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testQRLinkActionDefaultsToCopy() {
        XCTAssertEqual(ScreenshotPreferences.qrLinkAction, .copy)
        UserDefaults.standard.set("launch", forKey: ScreenshotPreferences.qrLinkActionKey)
        XCTAssertEqual(ScreenshotPreferences.qrLinkAction, .copy)
    }

    func testQRLinkActionRoundTrips() {
        ScreenshotPreferences.qrLinkAction = .open
        XCTAssertEqual(ScreenshotPreferences.qrLinkAction, .open)
    }

    func testToastSecondsDefaultsAndRejectsUnknownValues() {
        XCTAssertEqual(ScreenshotPreferences.toastSeconds, ScreenshotPreferences.defaultToastSeconds)
        UserDefaults.standard.set(42, forKey: ScreenshotPreferences.toastSecondsKey)
        XCTAssertEqual(ScreenshotPreferences.toastSeconds, ScreenshotPreferences.defaultToastSeconds)
        ScreenshotPreferences.toastSeconds = 5
        XCTAssertEqual(ScreenshotPreferences.toastSeconds, 5)
    }

    func testDefaultToastSecondsIsOffered() {
        XCTAssertTrue(ScreenshotPreferences.toastSecondsChoices.contains(ScreenshotPreferences.defaultToastSeconds))
    }
}
