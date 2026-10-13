import Foundation
import XCTest

@testable import Purrr

final class VocabularyTests: XCTestCase {
  func testLocalizedCorrectionsIncludeUnseenSpellingsAndSplitWords() {
    for original in ["AllDay", "all day", "aw day"] {
      let candidates = VocabularyCandidateExtractor.candidates(
        from: entry(before: "Please open the \(original) app.", after: "Please open the auday app.")
      )
      XCTAssertEqual(candidates.map(\.originalTerm), [original])
      XCTAssertEqual(candidates.map(\.correctedTerm), ["auday"])
    }
    let candidates = VocabularyCandidateExtractor.candidates(
      from: entry(before: "你知道 TypeList 吗？", after: "你知道 typeless 吗？")
    )
    XCTAssertEqual(candidates.map(\.correctedTerm), ["typeless"])
  }

  func testTwoIndependentCorrectionsStaySeparate() {
    let candidates = VocabularyCandidateExtractor.candidates(
      from: entry(
        before: "Open TypeList and then launch AllDay please.",
        after: "Open typeless and then launch auday please."
      )
    )
    XCTAssertEqual(candidates.map(\.correctedTerm), ["typeless", "auday"])
  }

  func testFormattingAdditionsDeletionsAndNumbersAreNotVocabulary() {
    let changes = [
      ("Pronoun Gender is useful.", "pronoun gender is useful!"),
      ("Open AllDay please.", "Open all day please."),
      ("Open the app.", "Please open the app."),
      ("Please open the app.", "Open the app."),
      ("Set it to 123 today.", "Set it to 456 today."),
      ("Open /tmp/TypeList now.", "Open /tmp/typeless now."),
      ("Open TypeList now.", "Open very\nnice now."),
    ]
    for (before, after) in changes {
      XCTAssertTrue(
        VocabularyCandidateExtractor.candidates(from: entry(before: before, after: after)).isEmpty,
        "Unexpected candidate for \(before) -> \(after)"
      )
    }
  }

  func testUnconfirmedTranslateAndLongRewritesAreExcluded() {
    var value = entry(before: "Open TypeList please.", after: "Open typeless please.")
    value.mode = .translate
    XCTAssertTrue(VocabularyCandidateExtractor.candidates(from: value).isEmpty)
    value.mode = .dictate
    value.submissionState = .unknown
    XCTAssertTrue(VocabularyCandidateExtractor.candidates(from: value).isEmpty)

    let before = Array(repeating: "before", count: 513).joined(separator: " ")
    let after = Array(repeating: "after", count: 513).joined(separator: " ")
    XCTAssertTrue(
      VocabularyCandidateExtractor.candidates(from: entry(before: before, after: after)).isEmpty)
  }

  @MainActor
  func testWordsPreserveSpellingPersistAndRejectDuplicateVariants() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    try store.add("  auday  ")
    try store.add("Pronoun Gender")
    XCTAssertThrowsError(try store.add("AUDAY"))
    XCTAssertThrowsError(try store.add("pronoun   gender"))
    XCTAssertThrowsError(try store.add("two\nlines"))
    XCTAssertEqual(store.words.count, 2)

