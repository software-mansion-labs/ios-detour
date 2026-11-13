import Detour
import XCTest
@testable import DetourAttribution

final class DetourAttributionTests: XCTestCase {
    func testIsTheProviderTheCoreSdkTakes() async {
        let provider: DetourAttributionProvider = DetourAttribution()

        let token = await provider.attributionToken()

        XCTAssertNil(token)
    }
}
