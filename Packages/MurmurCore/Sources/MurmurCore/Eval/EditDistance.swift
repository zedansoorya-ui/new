import Foundation

/// Levenshtein distance with operation counts, over any equatable sequence.
public struct EditOperations: Sendable, Equatable, Codable {
    public var substitutions: Int
    public var deletions: Int
    public var insertions: Int

    public init(substitutions: Int = 0, deletions: Int = 0, insertions: Int = 0) {
        self.substitutions = substitutions
        self.deletions = deletions
        self.insertions = insertions
    }

    public var total: Int { substitutions + deletions + insertions }
}

public enum EditDistance {
    /// Minimum edits turning `reference` into `hypothesis`. Ties prefer substitutions, then
    /// deletions, then insertions, which is the usual convention for WER breakdowns.
    public static func operations<T: Equatable>(reference: [T], hypothesis: [T]) -> EditOperations {
        let n = reference.count
        let m = hypothesis.count
        if n == 0 { return EditOperations(insertions: m) }
        if m == 0 { return EditOperations(deletions: n) }

        // Each cell holds (cost, substitutions, deletions, insertions) for the prefix pair.
        var previous = [EditOperations](repeating: EditOperations(), count: m + 1)
        for j in 0...m { previous[j] = EditOperations(insertions: j) }

        for i in 1...n {
            var current = [EditOperations](repeating: EditOperations(), count: m + 1)
            current[0] = EditOperations(deletions: i)
            for j in 1...m {
                if reference[i - 1] == hypothesis[j - 1] {
                    current[j] = previous[j - 1]
                    continue
                }
                var substitute = previous[j - 1]
                substitute.substitutions += 1
                var delete = previous[j]
                delete.deletions += 1
                var insert = current[j - 1]
                insert.insertions += 1
                current[j] = [substitute, delete, insert].min { $0.total < $1.total }!
            }
            previous = current
        }
        return previous[m]
    }

    /// Character-level distance between two strings.
    public static func characters(_ a: String, _ b: String) -> Int {
        operations(reference: Array(a), hypothesis: Array(b)).total
    }

    /// 1 − distance / max(length): 1 is identical, 0 is completely different.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(characters(a, b)) / Double(longest)
    }
}
