import Foundation

/// Word error rate of a hypothesis against a reference, after `ScoringNormalizer`.
public struct WordErrorRate: Sendable, Equatable, Codable {
    public var referenceWords: Int
    public var operations: EditOperations

    public init(referenceWords: Int, operations: EditOperations) {
        self.referenceWords = referenceWords
        self.operations = operations
    }

    /// (S + D + I) / N. Can exceed 1 when the hypothesis has many insertions. An empty reference
    /// gives 0 for an empty hypothesis and 1 otherwise.
    public var rate: Double {
        guard referenceWords > 0 else { return operations.insertions == 0 ? 0 : 1 }
        return Double(operations.total) / Double(referenceWords)
    }

    public static func compute(reference: String, hypothesis: String) -> WordErrorRate {
        let referenceWords = ScoringNormalizer.words(reference)
        let hypothesisWords = ScoringNormalizer.words(hypothesis)
        let operations = EditDistance.operations(reference: referenceWords, hypothesis: hypothesisWords)
        return WordErrorRate(referenceWords: referenceWords.count, operations: operations)
    }

    /// Corpus WER: total edits over total reference words, which weights long clips correctly.
    public static func aggregate(_ results: [WordErrorRate]) -> WordErrorRate {
        var operations = EditOperations()
        var words = 0
        for result in results {
            operations.substitutions += result.operations.substitutions
            operations.deletions += result.operations.deletions
            operations.insertions += result.operations.insertions
            words += result.referenceWords
        }
        return WordErrorRate(referenceWords: words, operations: operations)
    }
}
