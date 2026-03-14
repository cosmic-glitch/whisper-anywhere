import Foundation

protocol DeepgramKeyProviding: Sendable {
    func currentDeepgramKey() -> String
}

final class DeepgramKeyStore: DeepgramKeyProviding, @unchecked Sendable {
    static let shared = DeepgramKeyStore()

    private let lock = NSLock()
    private var key: String = ""

    func currentDeepgramKey() -> String {
        lock.lock()
        defer { lock.unlock() }
        return key
    }

    func setDeepgramKey(_ value: String) {
        lock.lock()
        key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
    }

    func clearDeepgramKey() {
        lock.lock()
        key = ""
        lock.unlock()
    }
}