    let word = try XCTUnwrap(store.words.first { $0.term == "auday" })
    try store.update(word, term: "Auday")
    let reloaded = VocabularyStore(storageURL: root)
    XCTAssertEqual(Set(reloaded.words.map(\.term)), ["Auday", "Pronoun Gender"])
    try reloaded.delete(try XCTUnwrap(reloaded.words.first { $0.term == "Auday" }))
    XCTAssertEqual(VocabularyStore(storageURL: root).words.map(\.term), ["Pronoun Gender"])
  }

  @MainActor
  func testOlderHistoryRequiresConfirmationAndDismissalSurvivesReload() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let revision = entry(before: "Open TypeList please.", after: "Open typeless please.")
    let store = VocabularyStore(storageURL: root)
    store.refresh(from: [revision], now: Date(timeIntervalSince1970: 2_000_000_001))
    XCTAssertTrue(store.words.isEmpty)
    let candidate = try XCTUnwrap(store.unreviewedCandidates.first)
    XCTAssertFalse(candidate.id.contains("TypeList"))
    XCTAssertFalse(candidate.id.contains("typeless"))
    try store.dismiss(candidate)

    let reloaded = VocabularyStore(storageURL: root)
    reloaded.refresh(from: [revision], now: Date(timeIntervalSince1970: 2_000_000_001))
    XCTAssertTrue(reloaded.candidates.isEmpty)

    let other = entry(before: "Please open aw day now.", after: "Please open auday now.")
    reloaded.refresh(from: [revision, other], now: Date(timeIntervalSince1970: 2_000_000_001))
    try reloaded.confirm(try XCTUnwrap(reloaded.unreviewedCandidates.first), term: "auday")
    XCTAssertEqual(reloaded.words.map(\.term), ["auday"])
    XCTAssertEqual(reloaded.words.first?.source, .confirmedEdit)
    XCTAssertTrue(reloaded.candidates.isEmpty)
  }

  @MainActor
  func testExpiredEvidenceDoesNotDeleteWordsAndReviewTogglePersists() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    try store.add("auday")
    let revision = entry(before: "Open TypeList please.", after: "Open typeless please.")
    store.refresh(from: [revision], now: Date(timeIntervalSince1970: 2_000_000_001))
    try store.setCollectsEdits(false)
    XCTAssertTrue(store.candidates.isEmpty)
    XCTAssertFalse(VocabularyStore(storageURL: root).collectsEdits)
    try store.setCollectsEdits(true)
    store.refresh(from: [revision], now: Date(timeIntervalSince1970: 2_000_000_001))
    XCTAssertEqual(store.unreviewedCandidates.count, 1)
    store.refresh(from: [revision], now: Date(timeIntervalSince1970: 2_000_000_000 + 24 * 60 * 60))
    XCTAssertTrue(store.candidates.isEmpty)
    XCTAssertEqual(store.words.map(\.term), ["auday"])
  }

  @MainActor
  func testCorruptStorageIsNotSilentlyOverwritten() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("vocabulary.json")
    let corrupt = Data("not valid JSON".utf8)
    try corrupt.write(to: file)
    let store = VocabularyStore(storageURL: root)
    XCTAssertThrowsError(try store.add("auday"))
    XCTAssertEqual(try Data(contentsOf: file), corrupt)
    XCTAssertTrue(store.words.isEmpty)
  }

  @MainActor
  func testLiveEditsAutoAddOnceAndUndoSuppressesTheSameEvidence() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    try store.add("PostgreSQL")
    let revision = entry(
      before: "Open TypeList and then launch AllDay please.",
      after: "Open typeless and then launch auday please."
    )
    let now = Date(timeIntervalSince1970: 2_000_000_001)
    store.refresh(from: [revision], now: now)
    XCTAssertEqual(
      store.words.map(\.term), ["PostgreSQL"], "History refresh must not auto-add old edits")

    let added = try reviewAndCollect(store, entry: revision, now: now)
    XCTAssertEqual(added.map(\.term), ["typeless", "auday"])
    XCTAssertTrue(added.allSatisfy { $0.source == .autoAdded })
    XCTAssertEqual(VocabularyStore(storageURL: root).words.count, 3)
    XCTAssertTrue(try reviewAndCollect(store, entry: revision, now: now).isEmpty)

    try store.undoAutoAdded(added)
    let reloaded = VocabularyStore(storageURL: root)
    reloaded.refresh(from: [revision], now: now)
    XCTAssertEqual(reloaded.words.map(\.term), ["PostgreSQL"])
    XCTAssertTrue(reloaded.candidates.isEmpty)
    XCTAssertTrue(try reviewAndCollect(reloaded, entry: revision, now: now).isEmpty)
  }

  @MainActor
  func testAutoCollectionRespectsTheToggleEligibilityAndExistingSpelling() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    let now = Date(timeIntervalSince1970: 2_000_000_001)
    var revision = entry(before: "Open TypeList please.", after: "Open typeless please.")
    try store.setCollectsEdits(false)
    XCTAssertTrue(try reviewAndCollect(store, entry: revision, now: now).isEmpty)
    try store.setCollectsEdits(true)
    revision.mode = .translate
    XCTAssertTrue(try reviewAndCollect(store, entry: revision, now: now).isEmpty)
    revision.mode = .dictate
    revision.submissionState = .unknown
    XCTAssertTrue(try reviewAndCollect(store, entry: revision, now: now).isEmpty)
    revision.submissionState = .confirmed
    XCTAssertTrue(
      try reviewAndCollect(store, entry: revision, now: now.addingTimeInterval(86_400)).isEmpty)
    try store.add("Typeless")
    XCTAssertTrue(try reviewAndCollect(store, entry: revision, now: now).isEmpty)
    XCTAssertEqual(store.words.first?.term, "Typeless")
    XCTAssertEqual(store.words.first?.source, .manual)
  }

  @MainActor
  func testUndoPreservesWordsEditedAfterAutomaticCollection() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    let added = try reviewAndCollect(
      store,
      entry: entry(
        before: "Open TypeList and then launch AllDay please.",
        after: "Open typeless and then launch auday please."
      ), now: Date(timeIntervalSince1970: 2_000_000_001)
    )
    try store.update(try XCTUnwrap(added.first), term: "Typeless App")
    XCTAssertThrowsError(try store.undoAutoAdded(added))
    XCTAssertEqual(Set(store.words.map(\.term)), ["Typeless App", "auday"])
  }

  @MainActor
  func testAutomaticCollectionDoesNotPublishWordsWhenSavingFails() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let blocked = root.appendingPathComponent("not-a-directory")
    try Data("occupied".utf8).write(to: blocked)
    let store = VocabularyStore(storageURL: blocked)
    XCTAssertThrowsError(
      try reviewAndCollect(
        store,
        entry: entry(before: "Open TypeList please.", after: "Open typeless please."),
        now: Date(timeIntervalSince1970: 2_000_000_001)
      )
    )
    XCTAssertTrue(store.words.isEmpty)
    XCTAssertNotNil(store.storageError)
    XCTAssertFalse(store.unreviewedCandidates.isEmpty, "Failed saves must remain retryable")
    XCTAssertTrue(store.candidates.isEmpty)
  }

  private func temporaryStorage() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }

  @MainActor
  private func reviewAndCollect(_ store: VocabularyStore, entry: HistoryEntry, now: Date) throws
    -> [VocabularyWord]
  {
    store.refresh(from: [entry], now: now)
    let proposals = store.unreviewedCandidates
    let decisions = proposals.map {
      VocabularyReviewDecision(candidateID: $0.id, action: .termCorrection, term: $0.correctedTerm)
    }
    return try store.applyReview(decisions, proposals: proposals, automaticallyAdd: true, now: now)
  }

  private func entry(
    before: String, after: String,
    completedAt: Date = Date(timeIntervalSince1970: 2_000_000_000)
  ) -> HistoryEntry {
    HistoryEntry(
      id: UUID(), completedAt: completedAt, mode: .dictate, audioFileName: nil,
      rawTranscript: before, processedText: before, submittedText: after,
      submissionState: .confirmed, submittedAt: completedAt, submissionEvidence: .returnKey,
      targetLanguage: nil, status: .succeeded, failureStage: nil, failureMessage: nil,
      usedRawFallback: false
    )
  }
}
