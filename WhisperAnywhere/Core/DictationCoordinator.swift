import Foundation
import OSLog

enum RecordingSessionMode: Equatable {
    case dictation
    case editCommand
}

private enum RecordingSessionContext {
    case dictation
    case editCommand(selectedText: String)
}

enum DictationState: Equatable {
    case idle
    case recording(Date, RecordingSessionMode)
    case transcribing
    case editing
    case inserting
    case error(String)
}

enum DictationEvent: Equatable {
    case clipboardFallbackNotice(String)
}

enum DictationError: LocalizedError {
    case missingAPIKey
    case permissionDenied(String)
    case audioFailure(String)
    case apiFailure(String)
    case insertionFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is missing."
        case .permissionDenied(let details):
            return "Permission denied: \(details)"
        case .audioFailure(let details):
            return "Audio error: \(details)"
        case .apiFailure(let details):
            return "API error: \(details)"
        case .insertionFailure(let details):
            return "Insertion error: \(details)"
        }
    }
}

actor DictationCoordinator {
    private let logger = Logger(subsystem: "ai.whisperanywhere.app", category: "DictationCoordinator")
    private let audioCapture: AudioCapturing
    private let transcriptionClient: Transcribing
    private let transcriptionLogStore: TranscriptionLogPersisting
    private let textEditor: TextEditing
    private let textInserter: TextInserting
    private let clipboard: ClipboardWriting
    private let selectionDetector: SelectionDetecting
    private let permissionService: PermissionProviding
    private let notifier: Notifying
    private let config: AppConfig
    private let minimumPressDuration: TimeInterval
    private let errorDisplayDuration: UInt64
    private let stateDidChange: @Sendable (DictationState) async -> Void
    private let eventDidOccur: @Sendable (DictationEvent) async -> Void

    private let streamingAudioCapture: StreamingAudioCaptureService?
    private let streamingClient: StreamingTranscribing?
    private let transcriptDidUpdate: (@Sendable (String) async -> Void)?

    private var state: DictationState = .idle
    private var recordingURL: URL?
    private var sessionContext: RecordingSessionContext = .dictation
    private var streamingEventTask: Task<Void, Never>?

    init(
        audioCapture: AudioCapturing,
        transcriptionClient: Transcribing,
        transcriptionLogStore: TranscriptionLogPersisting = NoopTranscriptionLogStore(),
        textEditor: TextEditing = NoopTextEditor(),
        textInserter: TextInserting,
        clipboard: ClipboardWriting,
        selectionDetector: SelectionDetecting = NoSelectionDetector(),
        permissionService: PermissionProviding,
        notifier: Notifying,
        config: AppConfig,
        minimumPressDuration: TimeInterval = 0.15,
        errorDisplayDuration: UInt64 = 1_200_000_000,
        stateDidChange: @escaping @Sendable (DictationState) async -> Void,
        eventDidOccur: @escaping @Sendable (DictationEvent) async -> Void = { _ in },
        streamingAudioCapture: StreamingAudioCaptureService? = nil,
        streamingClient: StreamingTranscribing? = nil,
        transcriptDidUpdate: (@Sendable (String) async -> Void)? = nil
    ) {
        self.audioCapture = audioCapture
        self.transcriptionClient = transcriptionClient
        self.transcriptionLogStore = transcriptionLogStore
        self.textEditor = textEditor
        self.textInserter = textInserter
        self.clipboard = clipboard
        self.selectionDetector = selectionDetector
        self.permissionService = permissionService
        self.notifier = notifier
        self.config = config
        self.minimumPressDuration = minimumPressDuration
        self.errorDisplayDuration = errorDisplayDuration
        self.stateDidChange = stateDidChange
        self.eventDidOccur = eventDidOccur
        self.streamingAudioCapture = streamingAudioCapture
        self.streamingClient = streamingClient
        self.transcriptDidUpdate = transcriptDidUpdate
    }

    func currentState() -> DictationState {
        state
    }

    func handleFnPressed() async {
        guard case .idle = state else {
            return
        }

        do {
            try await ensureReadyToRecord()
            sessionContext = await resolvedSessionContext()

            if let streamingAudioCapture, let streamingClient {
                try streamingAudioCapture.start()
                let pcmStream = streamingAudioCapture.pcmChunkStream()
                let eventStream = streamingClient.transcribeStream(audioChunks: pcmStream)

                streamingEventTask = Task { [weak self, transcriptDidUpdate] in
                    for await event in eventStream {
                        guard !Task.isCancelled else { break }
                        switch event {
                        case .partial(let text):
                            await transcriptDidUpdate?(text)
                        case .final_(let text):
                            await transcriptDidUpdate?(text)
                        }
                    }
                }

                await setState(.recording(Date(), modeForSessionContext(sessionContext)))
                logger.info("Fn pressed: started streaming recording session mode=\(String(describing: self.modeForSessionContext(self.sessionContext)), privacy: .public)")
            } else {
                try audioCapture.start()
                await setState(.recording(Date(), modeForSessionContext(sessionContext)))
                logger.info("Fn pressed: started recording session mode=\(String(describing: self.modeForSessionContext(self.sessionContext)), privacy: .public)")
            }
        } catch let error as DictationError {
            sessionContext = .dictation
            logger.error("Fn pressed: failed before recording error=\(error.localizedDescription, privacy: .public)")
            await transitionToError(error)
        } catch {
            sessionContext = .dictation
            logger.error("Fn pressed: unexpected failure before recording error=\(error.localizedDescription, privacy: .public)")
            await transitionToError(.audioFailure(error.localizedDescription))
        }
    }

    func handleFnReleased() async {
        guard case .recording(let startedAt, _) = state else {
            return
        }

        let activeSession = sessionContext

        do {
            if let streamingAudioCapture, let streamingClient {
                let audioURL = try streamingAudioCapture.stop()
                recordingURL = audioURL
                logger.info("Fn released: stopped streaming recording session=\(String(describing: self.modeForSessionContext(activeSession)), privacy: .public)")

                streamingEventTask?.cancel()
                streamingEventTask = nil

                let pressDuration = Date().timeIntervalSince(startedAt)
                guard pressDuration >= minimumPressDuration else {
                    try? FileManager.default.removeItem(at: audioURL)
                    recordingURL = nil
                    sessionContext = .dictation
                    await setState(.idle)
                    return
                }

                await setState(.transcribing)
                let transcriptionStartedAt = ContinuousClock.now
                let transcript: String
                do {
                    transcript = try await streamingClient.finalize()
                } catch {
                    let elapsed = durationMilliseconds(since: transcriptionStartedAt)
                    transcriptionLogStore.persistFailure(errorDescription: error.localizedDescription, durationMs: elapsed)
                    logger.error("Streaming transcription finalize failed durationMs=\(elapsed, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    throw error
                }
                let transcriptionElapsed = durationMilliseconds(since: transcriptionStartedAt)
                transcriptionLogStore.persistSuccess(transcript: transcript, durationMs: transcriptionElapsed)
                logger.info("Streaming transcription finalized durationMs=\(transcriptionElapsed, privacy: .public)")
                logger.info("Streaming transcription complete transcriptChars=\(transcript.count, privacy: .public)")
                let insertionText = await resolveInsertionText(transcript: transcript, session: activeSession)

                await setState(.inserting)
                await insertOrFallback(insertionText)

                try? FileManager.default.removeItem(at: audioURL)
                recordingURL = nil
                sessionContext = .dictation
                await setState(.idle)
            } else {
                let audioURL = try audioCapture.stop()
                recordingURL = audioURL
                logger.info("Fn released: stopped recording session=\(String(describing: self.modeForSessionContext(activeSession)), privacy: .public)")

                let pressDuration = Date().timeIntervalSince(startedAt)
                guard pressDuration >= minimumPressDuration else {
                    try? FileManager.default.removeItem(at: audioURL)
                    recordingURL = nil
                    sessionContext = .dictation
                    await setState(.idle)
                    return
                }

                await setState(.transcribing)
                let transcriptionStartedAt = ContinuousClock.now
                let transcript: String
                do {
                    transcript = try await transcriptionClient.transcribe(audioURL: audioURL)
                } catch {
                    let elapsed = durationMilliseconds(since: transcriptionStartedAt)
                    transcriptionLogStore.persistFailure(errorDescription: error.localizedDescription, durationMs: elapsed)
                    logger.error("Transcription call failed durationMs=\(elapsed, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    throw error
                }
                let transcriptionElapsed = durationMilliseconds(since: transcriptionStartedAt)
                transcriptionLogStore.persistSuccess(transcript: transcript, durationMs: transcriptionElapsed)
                logger.info("Transcription call succeeded durationMs=\(transcriptionElapsed, privacy: .public)")
                logger.info("Transcription complete transcriptChars=\(transcript.count, privacy: .public)")
                let insertionText = await resolveInsertionText(transcript: transcript, session: activeSession)

                await setState(.inserting)
                await insertOrFallback(insertionText)

                try? FileManager.default.removeItem(at: audioURL)
                recordingURL = nil
                sessionContext = .dictation
                await setState(.idle)
            }
        } catch let error as DictationError {
            sessionContext = .dictation
            logger.error("Fn released: dictation pipeline failed error=\(error.localizedDescription, privacy: .public)")
            await cleanupRecordingURL()
            await transitionToError(error)
        } catch {
            sessionContext = .dictation
            await cleanupRecordingURL()
            let mapped = mapError(error)
            logger.error("Fn released: unexpected pipeline failure mappedError=\(mapped.localizedDescription, privacy: .public)")
            await transitionToError(mapped)
        }
    }

    private func ensureReadyToRecord() async throws {
        guard config.hasActiveProviderKey else {
            throw DictationError.missingAPIKey
        }

        let snapshot = permissionService.snapshot()

        if snapshot.microphone != .granted {
            let granted = await permissionService.requestMicrophoneAccess()
            guard granted else {
                throw DictationError.permissionDenied("Microphone access is required.")
            }
        }

        if snapshot.accessibility != .granted {
            let granted = permissionService.requestAccessibilityAccess()
            guard granted else {
                throw DictationError.permissionDenied("Accessibility access is required for text insertion.")
            }
        }

        if snapshot.inputMonitoring != .granted {
            let granted = permissionService.requestInputMonitoringAccess()
            guard granted else {
                throw DictationError.permissionDenied("Input Monitoring access is required for Fn detection.")
            }
        }
    }

    private func mapError(_ error: Error) -> DictationError {
        if let audioError = error as? AudioCaptureError {
            return .audioFailure(audioError.localizedDescription)
        }

        if let insertionError = error as? TextInsertionServiceError {
            return .insertionFailure(insertionError.localizedDescription)
        }

        if let apiError = error as? OpenAITranscriptionError {
            return .apiFailure(apiError.localizedDescription)
        }

        if let editError = error as? OpenAIEditError {
            return .apiFailure(editError.localizedDescription)
        }

        if let deepgramError = error as? DeepgramTranscriptionError {
            return .apiFailure(deepgramError.localizedDescription)
        }

        return .apiFailure(error.localizedDescription)
    }

    private func cleanupRecordingURL() async {
        guard let recordingURL else {
            return
        }
        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
    }

    private func transitionToError(_ error: DictationError) async {
        let message = error.localizedDescription
        await setState(.error(message))

        switch error {
        case .missingAPIKey:
            notifier.notify(title: "Whisper Anywhere Error", body: "OPENAI_API_KEY is not configured.")
        default:
            notifier.notify(title: "Whisper Anywhere Error", body: message)
        }

        if errorDisplayDuration > 0 {
            try? await Task.sleep(nanoseconds: errorDisplayDuration)
        }

        sessionContext = .dictation
        await setState(.idle)
    }

    private func resolvedSessionContext() async -> RecordingSessionContext {
        guard let selectedText = await selectionDetector.detectSelectedText(),
              !selectedText.isEmpty else {
            logger.info("Selection detection: no selected text, using dictation mode")
            return .dictation
        }
        logger.info("Selection detection: selectedChars=\(selectedText.count, privacy: .public), using edit mode")
        return .editCommand(selectedText: selectedText)
    }

    private func modeForSessionContext(_ context: RecordingSessionContext) -> RecordingSessionMode {
        switch context {
        case .dictation:
            return .dictation
        case .editCommand:
            return .editCommand
        }
    }

    private func resolveInsertionText(transcript: String, session: RecordingSessionContext) async -> String {
        switch session {
        case .dictation:
            return transcript
        case .editCommand(let selectedText):
            await setState(.editing)
            let editStartedAt = ContinuousClock.now
            do {
                logger.info("Edit mode: sending edit request selectedChars=\(selectedText.count, privacy: .public) instructionChars=\(transcript.count, privacy: .public)")
                let editedText = try await textEditor.edit(selectedText: selectedText, instructions: transcript)
                let elapsed = durationMilliseconds(since: editStartedAt)
                logger.info("Edit call succeeded durationMs=\(elapsed, privacy: .public) editedChars=\(editedText.count, privacy: .public)")
                return editedText
            } catch {
                let elapsed = durationMilliseconds(since: editStartedAt)
                logger.error("Edit mode: model call failed durationMs=\(elapsed, privacy: .public), reinserting original selection error=\(error.localizedDescription, privacy: .public)")
                return selectedText
            }
        }
    }

    private func insertOrFallback(_ text: String) async {
        do {
            try textInserter.insert(text)
        } catch {
            let fallbackMessage = "Could not insert text. Copied to clipboard."
            logger.error("Insertion failed. Falling back to clipboard chars=\(text.count, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            clipboard.copy(text)
            notifier.notify(
                title: "Whisper Anywhere",
                body: "Could not insert into the active field. Transcript copied to clipboard."
            )
            await eventDidOccur(.clipboardFallbackNotice(fallbackMessage))
        }
    }

    private func setState(_ newState: DictationState) async {
        state = newState
        await stateDidChange(newState)
    }

    private func durationMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        let components = duration.components
        let secondsInMilliseconds = Double(components.seconds) * 1_000
        let attosecondsInMilliseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsInMilliseconds + attosecondsInMilliseconds
    }
}
