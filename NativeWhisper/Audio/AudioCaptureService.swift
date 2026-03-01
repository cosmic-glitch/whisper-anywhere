import Accelerate
import AVFoundation
import Foundation

protocol AudioCapturing: Sendable {
    func start() throws
    func stop() throws -> URL
    func currentNormalizedInputLevel() -> Float?
    func currentEqualizerBands() -> [Float]?
}

enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case notRecording
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Audio recording is already in progress."
        case .notRecording:
            return "Audio recording is not active."
        case .failedToStart:
            return "Failed to start audio recording."
        }
    }
}

private final class FFTBandAnalyzer {
    let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]
    private var sampleBuffer: [Float]
    private var adaptiveFloors: [Float]
    private var adaptiveCeilings: [Float]

    init?(fftSize: Int = 1024) {
        guard fftSize > 0, (fftSize & (fftSize - 1)) == 0 else {
            return nil
        }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return nil
        }

        self.fftSize = fftSize
        self.log2n = log2n
        self.fftSetup = setup
        self.window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        self.sampleBuffer = [Float](repeating: 0, count: fftSize)
        self.adaptiveFloors = [Float](repeating: -82, count: 5)
        self.adaptiveCeilings = [Float](repeating: -52, count: 5)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func bandLevels(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else {
            return [Float](repeating: 0, count: 5)
        }

        let sampleRate = Float(buffer.format.sampleRate)
        guard sampleRate > 0 else {
            return [Float](repeating: 0, count: 5)
        }

        let frameCount = min(Int(buffer.frameLength), fftSize)
        guard frameCount > 0 else {
            return [Float](repeating: 0, count: 5)
        }

        sampleBuffer = [Float](repeating: 0, count: fftSize)
        for index in 0 ..< frameCount {
            sampleBuffer[index] = channelData[index] * window[index]
        }

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        sampleBuffer.withUnsafeBufferPointer { samplePointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imag.withUnsafeMutableBufferPointer { imagPointer in
                    guard let sampleBase = samplePointer.baseAddress,
                          let realBase = realPointer.baseAddress,
                          let imagBase = imagPointer.baseAddress else {
                        return
                    }

                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)

                    sampleBase.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexBase in
                        vDSP_ctoz(complexBase, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }

                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        if !magnitudes.isEmpty {
            magnitudes[0] = 0
        }

        return computeBandLevels(from: magnitudes, sampleRate: sampleRate)
    }

    private func computeBandLevels(from magnitudes: [Float], sampleRate: Float) -> [Float] {
        // Human-speech-focused ranges (fundamental + formants + intelligibility).
        let bandEdges: [Float] = [90, 220, 450, 900, 1_800, 3_400]
        // Mild spectral-tilt compensation for higher speech bands.
        let bandGainOffsets: [Float] = [0.0, 0.5, 1.2, 2.0, 2.8]
        let binWidth = sampleRate / Float(fftSize)
        let nyquist = sampleRate / 2

        guard binWidth > 0, nyquist > 0 else {
            return [Float](repeating: 0, count: 5)
        }

        var levels = [Float](repeating: 0, count: 5)

        for bandIndex in 0 ..< 5 {
            let lowFrequency = min(max(bandEdges[bandIndex], 0), nyquist)
            let highFrequency = min(max(bandEdges[bandIndex + 1], lowFrequency + binWidth), nyquist)

            let lowerBin = max(1, Int(floor(lowFrequency / binWidth)))
            let upperBin = min(magnitudes.count - 1, Int(ceil(highFrequency / binWidth)))

            guard upperBin >= lowerBin else {
                levels[bandIndex] = 0
                continue
            }

            var energy: Float = 0
            for bin in lowerBin ... upperBin {
                energy += magnitudes[bin]
            }

            let averageEnergy = energy / Float(upperBin - lowerBin + 1)
            // zvmags output is unnormalized power. Scale to a 0...1-ish reference
            // so silence/noise doesn't pin bands high.
            let normalizedPower = averageEnergy / Float(fftSize * fftSize)
            let oneSidedPower = max(normalizedPower * 2, 1e-12)
            let decibels = (10 * log10f(oneSidedPower)) + bandGainOffsets[bandIndex]
            levels[bandIndex] = normalizeBandDecibels(decibels, bandIndex: bandIndex)
        }

        return levels
    }

    private func normalizeBandDecibels(_ decibels: Float, bandIndex: Int) -> Float {
        let floor = adaptiveFloors[bandIndex]
        let ceiling = adaptiveCeilings[bandIndex]

        // Track floor downward quickly, upward slowly.
        let floorAlpha: Float = decibels < floor ? 0.16 : 0.008
        adaptiveFloors[bandIndex] = (1 - floorAlpha) * floor + floorAlpha * decibels

        // Track ceiling upward quickly, downward slowly.
        let targetCeiling = max(decibels, adaptiveFloors[bandIndex] + 20)
        let ceilingAlpha: Float = targetCeiling > ceiling ? 0.06 : 0.015
        adaptiveCeilings[bandIndex] = (1 - ceilingAlpha) * ceiling + ceilingAlpha * targetCeiling
        adaptiveCeilings[bandIndex] = max(adaptiveCeilings[bandIndex], adaptiveFloors[bandIndex] + 20)

        // Require energy to rise above floor by a margin to avoid idle bars.
        let gate = adaptiveFloors[bandIndex] + 4.2
        let maxValue = adaptiveCeilings[bandIndex]
        guard decibels > gate, maxValue > gate else {
            return 0
        }

        let normalized = (decibels - gate) / (maxValue - gate)
        let clamped = min(max(normalized, 0), 1)
        let shaped = powf(clamped, 1.35)
        return min(shaped, 0.92)
    }
}

