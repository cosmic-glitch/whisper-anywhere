import XCTest
@testable import WhisperAnywhere

final class AudioCaptureServiceTests: XCTestCase {
    func testInactiveServiceReturnsNilLevels() {
        let service = AudioCaptureService()
        XCTAssertNil(service.currentNormalizedInputLevel())
        XCTAssertNil(service.currentEqualizerBands())
    }
}
