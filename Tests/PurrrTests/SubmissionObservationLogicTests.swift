import CoreGraphics
import XCTest

@testable import Purrr

final class SubmissionObservationLogicTests: XCTestCase {
  func testPlainReturnAndCommandReturnAreEditEndCandidates() {
    let plainReturn = SubmissionKeyEvent(keyCode: 36, flags: [], isRepeat: false)
    let commandReturn = SubmissionKeyEvent(
      keyCode: 36,
      flags: .maskCommand,
      isRepeat: false
    )

    XCTAssertEqual(SubmissionObservationLogic.evidence(for: plainReturn), .returnKey)
    XCTAssertEqual(SubmissionObservationLogic.evidence(for: commandReturn), .commandReturn)
  }

  func testShiftReturnAndRepeatedReturnAreNotEditEndCandidates() {
    let shiftReturn = SubmissionKeyEvent(
      keyCode: 36,
      flags: .maskShift,
      isRepeat: false
    )
    let repeatedReturn = SubmissionKeyEvent(keyCode: 36, flags: [], isRepeat: true)

    XCTAssertNil(SubmissionObservationLogic.evidence(for: shiftReturn))
    XCTAssertNil(SubmissionObservationLogic.evidence(for: repeatedReturn))
  }

  func testSemanticTargetSurvivesDynamicIdentifierAndHeightChanges() {
    let original = descriptor(
      elementIdentity: 10,
      identifier: "composer-v1",
      ancestors: [ancestor(role: "AXGroup", identifier: "composer-shell")],
      frame: CGRect(x: 100, y: 100, width: 500, height: 54)
    )
    let rerendered = descriptor(
      elementIdentity: 11,
      identifier: "composer-v2",
      ancestors: [ancestor(role: "AXGroup", identifier: "composer-shell")],
      frame: CGRect(x: 100, y: 72, width: 500, height: 110)
    )

    let match = original.match(rerendered)

    XCTAssertEqual(match.relationship, .sameControl)
    XCTAssertGreaterThanOrEqual(match.controlConfidence, 0.65)
  }

  func testDifferentWindowsAreDifferentTargetsEvenWhenControlMetadataMatches() {
    let original = descriptor(windowNumber: 7, identifier: "composer")
    let anotherWindow = descriptor(windowNumber: 8, identifier: "composer")

    XCTAssertEqual(original.match(anotherWindow).relationship, .differentControl)
  }

  func testFarSiblingWithoutStableIdentifiersIsNotAcceptedAsTheSameControl() {
    let original = descriptor(
      identifier: nil,
      ancestors: [ancestor(role: "AXGroup", identifier: "form")],
      frame: CGRect(x: 100, y: 100, width: 300, height: 50)
    )
    let sibling = descriptor(
      identifier: nil,
      ancestors: [ancestor(role: "AXGroup", identifier: "form")],
      frame: CGRect(x: 100, y: 500, width: 300, height: 50)
    )

    XCTAssertNotEqual(original.match(sibling).relationship, .sameControl)
  }

  func testLastNonEmptyRevisionIsCapturedAfterFieldRemainsCleared() {
    let target = descriptor(identifier: "composer")
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "Do you know TypeList?",
      target: target
    )

    _ = state.observe(text: "Do you know typeless?", target: target)

