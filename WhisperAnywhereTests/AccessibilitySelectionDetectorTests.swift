@preconcurrency import ApplicationServices
import XCTest
@testable import WhisperAnywhere

final class AccessibilitySelectionDetectorTests: XCTestCase {
    func testReaderReturnsAXSelectedTextWhenPresent() {
        let element = SendableBox(AXUIElementCreateApplication(getpid()))
        let reader = AccessibilitySelectionReader(
            isAccessibilityTrusted: { true },
            focusedElementProvider: { element.value },
            attributeValueProvider: { _, attribute in
                if attribute as String == kAXSelectedTextAttribute as String {
                    return "Selected text" as CFTypeRef
                }
                return nil
            },
            parameterizedAttributeValueProvider: { _, _, _ in nil }
        )

        XCTAssertEqual(reader.readSelectedText(), "Selected text")
    }

    func testReaderFallsBackToSelectedTextRange() {
        let element = SendableBox(AXUIElementCreateApplication(getpid()))
        var range = CFRange(location: 3, length: 5)
        let rangeValue = SendableBox(try! XCTUnwrap(AXValueCreate(.cfRange, &range)))
        let reader = AccessibilitySelectionReader(
            isAccessibilityTrusted: { true },
            focusedElementProvider: { element.value },
            attributeValueProvider: { _, attribute in
                if attribute as String == kAXSelectedTextRangeAttribute as String {
                    return rangeValue.value
                }
                return nil
            },
            parameterizedAttributeValueProvider: { _, attribute, _ in
                if attribute as String == kAXStringForRangeParameterizedAttribute as String {
                    return "range text" as CFTypeRef
                }
                return nil
            }
        )

        XCTAssertEqual(reader.readSelectedText(), "range text")
    }

    func testReaderIgnoresWhitespaceSelections() {
        let element = SendableBox(AXUIElementCreateApplication(getpid()))
        let reader = AccessibilitySelectionReader(
            isAccessibilityTrusted: { true },
            focusedElementProvider: { element.value },
            attributeValueProvider: { _, attribute in
                if attribute as String == kAXSelectedTextAttribute as String {
                    return "   " as CFTypeRef
                }
                return nil
            },
            parameterizedAttributeValueProvider: { _, _, _ in nil }
        )

        XCTAssertNil(reader.readSelectedText())
    }

    func testDetectorDelegatesToReader() async {
        let detector = AccessibilitySelectionDetector(reader: MockFocusedSelectionReader(selectedText: "Editable"))

        let selectedText = await detector.detectSelectedText()

        XCTAssertEqual(selectedText, "Editable")
    }
}

private struct MockFocusedSelectionReader: FocusedSelectionReading {
    let selectedText: String?

    func readSelectedText() -> String? {
        selectedText
    }
}

private final class SendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}
