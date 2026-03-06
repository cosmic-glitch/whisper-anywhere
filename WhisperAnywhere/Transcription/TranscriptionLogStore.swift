import Foundation
import OSLog

protocol TranscriptionLogPersisting: Sendable {
    func persistSuccess(transcript: String, durationMs: Double)
    func persistFailure(errorDescription: String, durationMs: Double)
}

struct NoopTranscriptionLogStore: TranscriptionLogPersisting {
    func persistSuccess(transcript: String, durationMs: Double) {}
    func persistFailure(errorDescription: String, durationMs: Double) {}
}

struct FileTranscriptionLogStore: TranscriptionLogPersisting {
    private static let logger = Logger(subsystem: "ai.whisperanywhere.app", category: "TranscriptionLogStore")

    private struct Entry: Encodable {
        let timestamp: String
        let status: String
        let durationMs: Double
        let transcript: String?
        let error: String?
    }

    private let logURL: URL

    init(
        logURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WhisperAnywhere/transcription.log")
    ) {
        self.logURL = logURL
    }

    func persistSuccess(transcript: String, durationMs: Double) {
        persist(
            Entry(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                status: "success",
                durationMs: durationMs,
                transcript: transcript,
                error: nil
            )
        )
    }

    func persistFailure(errorDescription: String, durationMs: Double) {
        persist(
            Entry(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                status: "failure",
                durationMs: durationMs,
                transcript: nil,
                error: errorDescription
            )
        )
    }

    private func persist(_ entry: Entry) {
        guard let entryData = formattedJSONData(for: entry) else {
            Self.logger.error("Transcription logging skipped: could not encode entry")
            return
        }

        do {
            let directoryURL = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: entryData)
                try handle.write(contentsOf: Data("\n\n".utf8))
            } else {
                var initialData = entryData
                initialData.append(Data("\n\n".utf8))
                try initialData.write(to: logURL, options: .atomic)
            }

            Self.logger.info(
                "Persisted transcription log status=\(entry.status, privacy: .public) durationMs=\(entry.durationMs, privacy: .public) path=\(logURL.path, privacy: .public)"
            )
        } catch {
            Self.logger.error("Failed to persist transcription log error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func formattedJSONData(for entry: Entry) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entry)
    }
}
