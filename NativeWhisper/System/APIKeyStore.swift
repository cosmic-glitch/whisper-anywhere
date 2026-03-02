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
    private let legacyDefaultsKey: String
    private let currentBundleIdentifier: String
    private let legacyBundleIdentifier: String
    private let fallbackEnvironmentKey: String
    private let fallbackEnvironment: [String: String]
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "WhisperAnywhere.OpenAIAPIKey",
        legacyDefaultsKey: String = "NativeWhisper.OpenAIAPIKey",
        currentBundleIdentifier: String = "ai.whisperanywhere.app",
        legacyBundleIdentifier: String = "ai.nativewhisper.app",
        fallbackEnvironmentKey: String = "OPENAI_API_KEY",
        fallbackEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.legacyDefaultsKey = legacyDefaultsKey
        self.currentBundleIdentifier = currentBundleIdentifier
        self.legacyBundleIdentifier = legacyBundleIdentifier
        self.fallbackEnvironmentKey = fallbackEnvironmentKey
        self.fallbackEnvironment = fallbackEnvironment
    }

    func currentAPIKey() -> String {
        lock.lock()
        defer { lock.unlock() }

        migrateStoredAPIKeyIfNeededLocked()

        let stored = normalized(defaults.string(forKey: defaultsKey))

        if !stored.isEmpty {
            return stored
        }

        return normalized(fallbackEnvironment[fallbackEnvironmentKey])
    }

    func saveAPIKey(_ value: String) {
        let trimmed = normalized(value)

        lock.lock()
        defaults.set(trimmed, forKey: defaultsKey)
        defaults.set(trimmed, forKey: legacyDefaultsKey)
        lock.unlock()
    }

    private func migrateStoredAPIKeyIfNeededLocked() {
        let current = normalized(defaults.string(forKey: defaultsKey))
        if !current.isEmpty {
            return
        }

        let legacyInCurrentDomain = normalized(defaults.string(forKey: legacyDefaultsKey))
        if !legacyInCurrentDomain.isEmpty {
            defaults.set(legacyInCurrentDomain, forKey: defaultsKey)
            return
        }

        for domain in [legacyBundleIdentifier, currentBundleIdentifier] {
            guard let suiteDefaults = UserDefaults(suiteName: domain) else {
                continue
            }

            for key in [legacyDefaultsKey, defaultsKey] {
                let candidate = normalized(suiteDefaults.string(forKey: key))
                if !candidate.isEmpty {
                    defaults.set(candidate, forKey: defaultsKey)
                    defaults.set(candidate, forKey: legacyDefaultsKey)
                    return
                }
            }
        }
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
