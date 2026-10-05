// Visual design follows Muesli's floating indicator (FloatingIndicatorController.swift and
// IndicatorWaveformDynamics.swift at 906df1c, MIT, Copyright (c) 2026 Pranav Hari): a dark capsule
// with a live waveform and timer. Rebuilt in SwiftUI for Murmur, with hover controls.

import SwiftUI

/// What the pill is showing, and what its buttons do.
@MainActor
final class PillModel: ObservableObject {
    /// A capture in progress. The timer excludes time spent paused.
    struct Recording: Equatable {
        var startedAt: Date
        /// "Hands-free" or "Command"; nil for a plain hold.
        var label: String?
        /// Set while paused; the timer stops here.
        var pausedAt: Date?
        /// Time spent paused before `pausedAt`.
        var pausedTotal: TimeInterval = 0

        var isPaused: Bool {
            pausedAt != nil
        }

        func elapsed(at now: Date) -> TimeInterval {
            max(0, (pausedAt ?? now).timeIntervalSince(startedAt) - pausedTotal)
        }
    }

    enum Phase: Equatable {
        case idle
        case recording(Recording)
        case processing
        case done(String)
        case error(String)
    }

    static let barCount = 22

    @Published var phase: Phase = .idle
    /// The pointer is over the pill: show its buttons.
    @Published var isHovering = false
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: PillModel.barCount)

    var onStartDictation: (@MainActor () -> Void)?
    var onTogglePause: (@MainActor () -> Void)?
    var onStop: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onOpenHistory: (@MainActor () -> Void)?

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
            .padding(.horizontal, isCollapsed ? 0 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(Color.black.opacity(isCollapsed ? 0.35 : 0.85))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(isCollapsed ? 0.15 : 0.2), lineWidth: 0.5)
            )
            .foregroundStyle(Color.white)
    }

    /// The small resting bar.
    private var isCollapsed: Bool {
        model.phase == .idle && !model.isHovering
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if model.isHovering {
                HStack(spacing: 6) {
                    PillButton(systemImage: "mic.fill", title: "Dictate") { model.onStartDictation?() }
                    PillButton(systemImage: "clock.arrow.circlepath", title: "History") { model.onOpenHistory?() }
                }
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 18, height: 3)
            }

        case .recording(let recording):
            HStack(spacing: 8) {
                if recording.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.orange)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                }
                if model.isHovering {
                    RecordingTimer(recording: recording)
                    PillButton(
                        systemImage: recording.isPaused ? "play.fill" : "pause.fill",
                        title: recording.isPaused ? "Resume" : "Pause"
                    ) { model.onTogglePause?() }
                    PillButton(systemImage: "checkmark", title: "Done") { model.onStop?() }
                    PillButton(systemImage: "xmark", title: "Cancel", tint: Color(red: 1, green: 0.55, blue: 0.5)) {
                        model.onCancel?()
                    }
                } else {
                    if recording.isPaused {
                        Text("Paused")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    } else {
                        WaveformBars(levels: model.levels)
                    }
                    RecordingTimer(recording: recording)
                    if let label = recording.label {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
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
                if model.isHovering {
                    PillButton(systemImage: "clock.arrow.circlepath", title: "History") { model.onOpenHistory?() }
                }
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

    static func elapsed(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%ld:%02ld", whole / 60, whole % 60)
    }
}

/// A compact labelled button. Labels rather than tooltips, because macOS shows no tooltips for an
/// app that is not active, which Murmur never is while you dictate.
struct PillButton: View {
    let systemImage: String
    let title: String
    var tint: Color = .white
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .accessibilityLabel(title)
    }
}

/// Elapsed recording time, frozen while paused.
struct RecordingTimer: View {
    let recording: PillModel.Recording

    var body: some View {
        TimelineView(.periodic(from: recording.startedAt, by: 0.5)) { context in
            Text(PillView.elapsed(recording.elapsed(at: context.date)))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
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
