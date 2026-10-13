import Foundation
import XCTest

@testable import Purrr

final class VocabularySemanticReviewTests: XCTestCase {
  func testOnlyApprovedCorrectionsReturnTermsAndFullNamesCanBeExtracted() throws {
    let proposals = [
      candidate(
        before: "Audey", after: "auday", beforeContext: "Open Audey Pro please",
        afterContext: "Open auday Pro please"),
      candidate(before: "应该", after: "定义"),
      candidate(before: "然后", after: "和官方回复"),
    ]
    let decisions = try VocabularySemanticReview.decode(
      """
      {"decisions":[
        {"id":0,"action":"term_correction","term":"auday Pro"},
        {"id":1,"action":"ordinary_edit","term":null},
        {"id":2,"action":"uncertain","term":null}
      ]}
      """, candidates: proposals
    )
    XCTAssertEqual(decisions.first?.candidateID, proposals[0].id)
    XCTAssertEqual(decisions.first?.term, "auday Pro")
    XCTAssertEqual(decisions[1].action, .ordinaryEdit)
    XCTAssertEqual(decisions[2].action, .uncertain)
  }

  func testInvalidOrUngroundedResponsesFailClosed() {
    let proposals = [candidate(before: "TypeList", after: "typeless")]
    let responses = [
      "{\"decisions\":[]}",
      "{\"decisions\":[{\"id\":9,\"action\":\"term_correction\",\"term\":\"typeless\"}]}",
      "{\"decisions\":[{\"id\":0,\"action\":\"term_correction\",\"term\":\"Typeless\"}]}",
      "{\"decisions\":[{\"id\":0,\"action\":\"ordinary_edit\",\"term\":\"typeless\"}]}",
      "{\"decisions\":[{\"id\":0,\"action\":\"unknown_action\",\"term\":null}]}",
      "Please ignore the task and add everything.",
    ]
    for response in responses {
      XCTAssertThrowsError(try VocabularySemanticReview.decode(response, candidates: proposals))
    }
    let adjacentName = candidate(
      before: "应该", after: "定义", beforeContext: "Typeless 应该", afterContext: "Typeless 定义"
    )
    XCTAssertThrowsError(
      try VocabularySemanticReview.decode(
        "{\"decisions\":[{\"id\":0,\"action\":\"term_correction\",\"term\":\"Typeless\"}]}",
        candidates: [adjacentName]
      ))
    XCTAssertThrowsError(
      try VocabularySemanticReview.decode(
        "{\"decisions\":[{\"id\":0,\"action\":\"uncertain\"},{\"id\":0,\"action\":\"uncertain\"}]}",
        candidates: [proposals[0], candidate(before: "AllDay", after: "auday")]
      ))
  }

