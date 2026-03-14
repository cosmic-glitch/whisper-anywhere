import Foundation
import OSLog

enum StreamingTranscriptEvent: Sendable {
    case partial(String)
    case final_(String)
}

protocol StreamingTranscribing: Sendable {
    func transcribeStream(audioChunks: AsyncStream<Data>) -> AsyncStream<StreamingTranscriptEvent>
    func finalize() async throws -> String
}

enum DeepgramTranscriptionError: LocalizedError, Equatable {
    case invalidAPIKey
    case connectionFailed(String)
    case httpError(statusCode: Int, message: String)
    case decodingFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Deepgram API key is not configured."
        case .connectionFailed(let details):
            return "Deepgram connection failed: \(details)"
        case .httpError(let statusCode, let message):
            return "Deepgram error (\(statusCode)): \(message)"
        case .decodingFailed:
            return "Failed to decode Deepgram response."
        case .emptyTranscript:
            return "Deepgram returned an empty transcript."
        }
    }
}

final class DeepgramStreamingClient: StreamingTranscribing, @unchecked Sendable {
    private let logger = Logger(subsystem: "ai.whisperanywhere.app", category: "DeepgramStreamingClient")
    private let keyProvider: DeepgramKeyProviding

    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var sendTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var accumulatedTranscript: String = ""
    private var eventContinuation: AsyncStream<StreamingTranscriptEvent>.Continuation?
    private var isFinalized = false

    init(keyProvider: DeepgramKeyProviding) {
        self.keyProvider = keyProvider
    }

    func transcribeStream(audioChunks: AsyncStream<Data>) -> AsyncStream<StreamingTranscriptEvent> {
        lock.lock()
        accumulatedTranscript = ""
        isFinalized = false
        lock.unlock()

        let apiKey = keyProvider.currentDeepgramKey()

        var urlComponents = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        urlComponents.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()

        lock.lock()
        webSocketTask = wsTask
        lock.unlock()

        logger.info("Deepgram WebSocket connection opened")

        return AsyncStream { continuation in
            self.lock.lock()
            self.eventContinuation = continuation
            self.lock.unlock()

            self.sendTask = Task { [weak self] in
                guard let self else { return }
                for await chunk in audioChunks {
                    guard !Task.isCancelled else { break }
                    do {
                        try await wsTask.send(.data(chunk))
                    } catch {
                        self.logger.error("Failed to send audio chunk: \(error.localizedDescription)")
                        break
                    }
                }
            }

            self.keepAliveTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { break }
                    let keepAlive = "{\"type\": \"KeepAlive\"}"
                    try? await wsTask.send(.string(keepAlive))
                }
            }

            self.receiveTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do {
                        let message = try await wsTask.receive()
                        switch message {
                        case .string(let text):
                            self.handleResponseText(text, continuation: continuation)
                        case .data(let data):
                            if let text = String(data: data, encoding: .utf8) {
                                self.handleResponseText(text, continuation: continuation)
                            }
                        @unknown default:
                            break
                        }
                    } catch {
                        self.logger.info("WebSocket receive ended: \(error.localizedDescription)")
                        break
                    }
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.cancelTasks()
            }
        }
    }

    func finalize() async throws -> String {
        let (alreadyFinalized, existingTranscript, wsTask) = markFinalized()

        if alreadyFinalized {
            return existingTranscript
        }

        if let wsTask {
            let closeMessage = "{\"type\": \"CloseStream\"}"
            try? await wsTask.send(.string(closeMessage))
            logger.info("Sent CloseStream message")

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        cancelTasks()

        let transcript = getAccumulatedTranscript()

        guard !transcript.isEmpty else {
            throw DeepgramTranscriptionError.emptyTranscript
        }

        logger.info("Finalized transcript: \(transcript.count) chars")
        return transcript
    }

    private func markFinalized() -> (alreadyFinalized: Bool, transcript: String, wsTask: URLSessionWebSocketTask?) {
        lock.lock()
        defer { lock.unlock() }
        if isFinalized {
            return (true, accumulatedTranscript, nil)
        }
        isFinalized = true
        return (false, "", webSocketTask)
    }

    private func getAccumulatedTranscript() -> String {
        lock.lock()
        defer { lock.unlock() }
        return accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleResponseText(_ text: String, continuation: AsyncStream<StreamingTranscriptEvent>.Continuation) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            guard response.type == "Results" else { return }

            let transcript = response.channel.alternatives.first?.transcript ?? ""
            guard !transcript.isEmpty else { return }

            if response.is_final {
                lock.lock()
                if !accumulatedTranscript.isEmpty {
                    accumulatedTranscript += " "
                }
                accumulatedTranscript += transcript
                lock.unlock()

                continuation.yield(.final_(transcript))
                logger.debug("Final segment: \(transcript)")
            } else {
                continuation.yield(.partial(transcript))
            }
        } catch {
            logger.error("Failed to decode Deepgram response: \(error.localizedDescription)")
        }
    }

    private func cancelTasks() {
        sendTask?.cancel()
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        sendTask = nil
        receiveTask = nil
        keepAliveTask = nil

        lock.lock()
        let wsTask = webSocketTask
        let cont = eventContinuation
        webSocketTask = nil
        eventContinuation = nil
        lock.unlock()

        wsTask?.cancel(with: .normalClosure, reason: nil)
        cont?.finish()
    }
}

struct DeepgramResponse: Decodable {
    let type: String
    let channel: Channel
    let is_final: Bool
    let speech_final: Bool

    struct Channel: Decodable {
        let alternatives: [Alternative]
    }

    struct Alternative: Decodable {
        let transcript: String
    }
}
