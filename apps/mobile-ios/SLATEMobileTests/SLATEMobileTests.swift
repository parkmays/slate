import XCTest
@testable import SLATEMobile

final class SLATEMobileTests: XCTestCase {
    func testContractsReferenceMatchesRepoLayout() {
        XCTAssertEqual(SLATEMobileConfig.contractsWebAPIFilename, "web-api.json")
    }
}
