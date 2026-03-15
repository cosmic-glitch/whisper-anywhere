@preconcurrency import ApplicationServices
import CoreFoundation
import Foundation
import OSLog

protocol SelectionDetecting: Sendable {
    func detectSelectedText() async -> String?
}

struct NoSelectionDetector: SelectionDetecting {
    func detectSelectedText() async -> String? {
        nil
    }
}

protocol FocusedSelectionReading: Sendable {
    func readSelectedText() -> String?
}

struct AccessibilitySelectionReader: FocusedSelectionReading {
    typealias AccessibilityTrustedProvider = @Sendable () -> Bool
    typealias FocusedElementProvider = @Sendable () -> AXUIElement?
    typealias AttributeValueProvider = @Sendable (AXUIElement, CFString) -> CFTypeRef?
    typealias ParameterizedAttributeValueProvider = @Sendable (AXUIElement, CFString, CFTypeRef) -> CFTypeRef?

    private let logger = Logger(subsystem: "ai.whisperanywhere.app", category: "SelectionDetector")
    private let isAccessibilityTrusted: AccessibilityTrustedProvider
    private let focusedElementProvider: FocusedElementProvider
    private let attributeValueProvider: AttributeValueProvider
    private let parameterizedAttributeValueProvider: ParameterizedAttributeValueProvider

    init(
        isAccessibilityTrusted: @escaping AccessibilityTrustedProvider = { AXIsProcessTrusted() },
        focusedElementProvider: @escaping FocusedElementProvider = AccessibilitySelectionReader.defaultFocusedElement,
        attributeValueProvider: @escaping AttributeValueProvider = AccessibilitySelectionReader.defaultAttributeValue,
        parameterizedAttributeValueProvider: @escaping ParameterizedAttributeValueProvider = AccessibilitySelectionReader.defaultParameterizedAttributeValue
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.focusedElementProvider = focusedElementProvider
        self.attributeValueProvider = attributeValueProvider
        self.parameterizedAttributeValueProvider = parameterizedAttributeValueProvider
    }

    func readSelectedText() -> String? {
        guard isAccessibilityTrusted() else {
            logger.error("Selection detection skipped: Accessibility trust unavailable")
            return nil
        }

        guard let focusedElement = focusedElementProvider() else {
            logger.info("Selection detection: no focused accessibility element")
            return nil
        }

        if let selectedText = selectedTextAttribute(for: focusedElement) {
            logger.info("Selection detection succeeded via AXSelectedText selectedChars=\(selectedText.count, privacy: .public)")
            return selectedText
        }

        if let selectedText = selectedTextFromRange(for: focusedElement) {
            logger.info("Selection detection succeeded via selected text range selectedChars=\(selectedText.count, privacy: .public)")
            return selectedText
        }

        logger.info("Selection detection: focused element exposed no selected text")
        return nil
    }

    private static func defaultFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard status == .success,
              let focusedObject,
              CFGetTypeID(focusedObject) == AXUIElementGetTypeID() else {
            return nil
        }

        return (focusedObject as! AXUIElement)
    }

    private static func defaultAttributeValue(for element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else {
            return nil
        }
        return value
    }

    private static func defaultParameterizedAttributeValue(for element: AXUIElement, attribute: CFString, parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
        guard status == .success else {
            return nil
        }
        return value
    }

    private func selectedTextAttribute(for element: AXUIElement) -> String? {
        guard let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, element: element),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return selectedText
    }

    private func selectedTextFromRange(for element: AXUIElement) -> String? {
        guard let selectedRange = selectedTextRange(for: element),
              selectedRange.length > 0 else {
            return nil
        }

        var mutableRange = selectedRange
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        guard let value = parameterizedAttributeValueProvider(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue
        ),
              CFGetTypeID(value) == CFStringGetTypeID(),
              let selectedText = value as? String,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return selectedText
    }

    private func stringAttribute(_ attribute: CFString, element: AXUIElement) -> String? {
        guard let value = attributeValueProvider(element, attribute),
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }

        return value as? String
    }

    private func selectedTextRange(for element: AXUIElement) -> CFRange? {
        guard let value = attributeValueProvider(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &selectedRange) else {
            return nil
        }

        return selectedRange
    }
}

final class AccessibilitySelectionDetector: SelectionDetecting, @unchecked Sendable {
    private let reader: any FocusedSelectionReading

    init(reader: any FocusedSelectionReading = AccessibilitySelectionReader()) {
        self.reader = reader
    }

    func detectSelectedText() async -> String? {
        reader.readSelectedText()
    }
}
