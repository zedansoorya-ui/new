import Foundation

/// Normalises text before scoring, so WER measures recognition rather than formatting. (Named to
/// avoid clashing with FluidAudio's inverse-text-normalisation `TextNormalizer`.)
///
/// v0 rules: lowercase; curly quotes become straight; hyphens, slashes and underscores split
/// words; everything except letters, digits, apostrophes and spaces is dropped; apostrophes at
/// word edges are dropped; whitespace collapses. Numbers are **not** normalised yet ("twenty" and
/// "20" differ), so references should spell numbers the way the engine is expected to write them.
public enum ScoringNormalizer {
    public static func normalize(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for scalar in text.lowercased().unicodeScalars {
            switch scalar {
            case "\u{2018}", "\u{2019}", "\u{02BC}":
                output.unicodeScalars.append("'")
            case "-", "\u{2013}", "\u{2014}", "/", "_":
                output.unicodeScalars.append(" ")
            default:
                if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                    output.unicodeScalars.append(scalar)
                } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    output.unicodeScalars.append(" ")
                }
                // Everything else (punctuation, symbols) is dropped.
            }
        }
        return words(in: output).joined(separator: " ")
    }

    /// Normalised words.
    public static func words(_ text: String) -> [String] {
        words(in: normalize(text))
    }

    private static func words(in normalized: String) -> [String] {
        normalized
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }
}
