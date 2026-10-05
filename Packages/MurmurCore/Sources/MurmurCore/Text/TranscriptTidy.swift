import Foundation

/// The minimal clean-up every transcript gets before it leaves the engine layer. The real
/// cleanup pipeline (fillers, spoken commands, dictionary, LLM) arrives in Milestone 4.
public enum TranscriptTidy {
    /// Trims, collapses runs of spaces and tabs, removes spaces before punctuation, and keeps
    /// line breaks.
    public static func basic(_ text: String) -> String {
        var lines: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let words = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
            var line = words.joined(separator: " ")
            for mark in [",", ".", "!", "?", ";", ":"] {
                line = line.replacingOccurrences(of: " " + mark, with: mark)
            }
            lines.append(line)
        }
        // Drop leading and trailing empty lines, keep interior paragraph breaks.
        while let first = lines.first, first.isEmpty { lines.removeFirst() }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