final class AudioCaptureService: NSObject, AudioCapturing, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var analysisEngine: AVAudioEngine?
    private var analyzer: FFTBandAnalyzer?

    private let bandsLock = NSLock()
    private var latestBands: [Float]?

    func start() throws {
        guard recorder == nil else {
            throw AudioCaptureError.alreadyRecording
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nativewhisper-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioCaptureError.failedToStart
        }

        self.recorder = recorder
        currentURL = url
        startBandAnalyzer()
    }

    func stop() throws -> URL {
        guard let recorder, let currentURL else {
            throw AudioCaptureError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        stopBandAnalyzer()
        return currentURL
    }

    func currentNormalizedInputLevel() -> Float? {
        guard let recorder else {
            return nil
        }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)

        let averageNormalized = normalizeDecibels(averagePower)
        let peakNormalized = normalizeDecibels(peakPower)
        let combined = (0.55 * averageNormalized) + (0.45 * peakNormalized)
        return min(max(combined, 0), 1)
    }

    func currentEqualizerBands() -> [Float]? {
        bandsLock.lock()
        defer { bandsLock.unlock() }
        return latestBands
    }

    private func startBandAnalyzer() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard let analyzer = FFTBandAnalyzer(fftSize: 1024) else {
            return
        }

        self.analyzer = analyzer

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(analyzer.fftSize), format: format) { [weak self, analyzer] buffer, _ in
            guard let self else {
                return
            }

            let bands = analyzer.bandLevels(from: buffer)
            self.bandsLock.lock()
            self.latestBands = bands
            self.bandsLock.unlock()
        }

        engine.prepare()

        do {
            try engine.start()
            self.analysisEngine = engine
        } catch {
            input.removeTap(onBus: 0)
            self.analysisEngine = nil
            self.analyzer = nil
            bandsLock.lock()
            self.latestBands = nil
            bandsLock.unlock()
        }
    }

    private func stopBandAnalyzer() {
        if let engine = analysisEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        analysisEngine = nil
        analyzer = nil

        bandsLock.lock()
        latestBands = nil
        bandsLock.unlock()
    }

    private func normalizeDecibels(_ power: Float) -> Float {
        let minDecibels: Float = -50
        let clamped = max(power, minDecibels)
        return (clamped - minDecibels) / abs(minDecibels)
    }
}
