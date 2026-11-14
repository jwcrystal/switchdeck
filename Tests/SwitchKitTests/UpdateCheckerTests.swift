import XCTest
@testable import SwitchKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: - Version comparison

    func testVersionIgnoresLeadingVAndTrailingZeroComponents() {
        XCTAssertEqual(AppVersion("v0.8.0"), AppVersion("0.8"))
        XCTAssertEqual(AppVersion("0.8"), AppVersion("0.8.0"))
        XCTAssertNotNil(AppVersion("0.8.0"))
    }

    func testVersionComparesNumericallyNotLexically() {
        XCTAssertGreaterThan(AppVersion("0.10.0")!, AppVersion("0.9.1")!)
        XCTAssertGreaterThan(AppVersion("1.0.0")!, AppVersion("0.99.99")!)
        XCTAssertGreaterThan(AppVersion("v1.2.3")!, AppVersion("1.2.2")!)
    }

    func testVersionRejectsGarbage() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("garbage"))
        XCTAssertNil(AppVersion("1.x.0"))
        XCTAssertNil(AppVersion("1..0"))
    }

    // MARK: - check()

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/jwcrystal/switchdeck/releases/latest")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func checker(
        current: String,
        tag: String,
        url: String = "https://github.com/jwcrystal/switchdeck/releases/tag/v0.9.0",
        status: Int = 200
    ) -> UpdateChecker {
        UpdateChecker(currentVersion: current) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.timeoutInterval, 15)
            let body = """
            {"tag_name": "\(tag)", "html_url": "\(url)", "name": "ignored"}
            """
            return (Data(body.utf8), self.response(status))
        }
    }

    func testNewerReleaseIsAvailable() async throws {
        let result = try await checker(current: "0.8.0", tag: "v0.9.0").check()
        XCTAssertEqual(
            result,
            .updateAvailable(
                ReleaseInfo(
                    version: "0.9.0",
                    url: URL(string: "https://github.com/jwcrystal/switchdeck/releases/tag/v0.9.0")!
                )
            )
        )
    }

    func testSameVersionIsUpToDate() async throws {
        let result = try await checker(current: "0.9.0", tag: "v0.9.0").check()
        XCTAssertEqual(result, .upToDate)
    }

    func testOlderReleaseIsUpToDate() async throws {
        let result = try await checker(current: "0.9.0", tag: "v0.8.0").check()
        XCTAssertEqual(result, .upToDate)
    }

    func testNonOKStatusThrows() async {
        await assertThrows(checker(current: "0.8.0", tag: "v0.9.0", status: 403))
    }

    func testMalformedJSONThrows() async {
        let broken = UpdateChecker(currentVersion: "0.8.0") { _ in
            (Data("not json".utf8), self.response(200))
        }
        await assertThrows(broken)
    }

    private func assertThrows(
        _ checker: UpdateChecker,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await checker.check()
            XCTFail("expected an error", file: file, line: line)
        } catch {
            XCTAssertTrue(error is SwitchDeckError, file: file, line: line)
            XCTAssertFalse(error.localizedDescription.isEmpty, file: file, line: line)
        }
    }
}
