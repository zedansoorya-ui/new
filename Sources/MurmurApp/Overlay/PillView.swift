// Visual design follows Muesli's floating indicator (FloatingIndicatorController.swift and
// IndicatorWaveformDynamics.swift at 906df1c, MIT, Copyright (c) 2026 Pranav Hari): a dark capsule
// with a live waveform and timer. Rebuilt in SwiftUI for Murmur.

import SwiftUI

/// What the pill is showing.
@MainActor
final class PillModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date, label: String?)
        case processing
        case done(String)
        case error(String)
    }

    static let barCount = 22

    @Published var phase: Phase = .idle
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: PillModel.barCount)

    func push(level: Float) {
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

struct PillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        content
            .padding(.horizontal, model.phase == .idle ? 0 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(Color.black.opacity(model.phase == .idle ? 0.35 : 0.85))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(model.phase == .idle ? 0.15 : 0.2), lineWidth: 0.5)
            )
            .foregroundStyle(Color.white)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            Capsule()
                .fill(Color.white.opacity(0.6))
                .frame(width: 18, height: 3)

        case .recording(let since, let label):
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                WaveformBars(levels: model.levels)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.elapsed(from: since, to: context.date))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white)
                Text("Transcribing")
                    .font(.system(size: 12, weight: .medium))
            }

        case .done(let message):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
            }

        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.yellow)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%ld:%02ld", seconds / 60, seconds % 60)
    }
}

/// Live mic level, newest on the right.
struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 18))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: levels)
    }
}
