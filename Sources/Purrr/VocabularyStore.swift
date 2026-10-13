import Foundation

struct VocabularyWord: Identifiable, Codable, Equatable {
  enum Source: String, Codable {
    case manual
    case confirmedEdit
    case autoAdded
  }

  let id: UUID
  var term: String
  var source: Source
  let createdAt: Date
  var reviewedByLLM: Bool? = nil
}

enum VocabularyError: LocalizedError {
  case invalidTerm
  case duplicateTerm
  case unreadableStorage
  case wordChanged

  var errorDescription: String? {
    switch self {
    case .invalidTerm: "Use up to 60 characters on one line."
    case .duplicateTerm: "Already in your vocabulary."
    case .unreadableStorage: "Couldn’t read the vocabulary file. Nothing was changed."
    case .wordChanged:
      "This word has changed. Edit it in Vocabulary."
    }
  }
}

@MainActor
final class VocabularyStore: ObservableObject {
  @Published private(set) var words: [VocabularyWord] = []
  @Published private(set) var candidates: [VocabularyCandidate] = []
  @Published private(set) var storageError: String?
  @Published private(set) var collectsEdits = true
  @Published private(set) var isReviewing = false
  @Published private(set) var reviewError: String?

  private struct Snapshot: Codable, Equatable {
    var words: [VocabularyWord] = []
    var dismissedCandidateIDs: Set<String> = []
    var collectsEdits = true
    var reviewResults: [String: VocabularyReviewDecision] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
      case words, dismissedCandidateIDs, collectsEdits, reviewResults
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      words = try values.decode([VocabularyWord].self, forKey: .words)
      dismissedCandidateIDs = try values.decode(Set<String>.self, forKey: .dismissedCandidateIDs)
      collectsEdits = try values.decode(Bool.self, forKey: .collectsEdits)
      reviewResults =
        try values.decodeIfPresent([String: VocabularyReviewDecision].self, forKey: .reviewResults)
        ?? [:]
    }
  }

  private let fileURL: URL
  private var snapshot = Snapshot()
  private var observedCandidates: [VocabularyCandidate] = []
  private var canWrite = true
  private var activeReviews = 0

  /// The existing collection switch also controls vocabulary use during processing.
  var processingTerms: [String] {
    guard collectsEdits else { return [] }
    return words.filter { $0.source != .autoAdded || $0.reviewedByLLM == true }.map(\.term)
  }

  var unreviewedCandidates: [VocabularyCandidate] {
    guard collectsEdits else { return [] }
    return observedCandidates.filter {
      snapshot.reviewResults[$0.id] == nil && !snapshot.dismissedCandidateIDs.contains($0.id)
    }
  }

  init(storageURL: URL? = nil) {
    let root =
      storageURL
      ?? FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      )[0].appendingPathComponent("Purrr", isDirectory: true)
      .appendingPathComponent("Vocabulary", isDirectory: true)
    fileURL = root.appendingPathComponent("vocabulary.json")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      snapshot = try decoder.decode(Snapshot.self, from: Data(contentsOf: fileURL))
      publish()
    } catch {
      canWrite = false
      storageError = VocabularyError.unreadableStorage.localizedDescription
    }
  }

  func refresh(from history: [HistoryEntry], collectingEdits: Bool? = nil, now: Date = Date()) {
    let activeHistory = history.filter { $0.expiresAt > now }
    let eligibleCandidates = activeHistory.flatMap {
      VocabularyCandidateExtractor.candidates(from: $0)
    }
    observedCandidates =
      (collectingEdits ?? collectsEdits) ? eligibleCandidates : []
    // Review evidence has the same lifetime as History, not the confirmed word list.
    let activeHistoryIDs = Set(activeHistory.map { $0.id.uuidString })
    var next = snapshot
    next.dismissedCandidateIDs = next.dismissedCandidateIDs.filter {
      activeHistoryIDs.contains(String($0.prefix(36)))
    }
    // Turning collection off hides suggestions without forgetting completed reviews.
    next.reviewResults = next.reviewResults.filter { id, decision in
      guard let proposal = eligibleCandidates.first(where: { $0.id == id }) else { return false }
      return (try? VocabularySemanticReview.validate([decision], candidates: [proposal])) != nil
    }
    if next != snapshot {
      do {
        try save(next)
        return
      } catch {
        // Keep readable history available even when metadata cleanup cannot be saved.
      }
    }
    publishCandidates()
  }

  func setCollectsEdits(_ enabled: Bool) throws {
    var next = snapshot
    next.collectsEdits = enabled
    try save(next)
  }

  func add(_ term: String) throws {
    try add(term, source: .manual, candidateID: nil)
  }

  func confirm(_ candidate: VocabularyCandidate, term: String) throws {
    try add(
      term, source: .confirmedEdit, candidateID: candidate.id,
      reviewed: candidate.isSemanticallyReviewed)
  }

  func beginReview() {
    activeReviews += 1
    isReviewing = true
    reviewError = nil
  }

  func finishReview(error: String? = nil) {
    activeReviews = max(0, activeReviews - 1)
    isReviewing = activeReviews > 0
    if let error { reviewError = error }
  }

  /// Raw diffs cannot enter automatic collection without explicit semantic decisions.
  func applyReview(
    _ decisions: [VocabularyReviewDecision], proposals: [VocabularyCandidate],
    automaticallyAdd: Bool, now: Date = Date()
  ) throws -> [VocabularyWord] {
    guard collectsEdits else { return [] }
    try VocabularySemanticReview.validate(decisions, candidates: proposals)
    var next = snapshot
    var approved: [VocabularyCandidate] = []
    for decision in decisions {
      guard let proposal = proposals.first(where: { $0.id == decision.candidateID }),
        observedCandidates.contains(proposal),
        !snapshot.dismissedCandidateIDs.contains(proposal.id)
      else { continue }
      next.reviewResults[proposal.id] = decision
      if decision.action == .termCorrection, let term = decision.term {
        var reviewed = proposal
        reviewed.correctedTerm = term
        reviewed.isSemanticallyReviewed = true
        approved.append(reviewed)
      }
    }
    var existing = Set(words.map { Self.key($0.term) })
    var added: [VocabularyWord] = []
    for candidate in automaticallyAdd ? approved : [] {
      let key = Self.key(candidate.correctedTerm)
      if existing.contains(key) {
        // Suppress duplicate evidence in the same batch as a newly added word.
        if added.contains(where: { Self.key($0.term) == key }) {
          next.dismissedCandidateIDs.insert(candidate.id)
        }
        continue
      }
      let term = try validatedTerm(candidate.correctedTerm)
      let word = VocabularyWord(
        id: UUID(), term: term, source: .autoAdded, createdAt: now, reviewedByLLM: true)
      added.append(word)
      next.words.append(word)
      existing.insert(key)
      next.dismissedCandidateIDs.insert(candidate.id)
    }
    guard next != snapshot else { return [] }
    // Persist every successful decision, even when no word is accepted or newly added.
    // Publishing only after the atomic save leaves failed attempts retryable.
    try save(next)
    return added
  }

  func undoAutoAdded(_ added: [VocabularyWord]) throws {
    guard !added.isEmpty else { return }
    // Never delete another word or a spelling the user has edited in the meantime.
    guard added.allSatisfy({ $0.source == .autoAdded && words.contains($0) }) else {
      throw VocabularyError.wordChanged
    }
    let ids = Set(added.map(\.id))
    var next = snapshot
    next.words.removeAll { ids.contains($0.id) }
    // Keep dismissed edit IDs so the same evidence cannot immediately add them again.
    try save(next)
  }

  func update(_ word: VocabularyWord, term: String) throws {
    let cleaned = try validatedTerm(term, excluding: word.id)
    var next = snapshot
    guard let index = next.words.firstIndex(where: { $0.id == word.id }) else { return }
    next.words[index].term = cleaned
    if word.source == .autoAdded && word.reviewedByLLM != true {
      // Explicitly saving a legacy spelling is a manual confirmation, not LLM approval.
      next.words[index].source = .manual
    }
    try save(next)
  }

  func delete(_ word: VocabularyWord) throws {
    var next = snapshot
    next.words.removeAll { $0.id == word.id }
    try save(next)
  }

  func dismiss(_ candidate: VocabularyCandidate) throws {
    var next = snapshot
    next.dismissedCandidateIDs.insert(candidate.id)
    try save(next)
  }

  private func add(
    _ term: String, source: VocabularyWord.Source, candidateID: String?, reviewed: Bool? = nil
  ) throws {
    let cleaned = try validatedTerm(term)
    var next = snapshot
    next.words.append(
      VocabularyWord(
        id: UUID(), term: cleaned, source: source, createdAt: Date(), reviewedByLLM: reviewed))
    if let candidateID { next.dismissedCandidateIDs.insert(candidateID) }
    try save(next)
  }

  private func validatedTerm(_ term: String, excluding id: UUID? = nil) throws -> String {
    let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
    guard !cleaned.isEmpty, cleaned.count <= 60,
      !cleaned.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw VocabularyError.invalidTerm }
    guard !words.contains(where: { $0.id != id && Self.key($0.term) == Self.key(cleaned) }) else {
      throw VocabularyError.duplicateTerm
    }
    return cleaned
  }

  private static func key(_ term: String) -> String {
    term.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }

  private func save(_ next: Snapshot) throws {
    guard canWrite else { throw VocabularyError.unreadableStorage }
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(next)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try data.write(to: fileURL, options: .atomic)
      snapshot = next
      storageError = nil
      publish()
    } catch {
      storageError = "Vocabulary could not be saved: \(error.localizedDescription)"
      throw error
    }
  }

  private func publish() {
    words = snapshot.words.sorted { $0.term.localizedStandardCompare($1.term) == .orderedAscending }
    collectsEdits = snapshot.collectsEdits
    publishCandidates()
  }

  private func publishCandidates() {
    let existing = Set(words.map { Self.key($0.term) })
    candidates =
      collectsEdits
      ? observedCandidates.compactMap { proposal in
        guard !snapshot.dismissedCandidateIDs.contains(proposal.id),
          let decision = snapshot.reviewResults[proposal.id], decision.action == .termCorrection,
          let term = decision.term, !existing.contains(Self.key(term))
        else { return nil }
        var reviewed = proposal
        reviewed.correctedTerm = term
        reviewed.isSemanticallyReviewed = true
        return reviewed
      } : []
  }
}
