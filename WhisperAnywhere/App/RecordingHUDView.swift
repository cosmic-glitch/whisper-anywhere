import SwiftUI

enum RecordingHUDMode: Equatable {
    case recording
    case transcribing
    case message(String)
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    static let waveformSampleCount = 140
    static let waveformFloor: Float = 0.04

    @Published var bands: [Float] = Array(repeating: waveformFloor, count: waveformSampleCount)
    @Published var mode: RecordingHUDMode = .recording
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        Group {
            if model.mode == .recording {
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    GeometryReader { geometry in
                        let barCount = max(model.bands.count, 1)
                        let spacing: CGFloat = 1
                        let totalSpacing = CGFloat(barCount - 1) * spacing
                        let computedWidth = (geometry.size.width - totalSpacing) / CGFloat(barCount)
                        let barWidth = max(0.8, computedWidth * 0.88)

                        HStack(spacing: spacing) {
                            ForEach(Array(model.bands.enumerated()), id: \.offset) { _, band in
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.96))
                                    .frame(width: barWidth, height: barHeight(for: band))
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                        }
                    }
                    .frame(height: 24)
                    .animation(.linear(duration: 0.08), value: model.bands)
                }
            } else if model.mode == .transcribing {
                Text("Transcribing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if case let .message(text) = model.mode {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.clear)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func barHeight(for band: Float) -> CGFloat {
        let clamped = CGFloat(min(max(band, 0), 1))
        let floor: CGFloat = 0.01
        let adjusted = max(clamped, floor)
        let boosted = pow(adjusted, 1.1)
        let minHeight: CGFloat = 3
        let dynamicRange: CGFloat = 18
        return minHeight + (boosted * dynamicRange)
    }
}
