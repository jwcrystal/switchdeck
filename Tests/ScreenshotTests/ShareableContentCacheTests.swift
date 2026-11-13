import XCTest
@testable import SwitchDeckApp

final class ShareableContentCacheTests: XCTestCase {
    func testReusesFreshCacheContainingAllExcludedWindows() {
        XCTAssertTrue(ScreenCaptureService.canReuse(cachedWindowIDs: [1, 2, 3], age: 1, excluding: [1, 3]))
    }

    func testRefetchesWhenAnExcludedWindowIsMissing() {
        XCTAssertFalse(ScreenCaptureService.canReuse(cachedWindowIDs: [1, 2], age: 1, excluding: [1, 9]))
    }

    func testRefetchesWhenCacheIsStale() {
        XCTAssertFalse(ScreenCaptureService.canReuse(cachedWindowIDs: [1, 2], age: 20, excluding: [1]))
    }

    func testEmptyExclusionReusesFreshCache() {
        XCTAssertTrue(ScreenCaptureService.canReuse(cachedWindowIDs: [], age: 0, excluding: []))
    }
}
