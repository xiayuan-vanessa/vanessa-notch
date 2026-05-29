import XCTest
@testable import VanessaCore

final class SmokeTests: XCTestCase {
    func test_version_isNotEmpty() {
        XCTAssertFalse(VanessaCore.version.isEmpty)
    }
}
