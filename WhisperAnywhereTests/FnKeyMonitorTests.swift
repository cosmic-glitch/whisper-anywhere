import CoreGraphics
import XCTest
@testable import WhisperAnywhere

final class FnKeyMonitorTests: XCTestCase {
    func testFnPressAndReleaseEvents() {
        let monitor = FnKeyMonitor()

        XCTAssertNil(monitor.process(flags: []))
        XCTAssertEqual(monitor.process(flags: [.maskSecondaryFn]), .pressed)
        XCTAssertNil(monitor.process(flags: [.maskSecondaryFn]))
        XCTAssertEqual(monitor.process(flags: []), .released)
    }
}