    XCTAssertEqual(state.observe(text: "", target: target), .continueTracking)
    XCTAssertEqual(
      state.observe(text: "", target: target),
      .confirmed(text: "Do you know typeless?", evidence: .fieldCleared)
    )
  }

  func testFocusChangeEndsEditingWithoutAKeyboardSubmissionGesture() {
    let composer = descriptor(identifier: "composer")
    let toolbar = descriptor(
      role: kAXButtonRole as String,
      identifier: "toolbar",
      frame: CGRect(x: 20, y: 20, width: 30, height: 30)
    )
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "Final wording",
      target: composer
    )
    _ = state.observe(text: "Final wording with edit", target: composer)

    XCTAssertEqual(state.observe(text: nil, target: toolbar), .continueTracking)
    XCTAssertEqual(
      state.observe(text: nil, target: toolbar),
      .confirmed(text: "Final wording with edit", evidence: .focusChanged)
    )
  }

  func testPointerInteractionCapturesThePreClickTextWhenFocusMoves() {
    let composer = descriptor(identifier: "composer")
    let sendButton = descriptor(
      role: kAXButtonRole as String,
      identifier: "action",
      frame: CGRect(x: 620, y: 100, width: 30, height: 30)
    )
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "Draft",
      target: composer
    )
    _ = state.observe(text: "Edited draft", target: composer)
    _ = state.beginInteraction(
      evidence: .pointerInteraction,
      snapshotText: "Edited draft",
      snapshotTarget: composer
    )

    XCTAssertEqual(
      state.observe(text: nil, target: sendButton),
      .confirmed(text: "Edited draft", evidence: .pointerInteraction)
    )
  }

  func testReturnThatInsertsANewlineContinuesTheEditingSession() {
    let target = descriptor(identifier: "editor")
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "First line",
      target: target
    )
    _ = state.observe(text: "First line", target: target)
    _ = state.beginInteraction(
      evidence: .returnKey,
      snapshotText: "First line",
      snapshotTarget: target
    )

    XCTAssertEqual(
      state.observe(text: "First line\n", target: target),
      .continueTracking
    )
    XCTAssertFalse(state.hasPendingCandidate)
    XCTAssertEqual(state.lastNonEmptyText, "First line\n")
  }

  func testSingleLineReturnEndsEditingImmediately() {
    let target = descriptor(role: kAXTextFieldRole as String, identifier: "address")
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "openai.com",
      target: target
    )

    XCTAssertEqual(
      state.beginInteraction(
        evidence: .returnKey,
        snapshotText: "openai.com",
        snapshotTarget: target
      ),
      .confirmed(text: "openai.com", evidence: .returnKey)
    )
  }

  func testInactivityEndsAReadableEditedSession() {
    let target = descriptor(identifier: "composer")
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "Generated text",
      target: target
    )
    _ = state.observe(text: "Generated text", target: target)
    _ = state.observe(text: "User's final edit", target: target)

    XCTAssertEqual(
      state.concludeEditing(evidence: .inactivity),
      .confirmed(text: "User's final edit", evidence: .inactivity)
    )
  }

  func testInactivityDoesNotGuessWhenNoInsertedValueWasEverReadable() {
    let target = descriptor(identifier: "composer")
    var state = SubmissionTrackingState(
      initialValue: "",
      processedText: "Generated text",
      target: target
    )

    XCTAssertEqual(
      state.concludeEditing(evidence: .inactivity),
      .continueTracking
    )
  }

  private func descriptor(
    windowNumber: Int = 7,
    elementIdentity: UInt = 0,
    role: String = kAXTextAreaRole as String,
    identifier: String?,
    ancestors: [SubmissionTargetDescriptor.Ancestor] = [],
    frame: CGRect = CGRect(x: 100, y: 100, width: 500, height: 80)
  ) -> SubmissionTargetDescriptor {
    SubmissionTargetDescriptor(
      processIdentifier: 42,
      bundleIdentifier: "com.example.editor",
      elementIdentity: elementIdentity,
      windowNumber: windowNumber,
      windowIdentifier: "main-window-\(windowNumber)",
      windowTitle: "Document",
      documentIdentifier: "document://current",
      role: role,
      identifier: identifier,
      capabilities: ["settable-value", "selected-text-range"],
      ancestors: ancestors,
      frame: frame
    )
  }

  private func ancestor(
    role: String,
    identifier: String
  ) -> SubmissionTargetDescriptor.Ancestor {
    SubmissionTargetDescriptor.Ancestor(
      role: role,
      subrole: nil,
      identifier: identifier,
      domIdentifier: nil
    )
  }
}