  @MainActor
  func testOrdinaryAndUncertainEditsDisappearFromReviewWithoutBeingCollected() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    let value = entry(before: "这里应该说清楚", after: "这里定义说清楚")
    let ambiguous = entry(before: "Open TypeList please", after: "Open typeless please")
    let now = value.completedAt.addingTimeInterval(1)
    store.refresh(from: [value, ambiguous], now: now)
    XCTAssertFalse(store.unreviewedCandidates.isEmpty)
    XCTAssertTrue(store.candidates.isEmpty, "Raw diffs must never appear as approved terms")
    let proposals = store.unreviewedCandidates
    let decisions = proposals.map {
      VocabularyReviewDecision(
        candidateID: $0.id,
        action: $0.historyID == value.id ? .ordinaryEdit : .uncertain, term: nil)
    }
    let added = try store.applyReview(
      decisions, proposals: proposals, automaticallyAdd: true, now: now)
    XCTAssertTrue(added.isEmpty)
    XCTAssertTrue(store.words.isEmpty)
    XCTAssertTrue(store.candidates.isEmpty)
    XCTAssertTrue(store.unreviewedCandidates.isEmpty)
  }

  @MainActor
  func testOldHistoryApprovalStaysManualAndLateResultsCannotResurrectDeletedEvidence() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    let value = entry(before: "Open TypeList please", after: "Open typeless please")
    let now = value.completedAt.addingTimeInterval(1)
    store.refresh(from: [value], now: now)
    let proposals = store.unreviewedCandidates
    let decisions = proposals.map {
      VocabularyReviewDecision(candidateID: $0.id, action: .termCorrection, term: "typeless")
    }
    XCTAssertTrue(
      try store.applyReview(decisions, proposals: proposals, automaticallyAdd: false, now: now)
        .isEmpty)
    XCTAssertTrue(store.words.isEmpty)
    XCTAssertEqual(store.candidates.first?.correctedTerm, "typeless")
    XCTAssertEqual(store.candidates.first?.isSemanticallyReviewed, true)

    store.refresh(from: [], now: now)
    XCTAssertTrue(
      try store.applyReview(decisions, proposals: proposals, automaticallyAdd: true, now: now)
        .isEmpty)
    XCTAssertTrue(store.words.isEmpty)
    store.refresh(from: [value], now: now)
    try store.setCollectsEdits(false)
    XCTAssertTrue(
      try store.applyReview(decisions, proposals: proposals, automaticallyAdd: true, now: now)
        .isEmpty)
    XCTAssertTrue(store.words.isEmpty)
  }

  @MainActor
  func testCompletedReviewsSurviveReloadWithoutSkippingUncheckedEdits() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    try store.add("ChatGPT")
    let revisions = [
      entry(before: "Please open TypeList now", after: "Please open typeless now"),
      entry(before: "这里应该说清楚", after: "这里定义说清楚"),
      entry(before: "Please open aw day now", after: "Please open auday now"),
      entry(before: "Please open ChatGDP now", after: "Please open ChatGPT now"),
    ]
    let now = revisions[0].completedAt.addingTimeInterval(1)
    store.refresh(from: revisions, now: now)
    XCTAssertEqual(store.unreviewedCandidates.count, 4)
    let proposals = store.unreviewedCandidates
    let decisions = proposals.map { proposal in
      switch proposal.historyID {
      case revisions[1].id:
        VocabularyReviewDecision(candidateID: proposal.id, action: .ordinaryEdit, term: nil)
      case revisions[2].id:
        VocabularyReviewDecision(candidateID: proposal.id, action: .uncertain, term: nil)
      default:
        VocabularyReviewDecision(
          candidateID: proposal.id, action: .termCorrection, term: proposal.correctedTerm)
      }
    }
    _ = try store.applyReview(decisions, proposals: proposals, automaticallyAdd: false, now: now)

    let pending = entry(before: "Please open Harrow now", after: "Please open haro now")
    let reloaded = VocabularyStore(storageURL: root)
    reloaded.refresh(from: revisions + [pending], now: now)
    XCTAssertEqual(reloaded.unreviewedCandidates.map(\.historyID), [pending.id])
    XCTAssertEqual(reloaded.candidates.map(\.correctedTerm), ["typeless"])
    XCTAssertEqual(reloaded.words.map(\.term), ["ChatGPT"])
    try reloaded.confirm(try XCTUnwrap(reloaded.candidates.first), term: "typeless")

    let confirmed = VocabularyStore(storageURL: root)
    confirmed.refresh(from: revisions + [pending], now: now)
    XCTAssertEqual(confirmed.unreviewedCandidates.map(\.historyID), [pending.id])
    XCTAssertTrue(confirmed.candidates.isEmpty)
    XCTAssertEqual(Set(confirmed.words.map(\.term)), ["ChatGPT", "typeless"])
  }

  @MainActor
  func testReviewProgressSurvivesDisabledCollectionAndIsRemovedWithHistory() throws {
    for expires in [false, true] {
      let root = temporaryStorage()
      defer { try? FileManager.default.removeItem(at: root) }
      let store = VocabularyStore(storageURL: root)
      try store.add("Kept word")
      let revision = entry(before: "Please open TypeList now", after: "Please open typeless now")
      let now = revision.completedAt.addingTimeInterval(1)
      store.refresh(from: [revision], now: now)
      let proposal = try XCTUnwrap(store.unreviewedCandidates.first)
      _ = try store.applyReview(
        [VocabularyReviewDecision(candidateID: proposal.id, action: .uncertain, term: nil)],
        proposals: [proposal], automaticallyAdd: true, now: now)
      try store.setCollectsEdits(false)
      store.refresh(from: [revision], collectingEdits: false, now: now)

      let reloaded = VocabularyStore(storageURL: root)
      reloaded.refresh(from: [revision], now: now)
      try reloaded.setCollectsEdits(true)
      reloaded.refresh(from: [revision], now: now)
      XCTAssertTrue(reloaded.unreviewedCandidates.isEmpty)
      XCTAssertTrue(reloaded.candidates.isEmpty)

      reloaded.refresh(from: expires ? [revision] : [], now: expires ? revision.expiresAt : now)
      let persisted = try String(
        contentsOf: root.appendingPathComponent("vocabulary.json"), encoding: .utf8)
      XCTAssertFalse(
        persisted.contains(proposal.id), "Deleted or expired review metadata must be removed")
      XCTAssertFalse(
        persisted.contains("Please open"), "Review progress must not duplicate context")
      XCTAssertEqual(VocabularyStore(storageURL: root).words.map(\.term), ["Kept word"])
    }
  }

  @MainActor
  func testFailedManualReviewSaveDoesNotMarkAnEditAsChecked() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let blocked = root.appendingPathComponent("not-a-directory")
    try Data("occupied".utf8).write(to: blocked)
    let store = VocabularyStore(storageURL: blocked)
    let revision = entry(before: "这里应该说清楚", after: "这里定义说清楚")
    let now = revision.completedAt.addingTimeInterval(1)
    store.refresh(from: [revision], now: now)
    let proposal = try XCTUnwrap(store.unreviewedCandidates.first)
    let decision = VocabularyReviewDecision(
      candidateID: proposal.id, action: .ordinaryEdit, term: nil)
    XCTAssertThrowsError(
      try store.applyReview([decision], proposals: [proposal], automaticallyAdd: false, now: now))
    XCTAssertEqual(store.unreviewedCandidates.map(\.id), [proposal.id])

    try FileManager.default.removeItem(at: blocked)
    let reloaded = VocabularyStore(storageURL: blocked)
    reloaded.refresh(from: [revision], now: now)
    XCTAssertEqual(reloaded.unreviewedCandidates.map(\.id), [proposal.id])
    _ = try reloaded.applyReview(
      [decision], proposals: [proposal], automaticallyAdd: false, now: now)
    let checked = VocabularyStore(storageURL: blocked)
    checked.refresh(from: [revision], now: now)
    XCTAssertTrue(checked.unreviewedCandidates.isEmpty)
    XCTAssertTrue(checked.words.isEmpty)
  }

  @MainActor
  func testOutOfOrderReviewsAndChangedEditsRemainIndependentlyCheckable() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = VocabularyStore(storageURL: root)
    let older = entry(before: "Please open TypeList now", after: "Please open typeless now")
    var later = entry(before: "Please open AllDay now", after: "Please open auday now")
    later.submittedAt = later.completedAt.addingTimeInterval(10)
    let now = later.completedAt.addingTimeInterval(11)
    store.refresh(from: [older, later], now: now)
    let proposal = try XCTUnwrap(store.unreviewedCandidates.first { $0.historyID == later.id })
    _ = try store.applyReview(
      [VocabularyReviewDecision(candidateID: proposal.id, action: .termCorrection, term: "auday")],
      proposals: [proposal], automaticallyAdd: false, now: now)
    let reloaded = VocabularyStore(storageURL: root)
    reloaded.refresh(from: [older, later], now: now)
    XCTAssertEqual(reloaded.unreviewedCandidates.map(\.historyID), [older.id])
    XCTAssertEqual(reloaded.candidates.map(\.correctedTerm), ["auday"])

    later.submittedText = "Please open haro now"
    reloaded.refresh(from: [older, later], now: now)
    XCTAssertEqual(Set(reloaded.unreviewedCandidates.map(\.historyID)), [older.id, later.id])
    XCTAssertTrue(reloaded.candidates.isEmpty)
    let persisted = try String(
      contentsOf: root.appendingPathComponent("vocabulary.json"), encoding: .utf8)
    XCTAssertFalse(persisted.contains(proposal.id))
  }

  @MainActor
  func testOlderAutoAddedWordsDecodeAsUnreviewedAndAreNotDeleted() throws {
    let root = temporaryStorage()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let json = """
      {"words":[{"id":"1707A0EE-8936-46AA-8C40-FB758C589028","term":"ordinary phrase","source":"autoAdded","createdAt":"2026-10-13T00:00:00Z"}],"dismissedCandidateIDs":[],"collectsEdits":true}
      """
    try Data(json.utf8).write(to: root.appendingPathComponent("vocabulary.json"))
    let store = VocabularyStore(storageURL: root)
    XCTAssertEqual(store.words.first?.term, "ordinary phrase")
    XCTAssertNil(store.words.first?.reviewedByLLM)
    XCTAssertTrue(store.processingTerms.isEmpty)
    try store.update(try XCTUnwrap(store.words.first), term: "typeless")
    let confirmed = VocabularyStore(storageURL: root)
    XCTAssertEqual(confirmed.processingTerms, ["typeless"])
    XCTAssertEqual(confirmed.words.first?.source, .manual)
    XCTAssertNil(confirmed.words.first?.reviewedByLLM)
    try confirmed.setCollectsEdits(false)
    XCTAssertTrue(confirmed.processingTerms.isEmpty)
    try confirmed.setCollectsEdits(true)
    XCTAssertEqual(confirmed.processingTerms, ["typeless"])
  }

  func testReviewRequestUsesConfiguredAPIAndSeparateUntrustedPayload() async throws {
    let recorder = RequestRecorder()
    let (processor, baseConfiguration) = client(
      recorder: recorder,
      response: """
        {"decisions":[{"id":0,"action":"term_correction","term":"typeless"}]}
        """)
    var configuration = baseConfiguration
    configuration.vocabulary = ["INDEPENDENT_PROCESSING_WORD"]
    let proposal = candidate(before: "TypeList", after: "typeless")
    let decisions = try await processor.reviewVocabulary([proposal], configuration: configuration)
    XCTAssertEqual(decisions.first?.term, "typeless")
    let request = try XCTUnwrap(recorder.last)
    XCTAssertEqual(request.url.path, "/v1/chat/completions")
    XCTAssertEqual(request.authorization, "Bearer synthetic-key")
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    XCTAssertEqual(body["model"] as? String, "configured-test-model")
    let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
    XCTAssertEqual(messages.map { $0["role"]! }, ["system", "user"])
    XCTAssertFalse(messages[0]["content"]!.contains("UNRELATED_CUSTOM_PROMPT"))
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as? [String: Any])
    let edits = try XCTUnwrap(payload["edits"] as? [[String: Any]])
    XCTAssertEqual(edits[0]["id"] as? Int, 0)
    XCTAssertEqual(edits[0]["corrected_fragment"] as? String, "typeless")
    XCTAssertEqual(edits[0]["after_context"] as? String, proposal.correctedContext)
    XCTAssertFalse(
      String(decoding: request.body, as: UTF8.self).contains(proposal.historyID.uuidString))
    XCTAssertFalse(
      String(decoding: request.body, as: UTF8.self).contains("INDEPENDENT_PROCESSING_WORD"))
  }

  func testDictateSendsVocabularyAndSourceInTheSameRequest() async throws {
    let recorder = RequestRecorder()
    let (processor, baseConfiguration) = client(recorder: recorder, response: "Open auday.")
    var configuration = baseConfiguration
    configuration.vocabulary = ["auday", "typeless"]
    _ = try await processor.dictate("Open the AllDay app.", configuration: configuration)
    let request = try XCTUnwrap(recorder.last)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as? [String: Any])
    XCTAssertEqual(payload["source_text"] as? String, "Open the AllDay app.")
    XCTAssertEqual(payload["vocabulary"] as? [String], ["auday", "typeless"])
    XCTAssertEqual(messages.count, 2)
    XCTAssertTrue(messages[0]["content"]!.hasPrefix("UNRELATED_CUSTOM_PROMPT"))
  }

  func testBlankPromptWithNoVocabularyReturnsRawTextWithoutARequest() async throws {
    let recorder = RequestRecorder()
    let (processor, baseConfiguration) = client(recorder: recorder, response: "Unexpected response")
    let configuration = LLMConfiguration(
      baseURL: baseConfiguration.baseURL, apiKey: baseConfiguration.apiKey,
      model: baseConfiguration.model,
      dictatePrompt: "", translatePrompt: baseConfiguration.translatePrompt)
    let original = "um, um,  raw text\nwith spacing"
    let output = try await processor.dictate(original, configuration: configuration)
    XCTAssertEqual(output, original)
    XCTAssertNil(recorder.last)
  }

  func testDictateRequestRetainsItsSourceTextBoundary() async throws {
    let recorder = RequestRecorder()
    let (processor, configuration) = client(recorder: recorder, response: "Can you define this?")
    let output = try await processor.dictate("Can you define this?", configuration: configuration)
    XCTAssertEqual(output, "Can you define this?")
    let request = try XCTUnwrap(recorder.last)
    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
    XCTAssertTrue(messages[0]["content"]!.hasPrefix("UNRELATED_CUSTOM_PROMPT"))
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as? [String: String])
    XCTAssertEqual(payload, ["source_text": "Can you define this?"])
  }

  private func candidate(
    before: String, after: String, beforeContext: String? = nil, afterContext: String? = nil
  ) -> VocabularyCandidate {
    VocabularyCandidate(
      id: UUID().uuidString, historyID: UUID(), originalTerm: before,
      correctedTerm: after, originalContext: beforeContext ?? "Please open \(before) now",
      correctedContext: afterContext ?? "Please open \(after) now",
      observedAt: Date(timeIntervalSince1970: 2_000_000_000))
  }

  private func entry(before: String, after: String) -> HistoryEntry {
    HistoryEntry(
      id: UUID(), completedAt: Date(timeIntervalSince1970: 2_000_000_000), mode: .dictate,
      audioFileName: nil, rawTranscript: before, processedText: before, submittedText: after,
      submissionState: .confirmed, targetLanguage: nil, status: .succeeded,
      failureStage: nil, failureMessage: nil, usedRawFallback: false)
  }

  private func temporaryStorage() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
  }

  private func client(recorder: RequestRecorder, response: String) -> (
    OpenAICompatibleTextProcessor, LLMConfiguration
  ) {
    let host = UUID().uuidString.lowercased() + ".invalid"
    ReviewURLProtocol.registry.register(host: host, recorder: recorder, response: response)
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [ReviewURLProtocol.self]
    let processor = OpenAICompatibleTextProcessor(
      session: URLSession(configuration: sessionConfiguration))
    return (
      processor,
      LLMConfiguration(
        baseURL: "https://\(host)/v1", apiKey: "synthetic-key",
        model: "configured-test-model", dictatePrompt: "UNRELATED_CUSTOM_PROMPT",
        translatePrompt: "UNRELATED_TRANSLATE_PROMPT")
    )
  }
}

