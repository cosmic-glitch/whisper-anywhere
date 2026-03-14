import Foundation

enum TranscriptionProvider: String, CaseIterable {
    case openAI = "openai"
    case deepgram = "deepgram"
}

struct AppConfig {
    private let keyProvider: @Sendable () -> String
    private let deepgramKeyProvider: @Sendable () -> String
    let model: String
    let language: String
    let backendBaseURL: URL?
    let provider: TranscriptionProvider

    init(
        openAIKey: String,
        model: String,
        language: String,
        backendBaseURL: URL? = URL(string: "https://whisperanywhere.app"),
        provider: TranscriptionProvider = .openAI,
        deepgramKeyProvider: @escaping @Sendable () -> String = { DeepgramKeyStore.shared.currentDeepgramKey() }
    ) {
        self.keyProvider = { openAIKey }
        self.deepgramKeyProvider = deepgramKeyProvider
        self.model = model
        self.language = language
        self.backendBaseURL = backendBaseURL
        self.provider = provider
    }

    init(
        keyProvider: @escaping @Sendable () -> String,
        model: String,
        language: String,
        backendBaseURL: URL? = URL(string: "https://whisperanywhere.app"),
        provider: TranscriptionProvider = .openAI,
        deepgramKeyProvider: @escaping @Sendable () -> String = { DeepgramKeyStore.shared.currentDeepgramKey() }
    ) {
        self.keyProvider = keyProvider
        self.deepgramKeyProvider = deepgramKeyProvider
        self.model = model
        self.language = language
        self.backendBaseURL = backendBaseURL
        self.provider = provider
    }

    var openAIKey: String {
        keyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var deepgramKey: String {
        deepgramKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        return !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasActiveProviderKey: Bool {
        switch provider {
        case .openAI:
            return !openAIKey.isEmpty
        case .deepgram:
            return !deepgramKey.isEmpty
        }
    }

    static func load(
        apiKeyStore: APIKeyProviding = InMemoryAPIKeyProvider.shared,
        provider: TranscriptionProvider = .openAI,
        deepgramKeyStore: DeepgramKeyProviding = DeepgramKeyStore.shared
    ) -> AppConfig {
        return AppConfig(
            keyProvider: {
                apiKeyStore.currentAPIKey()
            },
            model: "gpt-4o-mini-transcribe",
            language: "en",
            provider: provider,
            deepgramKeyProvider: {
                deepgramKeyStore.currentDeepgramKey()
            }
        )
    }
}
