import Foundation

protocol APIKeyProviding: Sendable {
    func currentAPIKey() -> String
}

protocol APIKeyStoring: APIKeyProviding {
    func saveAPIKey(_ value: String)
}

final class APIKeyStore: APIKeyStoring, @unchecked Sendable {
    static let shared = APIKeyStore()

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let fallbackEnvironmentKey: String
    private let fallbackEnvironment: [String: String]
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "NativeWhisper.OpenAIAPIKey",
        fallbackEnvironmentKey: String = "OPENAI_API_KEY",
        fallbackEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.fallbackEnvironmentKey = fallbackEnvironmentKey
        self.fallbackEnvironment = fallbackEnvironment
    }

    func currentAPIKey() -> String {
        lock.lock()
        defer { lock.unlock() }

        let stored = (defaults.string(forKey: defaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !stored.isEmpty {
            return stored
        }

        return (fallbackEnvironment[fallbackEnvironmentKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        defaults.set(trimmed, forKey: defaultsKey)
        lock.unlock()
    }
}
