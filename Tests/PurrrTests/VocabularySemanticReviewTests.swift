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
  }

  func testReviewRequestUsesConfiguredAPIAndSeparateUntrustedPayload() async throws {
    let recorder = RequestRecorder()
    let (processor, configuration) = client(
      recorder: recorder,
      response: """
        {"decisions":[{"id":0,"action":"term_correction","term":"typeless"}]}
        """)
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
