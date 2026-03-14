import AVFoundation
import Foundation

final class StreamingAudioCaptureService: AudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var continuation: AsyncStream<Data>.Continuation?
    private var latestLevel: Float = 0

    private let targetSampleRate: Double = 16_000
    private let bufferSize: AVAudioFrameCount = 4096

    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard engine == nil else {
            throw AudioCaptureError.alreadyRecording
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperanywhere-stream-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let file = try AVAudioFile(
            forWriting: url,
            settings: targetFormat.settings,
            commonFormat: targetFormat.commonFormat,
            interleaved: true
        )

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.failedToStart
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let level = self.computeLevel(from: buffer)
            self.lock.lock()
            self.latestLevel = level
            self.lock.unlock()

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (self.targetSampleRate / inputFormat.sampleRate)
            )
            guard frameCapacity > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil, convertedBuffer.frameLength > 0 else {
                return
            }

            try? file.write(from: convertedBuffer)

            let data = self.pcmBufferToData(convertedBuffer)
            self.lock.lock()
            let cont = self.continuation
            self.lock.unlock()
            cont?.yield(data)
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.audioFile = file
        self.currentURL = url
    }

    func stop() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        guard let engine, let url = currentURL else {
            throw AudioCaptureError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        continuation?.finish()
        continuation = nil

        self.engine = nil
        self.audioFile = nil
        self.currentURL = nil
        self.latestLevel = 0

        return url
    }

    func currentNormalizedInputLevel() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        guard engine != nil else { return nil }
        return latestLevel
    }

    func pcmChunkStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func computeLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let samples = channelData[0]
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sumOfSquares: Float = 0
        var peak: Float = 0

        for i in 0..<count {
            let sample = abs(samples[i])
            sumOfSquares += sample * sample
            if sample > peak { peak = sample }
        }

        let rms = sqrt(sumOfSquares / Float(count))
        let rmsDB = 20 * log10(max(rms, 1e-10))
        let peakDB = 20 * log10(max(peak, 1e-10))

        let rmsNorm = normalizeDecibels(rmsDB)
        let peakNorm = normalizeDecibels(peakDB)
        return min(max((0.55 * rmsNorm) + (0.45 * peakNorm), 0), 1)
    }

    private func normalizeDecibels(_ power: Float) -> Float {
        let minDecibels: Float = -50
        let clamped = max(power, minDecibels)
        return (clamped - minDecibels) / abs(minDecibels)
    }

    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: buffer.int16ChannelData![0], count: byteCount)
    }
}
