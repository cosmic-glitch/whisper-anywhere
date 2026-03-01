import XCTest
@testable import NativeWhisper

final class AudioCaptureServiceTests: XCTestCase {
    func testInactiveServiceReturnsNilLevels() {
        let service = AudioCaptureService()
        XCTAssertNil(service.currentNormalizedInputLevel())
        XCTAssertNil(service.currentEqualizerBands())
    }
}
