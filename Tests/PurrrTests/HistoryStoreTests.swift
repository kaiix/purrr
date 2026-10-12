import Foundation
import XCTest

@testable import Purrr

final class HistoryStoreTests: XCTestCase {
  func testLegacyHistoryDecodesIntoRawAndProcessedStages() throws {
    let data = Data(
      """
      {
        "id": "1707A0EE-8936-46AA-8C40-FB758C589028",
        "completedAt": "2026-09-30T10:15:30Z",
        "mode": "dictate",
        "sourceText": "TypeList is useful",
        "deliveredText": "TypeList is useful.",
        "status": "succeeded",
        "usedRawFallback": false
      }
      """.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let entry = try decoder.decode(HistoryEntry.self, from: data)

    XCTAssertEqual(entry.rawTranscript, "TypeList is useful")
    XCTAssertEqual(entry.processedText, "TypeList is useful.")
    XCTAssertNil(entry.submittedText)
    XCTAssertEqual(entry.submissionState, .notObserved)
  }

  @MainActor
  func testConfirmedSubmissionPersistsAndBecomesPreferredCopyText() throws {
    let storageURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: storageURL) }

    let store = HistoryStore(storageURL: storageURL)
    let id = store.add(
      mode: .dictate,
      recording: nil,
      rawTranscript: "Do you know TypeList?",
      processedText: "Do you know TypeList?",
      targetLanguage: nil,
      status: .succeeded
    )

    store.applySubmissionOutcome(
      id: id,
      outcome: .confirmed(
        text: "Do you know typeless?",
        evidence: .returnKey,
        submittedAt: Date(timeIntervalSince1970: 1_795_000_000)
      )
    )

    let reloaded = HistoryStore(storageURL: storageURL)
    let entry = try XCTUnwrap(reloaded.entry(id: id))
    XCTAssertEqual(entry.submittedText, "Do you know typeless?")
    XCTAssertEqual(entry.submissionState, .confirmed)
    XCTAssertEqual(entry.submissionEvidence, .returnKey)
    XCTAssertEqual(entry.preferredCopyText, "Do you know typeless?")
  }
}
