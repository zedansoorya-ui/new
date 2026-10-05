import Foundation
import MurmurStorage

/// One calendar day of dictations in the History window.
struct HistorySection: Identifiable {
    let id: Date
    let title: String
    let entries: [DictationEntry]
}

/// State for the History window. Reads go straight to the database (they take milliseconds).
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var entries: [DictationEntry] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var problem: String?
    @Published var query = ""
    @Published var selection: DictationEntry.ID?
    @Published var saveHistory: Bool

    /// Called when the "Save new dictations" switch changes.
    var onSaveHistoryChange: ((Bool) -> Void)?
    /// Called after one entry was deleted, and after the history was cleared.
    var onEntryDeleted: ((UUID) -> Void)?
    var onHistoryCleared: (() -> Void)?

    private let store: HistoryStore?

    init(store: HistoryStore?, saveHistory: Bool) {
        self.store = store
        self.saveHistory = saveHistory
    }

    /// The switch's binding: records the choice and tells the app.
    var saveHistoryChoice: Bool {
        get { saveHistory }
        set {
            saveHistory = newValue
            onSaveHistoryChange?(newValue)
        }
    }

    var selectedEntry: DictationEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    func reload() {
        guard let store else {
            entries = []
            totalCount = 0
            problem = "History is unavailable: Murmur could not open its database. Copy Diagnostics for details."
            return
        }
        do {
            entries = try store.search(query)
            totalCount = try store.count()
            problem = nil
        } catch {
            problem = "Could not read the history: \(error.localizedDescription)"
            Log.ui.error("history read failed: \(error.localizedDescription, privacy: .public)")
        }
        if selection == nil || !entries.contains(where: { $0.id == selection }) {
            selection = entries.first?.id
        }
    }

    func copy(_ entry: DictationEntry) {
        Clipboard.copy(entry.text)
    }

    func delete(_ entry: DictationEntry) {
        do {
            try store?.delete(id: entry.id)
            reload()
            onEntryDeleted?(entry.id)
        } catch {
            reload()
            problem = "Could not delete: \(error.localizedDescription)"
        }
    }

    func deleteAll() {
        do {
            try store?.deleteAll()
            reload()
            onHistoryCleared?()
        } catch {
            reload()
            problem = "Could not clear the history: \(error.localizedDescription)"
        }
    }

    /// Entries grouped by day, newest first: "Today", "Yesterday", then dates.
    var sections: [HistorySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            HistorySection(
                id: day,
                title: Self.title(for: day, calendar: calendar),
                entries: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    private static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
