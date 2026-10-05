import MurmurCore
import MurmurStorage
import SwiftUI

/// Every saved dictation: a searchable list on the left, the full text on the right.
///
/// The search field and controls live inside the view rather than in a window toolbar, because
/// the window hosts this view directly and SwiftUI toolbars need a SwiftUI-managed window.
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @State private var confirmingClear = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search dictations", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                List(selection: $model.selection) {
                    ForEach(model.sections) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                HistoryRow(entry: entry)
                                    .tag(entry.id)
                                    .contextMenu {
                                        Button("Copy") { model.copy(entry) }
                                        Button("Delete", role: .destructive) { model.delete(entry) }
                                    }
                            }
                        }
                    }
                }
                .overlay {
                    if model.entries.isEmpty {
                        emptyState
                    }
                }
                Divider()
                HStack {
                    Toggle("Save new dictations", isOn: $model.saveHistoryChoice)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                        .controlSize(.small)
                        .disabled(model.totalCount == 0)
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            if let entry = model.selectedEntry {
                HistoryDetail(entry: entry, onCopy: { model.copy(entry) }, onDelete: { model.delete(entry) })
            } else {
                Text(model.entries.isEmpty ? "" : "Select a dictation")
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Delete all \(model.totalCount) saved dictations?",
            isPresented: $confirmingClear
        ) {
            Button("Delete All", role: .destructive) { model.deleteAll() }
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: model.query) {
            model.reload()
        }
        .frame(minWidth: 720, minHeight: 440)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "waveform" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if let problem = model.problem {
                Text(problem)
            } else if model.query.isEmpty {
                Text("No dictations yet")
                    .font(.headline)
                Text("Hold fn and speak. Everything you dictate is saved here, on this Mac only.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No matches for “\(model.query)”")
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

private struct HistoryRow: View {
    let entry: DictationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let app = entry.appName {
                    Text(app)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(HistoryFormat.duration(entry.audioSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(entry.text)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetail: View {
    let entry: DictationEntry
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            HStack(alignment: .top, spacing: 18) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    detailRow("When", entry.createdAt.formatted(date: .abbreviated, time: .standard))
                    detailRow("App", entry.appName ?? "Unknown")
                    detailRow("Length", "\(HistoryFormat.duration(entry.audioSeconds)), \(entry.wordCount) words")
                    detailRow("Mode", HistoryFormat.mode(entry.mode))
                    if let latency = entry.timeline?.postReleaseLatency {
                        detailRow("Ready in", "\(Int((latency * 1000).rounded())) ms after release")
                    }
                }
                .font(.callout)
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Copy", action: onCopy)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
            .padding(16)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

enum HistoryFormat {
    static func duration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1f s", seconds)
        }
        let whole = Int(seconds.rounded())
        return String(format: "%ld:%02ld", whole / 60, whole % 60)
    }

    static func mode(_ mode: CaptureMode) -> String {
        switch mode {
        case .hold: return "Hold to talk"
        case .handsFree: return "Hands-free"
        case .command: return "Command"
        }
    }
}
