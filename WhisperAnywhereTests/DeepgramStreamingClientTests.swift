import Foundation
import XCTest
@testable import WhisperAnywhere

final class DeepgramStreamingClientTests: XCTestCase {
    func testDeepgramResponseParsesPartialResult() throws {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": [
                    {"transcript": "hello"}
                ]
            },
            "is_final": false,
            "speech_final": false
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        XCTAssertEqual(response.type, "Results")
        XCTAssertFalse(response.is_final)
        XCTAssertFalse(response.speech_final)
        XCTAssertEqual(response.channel.alternatives.first?.transcript, "hello")
    }

    func testDeepgramResponseParsesFinalResult() throws {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": [
                    {"transcript": "hello world"}
                ]
            },
            "is_final": true,
            "speech_final": true
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        XCTAssertTrue(response.is_final)
        XCTAssertTrue(response.speech_final)
        XCTAssertEqual(response.channel.alternatives.first?.transcript, "hello world")
    }

    func testDeepgramResponseParsesEmptyAlternatives() throws {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": []
            },
            "is_final": false,
            "speech_final": false
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        XCTAssertTrue(response.channel.alternatives.isEmpty)
    }

    func testDeepgramTranscriptionErrorDescriptions() {
        XCTAssertEqual(
            DeepgramTranscriptionError.invalidAPIKey.localizedDescription,
            "Deepgram API key is not configured."
        )
        XCTAssertEqual(
            DeepgramTranscriptionError.emptyTranscript.localizedDescription,
            "Deepgram returned an empty transcript."
        )
        XCTAssertEqual(
            DeepgramTranscriptionError.connectionFailed("timeout").localizedDescription,
            "Deepgram connection failed: timeout"
        )
        XCTAssertEqual(
            DeepgramTranscriptionError.httpError(statusCode: 401, message: "Unauthorized").localizedDescription,
            "Deepgram error (401): Unauthorized"
        )
        XCTAssertEqual(
            DeepgramTranscriptionError.decodingFailed.localizedDescription,
            "Failed to decode Deepgram response."
        )
    }

    func testDeepgramKeyStoreReturnsEmptyByDefault() {
        let store = DeepgramKeyStore()
        store.clearDeepgramKey()
        XCTAssertEqual(store.currentDeepgramKey(), "")
    }

    func testDeepgramKeyStoreSetAndRetrieve() {
        let store = DeepgramKeyStore()
        store.setDeepgramKey("custom-key-123")
        XCTAssertEqual(store.currentDeepgramKey(), "custom-key-123")
        store.clearDeepgramKey()
    }

    func testDeepgramKeyStoreTrimsWhitespace() {
        let store = DeepgramKeyStore()
        store.setDeepgramKey("  key-with-spaces  \n")
        XCTAssertEqual(store.currentDeepgramKey(), "key-with-spaces")
        store.clearDeepgramKey()
    }

    func testDeepgramKeyStoreClear() {
        let store = DeepgramKeyStore()
        store.setDeepgramKey("some-key")
        store.clearDeepgramKey()
        XCTAssertEqual(store.currentDeepgramKey(), "")
    }

    func testTranscriptionProviderEnum() {
        XCTAssertEqual(TranscriptionProvider.openAI.rawValue, "openai")
        XCTAssertEqual(TranscriptionProvider.deepgram.rawValue, "deepgram")
        XCTAssertEqual(TranscriptionProvider(rawValue: "openai"), .openAI)
        XCTAssertEqual(TranscriptionProvider(rawValue: "deepgram"), .deepgram)
        XCTAssertNil(TranscriptionProvider(rawValue: "invalid"))
    }

    func testAppConfigHasActiveProviderKeyOpenAI() {
        let config = AppConfig(openAIKey: "sk-test", model: "whisper-1", language: "en", provider: .openAI)
        XCTAssertTrue(config.hasActiveProviderKey)

        let emptyConfig = AppConfig(openAIKey: "", model: "whisper-1", language: "en", provider: .openAI)
        XCTAssertFalse(emptyConfig.hasActiveProviderKey)
    }

    func testAppConfigHasActiveProviderKeyDeepgram() {
        let config = AppConfig(
            openAIKey: "",
            model: "whisper-1",
            language: "en",
            provider: .deepgram,
            deepgramKeyProvider: { "dg-key" }
        )
        XCTAssertTrue(config.hasActiveProviderKey)

        let emptyConfig = AppConfig(
            openAIKey: "",
            model: "whisper-1",
            language: "en",
            provider: .deepgram,
            deepgramKeyProvider: { "" }
        )
        XCTAssertFalse(emptyConfig.hasActiveProviderKey)
    }

}
