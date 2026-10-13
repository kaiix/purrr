import CryptoKit
import Foundation
import NaturalLanguage

struct VocabularyCandidate: Identifiable, Equatable {
  let id: String
  let historyID: UUID
  let originalTerm: String
  var correctedTerm: String
  let originalContext: String
  let correctedContext: String
  let observedAt: Date
  var isSemanticallyReviewed = false
}

enum VocabularyCandidateExtractor {
  private struct Token {
    let text: String
    let range: Range<String.Index>

    var comparisonText: String { text.lowercased() }
  }

  static func candidates(from entry: HistoryEntry) -> [VocabularyCandidate] {
    guard entry.mode == .dictate, entry.status == .succeeded,
      entry.submissionState == .confirmed,
      let original = entry.processedText?.precomposedStringWithCanonicalMapping,
      let corrected = entry.submittedText?.precomposedStringWithCanonicalMapping,
      original != corrected, original.count <= 16_000, corrected.count <= 16_000
    else { return [] }

    let before = tokens(in: original)
    let after = tokens(in: corrected)
    // Bound worst-case sequence comparison for long or unrelated composer snapshots.
    guard !before.isEmpty, !after.isEmpty, before.count <= 512, after.count <= 512 else {
      return []
    }
    let difference = after.difference(from: before) {
      $0.comparisonText == $1.comparisonText
    }
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }

    // Large rewrites are not useful vocabulary evidence, even if a small hunk survives.
    if max(before.count, after.count) >= 12,
      removed.count + inserted.count > (before.count + after.count) / 2
    {
      return []
    }

    var results: [VocabularyCandidate] = []
    var oldIndex = 0
    var newIndex = 0
    while oldIndex < before.count || newIndex < after.count {
      let oldStart = oldIndex
      let newStart = newIndex
      while removed.contains(oldIndex) { oldIndex += 1 }
      while inserted.contains(newIndex) { newIndex += 1 }
      if oldStart != oldIndex || newStart != newIndex {
        let oldRange = oldStart..<oldIndex
        let newRange = newStart..<newIndex
        if !oldRange.isEmpty, !newRange.isEmpty,
          oldRange.count <= 4, newRange.count <= 4
        {
          let oldSpan =
            before[oldRange.lowerBound].range
            .lowerBound..<before[oldRange.upperBound - 1].range.upperBound
          let newSpan =
            after[newRange.lowerBound].range
            .lowerBound..<after[newRange.upperBound - 1].range.upperBound
          let source = String(original[oldSpan])
          let destination = String(corrected[newSpan])
          if isPossibleTerm(source), isPossibleTerm(destination),
            formattingKey(source) != formattingKey(destination),
            !isIdentifierFragment(oldSpan, in: original),
            !isIdentifierFragment(newSpan, in: corrected)
          {
            results.append(
              VocabularyCandidate(
                id: candidateID(
                  entry.id, oldStart: oldStart, newStart: newStart, source: source,
                  destination: destination),
                historyID: entry.id,
                originalTerm: source,
                correctedTerm: destination,
                originalContext: context(around: oldRange, tokens: before, text: original),
                correctedContext: context(around: newRange, tokens: after, text: corrected),
                observedAt: entry.submittedAt ?? entry.completedAt
              )
            )
          }
        }
      } else {
        // Both sequences have reached the next unchanged anchor.
        oldIndex += 1
        newIndex += 1
      }
    }
    return results
  }

  private static func tokens(in text: String) -> [Token] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var result: [Token] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      result.append(Token(text: String(text[range]), range: range))
      return result.count <= 512
    }
    return result
  }

  private static func formattingKey(_ text: String) -> String {
    String(text.lowercased().filter { $0.isLetter || $0.isNumber })
  }

  private static func candidateID(
    _ historyID: UUID, oldStart: Int, newStart: Int, source: String, destination: String
  ) -> String {
    // Dismissal metadata must not retain the edited words after History expires.
    let fingerprint = SHA256.hash(data: Data("\(source)\u{0}\(destination)".utf8))
      .map { String(format: "%02x", $0) }.joined()
    return "\(historyID.uuidString):\(oldStart):\(newStart):\(fingerprint)"
  }

  private static func isPossibleTerm(_ text: String) -> Bool {
    guard (2...60).contains(text.count), text.contains(where: { $0.isLetter }),
      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      return false
    }
    return text.allSatisfy {
      $0.isLetter || $0.isWhitespace || $0 == "-" || $0 == "'" || $0 == "’"
    }
  }

  private static func isIdentifierFragment(_ range: Range<String.Index>, in text: String) -> Bool {
    let delimiters: Set<Character> = ["/", "\\", "@", "_", "#", "=", ":"]
    if range.lowerBound > text.startIndex,
      delimiters.contains(text[text.index(before: range.lowerBound)])
    {
      return true
    }
    if range.upperBound < text.endIndex, delimiters.contains(text[range.upperBound]) {
      return true
    }
    return false
  }

  private static func context(around range: Range<Int>, tokens: [Token], text: String) -> String {
    let start = max(0, range.lowerBound - 6)
    let end = min(tokens.count, range.upperBound + 6)
    let editStart = tokens[range.lowerBound].range.lowerBound
    let editEnd = tokens[range.upperBound - 1].range.upperBound
    let lower = text.index(editStart, offsetBy: -200, limitedBy: text.startIndex) ?? text.startIndex
    let upper = text.index(editEnd, offsetBy: 200, limitedBy: text.endIndex) ?? text.endIndex
    return String(
      text[
        max(lower, tokens[start].range.lowerBound)..<min(upper, tokens[end - 1].range.upperBound)])
  }
}