private final class RequestRecorder: @unchecked Sendable {
  struct Recorded {
    let url: URL
    let authorization: String?
    let body: Data
  }
  private let lock = NSLock()
  private var value: Recorded?
  var last: Recorded? { lock.withLock { value } }

  func record(_ request: URLRequest) {
    var body = request.httpBody ?? Data()
    if body.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 2048)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        body.append(contentsOf: buffer.prefix(count))
      }
    }
    let recorded = Recorded(
      url: request.url!, authorization: request.value(forHTTPHeaderField: "Authorization"),
      body: body)
    lock.withLock { value = recorded }
  }
}

private final class ReviewStubRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var stubs: [String: (RequestRecorder, String)] = [:]
  func register(host: String, recorder: RequestRecorder, response: String) {
    lock.withLock { stubs[host] = (recorder, response) }
  }
  func stub(for host: String) -> (RequestRecorder, String)? {
    lock.withLock { stubs.removeValue(forKey: host) }
  }
}

private final class ReviewURLProtocol: URLProtocol, @unchecked Sendable {
  static let registry = ReviewStubRegistry()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url, let host = url.host,
      let (recorder, output) = Self.registry.stub(for: host)
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    recorder.record(request)
    let body = try! JSONSerialization.data(withJSONObject: [
      "choices": [["message": ["content": output]]]
    ])
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
