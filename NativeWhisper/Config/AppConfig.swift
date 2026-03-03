import Foundation

struct AppConfig {
    private let keyProvider: @Sendable () -> String
    let model: String
    let language: String

    init(
        openAIKey: String,
        model: String,
        language: String
    ) {
        self.keyProvider = { openAIKey }
        self.model = model
        self.language = language
    }

    init(
        keyProvider: @escaping @Sendable () -> String,
        model: String,
        language: String
    ) {
        self.keyProvider = keyProvider
        self.model = model
        self.language = language
    }

    var openAIKey: String {
        keyProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        return !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(apiKeyStore: APIKeyProviding = APIKeyStore.shared) -> AppConfig {
        return AppConfig(
            keyProvider: {
                apiKeyStore.currentAPIKey()
            },
            model: "gpt-4o-mini-transcribe",
            language: "en"
        )
    }
}
