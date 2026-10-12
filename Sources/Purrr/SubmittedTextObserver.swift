import AppKit
import ApplicationServices
import Foundation
import OSLog

private func submittedTextAccessibilityChanged(
  _ observer: AXObserver,
  _ element: AXUIElement,
  _ notification: CFString,
  _ refcon: UnsafeMutableRawPointer?
) {
  guard let refcon else { return }
  let textObserver = Unmanaged<SubmittedTextObserver>.fromOpaque(refcon).takeUnretainedValue()
  textObserver.handleAccessibilityChange()
}

struct SubmissionKeyEvent {
  let keyCode: UInt32
  let flags: CGEventFlags
  let isRepeat: Bool
}

enum SubmissionObservationLogic {
  static func isReturnKey(_ keyCode: UInt32) -> Bool {
    keyCode == 36 || keyCode == 76
  }

  static func evidence(for event: SubmissionKeyEvent) -> SubmissionEvidence? {
    guard !event.isRepeat, isReturnKey(event.keyCode) else { return nil }
    let modifiers = event.flags.intersection([
      .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ])
    if modifiers.isEmpty {
      return .returnKey
    }
    if modifiers == .maskCommand {
      return .commandReturn
    }
    return nil
  }

  static func shouldRefreshAfterKey(_ event: SubmissionKeyEvent) -> Bool {
    guard !event.isRepeat else { return false }
    switch event.keyCode {
    case 0...51, 65...92, 115...126:
      return true
    default:
      return false
    }
  }

  static func normalizeForComparison(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(
        of: "[\u{200B}-\u{200F}\u{FEFF}]",
        with: "",
        options: .regularExpression
      )
  }

  static func containsInsertedText(_ value: String, processedText: String) -> Bool {
    let normalizedValue = normalizeForInsertionMatching(value)
    let normalizedProcessedText = normalizeForInsertionMatching(processedText)
    return !normalizedProcessedText.isEmpty && normalizedValue.contains(normalizedProcessedText)
  }

  static func hasTextContinuity(_ previous: String, _ current: String) -> Bool {
    let lhs = Array(normalizeForInsertionMatching(previous).lowercased())
    let rhs = Array(normalizeForInsertionMatching(current).lowercased())
    guard !lhs.isEmpty, !rhs.isEmpty else { return false }
    if lhs == rhs { return true }
    if lhs.count >= rhs.count, String(lhs).contains(String(rhs)) { return true }
    if rhs.count >= lhs.count, String(rhs).contains(String(lhs)) { return true }

    let smallerCount = min(lhs.count, rhs.count)
    let largerCount = max(lhs.count, rhs.count)
    guard Double(smallerCount) / Double(largerCount) >= 0.5 else { return false }

    var prefix = 0
    while prefix < smallerCount, lhs[prefix] == rhs[prefix] {
      prefix += 1
    }
    var suffix = 0
    while suffix < smallerCount - prefix,
      lhs[lhs.count - suffix - 1] == rhs[rhs.count - suffix - 1]
    {
      suffix += 1
    }
    return Double(prefix + suffix) / Double(largerCount) >= 0.45
  }

  private static func normalizeForInsertionMatching(_ text: String) -> String {
    normalizeForComparison(text)
      .components(separatedBy: .whitespacesAndNewlines)
      .joined()
  }
}

enum SubmissionTrackingDecision: Equatable {
  case continueTracking
  case confirmed(text: String, evidence: SubmissionEvidence)
}

struct SubmissionTrackingState {
  private struct Candidate: Equatable {
    let text: String
    let evidence: SubmissionEvidence
  }

  private let initialValue: String
  private let processedText: String
  private(set) var target: SubmissionTargetDescriptor
  private(set) var lastNonEmptyText: String?
  private var hasObservedTrackedText = false
  private var candidate: Candidate?

  init(
    initialValue: String,
    processedText: String,
    target: SubmissionTargetDescriptor
  ) {
    self.initialValue = initialValue
    self.processedText = processedText
    self.target = target
  }

  var hasPendingCandidate: Bool {
    candidate != nil
  }

  mutating func observe(
    text snapshotText: String?,
    target snapshotTarget: SubmissionTargetDescriptor
  ) -> SubmissionTrackingDecision {
    let text = snapshotText ?? ""
    let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let targetMatch = target.match(snapshotTarget)
    let hasLineage = hasText && valueHasTrackedLineage(text)
    let sameTarget =
      targetMatch.relationship == .sameControl
      || (targetMatch.relationship == .uncertain && hasLineage)

    if !sameTarget, hasLineage, snapshotTarget.isEditable {
      target = snapshotTarget
      updateTrackedText(text)
      if let candidate,
        SubmissionObservationLogic.normalizeForComparison(text)
          != SubmissionObservationLogic.normalizeForComparison(candidate.text)
      {
        self.candidate = nil
      }
      return .continueTracking
    }

    if !sameTarget {
      if let candidate {
        return .confirmed(text: candidate.text, evidence: candidate.evidence)
      }
      if let lastNonEmptyText {
        candidate = Candidate(text: lastNonEmptyText, evidence: .focusChanged)
      }
      return .continueTracking
    }

    if !hasText {
      if let candidate {
        return .confirmed(text: candidate.text, evidence: candidate.evidence)
      }
      if let lastNonEmptyText {
        candidate = Candidate(text: lastNonEmptyText, evidence: .fieldCleared)
      }
      return .continueTracking
    }

    if let candidate,
      SubmissionObservationLogic.normalizeForComparison(text)
        != SubmissionObservationLogic.normalizeForComparison(candidate.text)
    {
      self.candidate = nil
    }

    if hasObservedTrackedText || valueHasTrackedLineage(text) {
      target = snapshotTarget
      updateTrackedText(text)
    }
    return .continueTracking
  }

  mutating func beginInteraction(
    evidence: SubmissionEvidence,
    snapshotText: String?,
    snapshotTarget: SubmissionTargetDescriptor?
  ) -> SubmissionTrackingDecision {
    if let snapshotTarget {
      let decision = observe(text: snapshotText, target: snapshotTarget)
      if case .confirmed = decision {
        return decision
      }
    }

    let permitsProcessedFallback = evidence == .returnKey || evidence == .commandReturn
    guard let finalText = finalText(allowProcessedFallback: permitsProcessedFallback) else {
      return .continueTracking
    }
    if evidence == .commandReturn
      || (evidence == .returnKey && target.controlKind == .singleLine)
    {
      return .confirmed(text: finalText, evidence: evidence)
    }
    candidate = Candidate(text: finalText, evidence: evidence)
    return .continueTracking
  }

  mutating func concludeEditing(
    evidence: SubmissionEvidence
  ) -> SubmissionTrackingDecision {
    if let candidate {
      return .confirmed(text: candidate.text, evidence: candidate.evidence)
    }
    guard let finalText = finalText(allowProcessedFallback: false) else {
      return .continueTracking
    }
    return .confirmed(text: finalText, evidence: evidence)
  }

  mutating func cancelInteractionCandidate() {
    candidate = nil
  }

  private mutating func updateTrackedText(_ text: String) {
    hasObservedTrackedText = true
    lastNonEmptyText = text
  }

  private func valueHasTrackedLineage(_ text: String) -> Bool {
    if let lastNonEmptyText,
      SubmissionObservationLogic.hasTextContinuity(lastNonEmptyText, text)
    {
      return true
    }
    return SubmissionObservationLogic.containsInsertedText(text, processedText: processedText)
      || SubmissionObservationLogic.hasTextContinuity(processedText, text)
  }

  private func finalText(allowProcessedFallback: Bool) -> String? {
    if let lastNonEmptyText,
      !lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return lastNonEmptyText
    }
    if allowProcessedFallback,
      initialValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return processedText
    }
    return nil
  }
}

final class SubmittedTextObserver {
  private static let logger = Logger(
    subsystem: "io.github.kaiix.purrr",
    category: "SubmittedTextObserver"
  )

  struct PreparedObservation {
    fileprivate let destination: CapturedDestination
    fileprivate let initialValue: String
    fileprivate let processedText: String
    fileprivate let target: SubmissionTargetDescriptor
  }

  var onUpdate: ((UUID, SubmissionObservationOutcome) -> Void)?

  private final class Observation {
    let entryID: UUID
    let prepared: PreparedObservation
    var trackingState: SubmissionTrackingState
    var timeout: DispatchWorkItem?
    var poll: DispatchWorkItem?
    var keyRefresh: DispatchWorkItem?
    var confirmationChecks: [DispatchWorkItem] = []
    var accessibilityObserver: AXObserver?
    var runLoopSource: CFRunLoopSource?
    var applicationElement: AXUIElement?
    var observedElement: AXUIElement?
    var observesValueChanges = false
    var observesFocusChanges = false

    init(entryID: UUID, prepared: PreparedObservation) {
      self.entryID = entryID
      self.prepared = prepared
      trackingState = SubmissionTrackingState(
        initialValue: prepared.initialValue,
        processedText: prepared.processedText,
        target: prepared.target
      )
    }
  }

  private static let inactivityDuration: TimeInterval = 15
  private static let pollingInterval: TimeInterval = 1
  private static let initialReadDelay: TimeInterval = 0.2
  private static let keyRefreshDelay: TimeInterval = 0.1
  private static let interactionCheckDelays: [TimeInterval] = [0.05, 0.15, 0.35, 0.75]
  private static let inferredEndCheckDelays: [TimeInterval] = [0.35, 0.75]

  private var observation: Observation?
  private var applicationActivationObserver: NSObjectProtocol?

  init() {
    applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self,
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
        let observation = self.observation
      else {
        return
      }
      if application.processIdentifier != observation.prepared.destination.processIdentifier {
        self.finishAfterDestinationLoss(observation)
      } else {
        self.poll(observation)
      }
    }
  }

  deinit {
    if let applicationActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
    }
    if let observation {
      tearDown(observation)
    }
  }

  func prepare(
    destination: CapturedDestination?,
    processedText: String
  ) -> PreparedObservation? {
    guard AXIsProcessTrusted(),
      !processedText.isEmpty,
      let destination,
      NSWorkspace.shared.frontmostApplication?.processIdentifier
        == destination.processIdentifier,
      let originalElement = destination.focusedElement
    else {
      return nil
    }

    let snapshot =
      AccessibilityReader.focusedTextSnapshot(
        processIdentifier: destination.processIdentifier
      )
      ?? AccessibilityReader.textSnapshot(
        startingAt: originalElement,
        processIdentifier: destination.processIdentifier
      )
    guard let snapshot else { return nil }

    return PreparedObservation(
      destination: destination,
      initialValue: snapshot.text ?? "",
      processedText: processedText,
      target: snapshot.target
    )
  }

  @discardableResult
  func start(entryID: UUID, prepared: PreparedObservation) -> Bool {
    finishCurrent(as: .unknown)

    let next = Observation(entryID: entryID, prepared: prepared)
    observation = next
    installAccessibilityObserver(for: next)
    resetInactivityTimer(for: next)
    schedulePoll(for: next, after: Self.initialReadDelay)
    Self.logger.notice("Started final-edit tracking")
    return true
  }

  func handleKeyDown(_ event: SubmissionKeyEvent) {
    guard let observation,
      NSWorkspace.shared.frontmostApplication?.processIdentifier
        == observation.prepared.destination.processIdentifier
    else {
      return
    }

    if let evidence = SubmissionObservationLogic.evidence(for: event) {
      resetInactivityTimer(for: observation)
      let snapshot = currentSnapshot(for: observation)
      let decision = observation.trackingState.beginInteraction(
        evidence: evidence,
        snapshotText: snapshot?.text,
        snapshotTarget: snapshot?.target
      )
      if apply(decision, to: observation) {
        return
      }
      Self.logger.notice("Observed a keyboard edit-end candidate")
      scheduleConfirmationChecks(
        for: observation,
        delays: Self.interactionCheckDelays
      )
      return
    }

    guard SubmissionObservationLogic.shouldRefreshAfterKey(event) else { return }
    resetInactivityTimer(for: observation)
    scheduleKeyRefresh(for: observation)
  }

  func handlePointerDown(at _: CGPoint) {
    guard let observation,
      NSWorkspace.shared.frontmostApplication?.processIdentifier
        == observation.prepared.destination.processIdentifier
    else {
      return
    }

    resetInactivityTimer(for: observation)
    let snapshot = currentSnapshot(for: observation)
    let decision = observation.trackingState.beginInteraction(
      evidence: .pointerInteraction,
      snapshotText: snapshot?.text,
      snapshotTarget: snapshot?.target
    )
    if apply(decision, to: observation) {
      return
    }
    scheduleConfirmationChecks(for: observation, delays: Self.interactionCheckDelays)
  }

  func stop() {
    finishCurrent(as: .unknown)
  }

  fileprivate func handleAccessibilityChange() {
    guard let observation else { return }
    poll(observation)
  }

  @discardableResult
  private func poll(_ observation: Observation) -> Bool {
    guard self.observation === observation else { return false }
    guard
      NSWorkspace.shared.frontmostApplication?.processIdentifier
        == observation.prepared.destination.processIdentifier
    else {
      finishAfterDestinationLoss(observation)
      return false
    }
    guard let snapshot = currentSnapshot(for: observation) else { return false }
    updateObservedElement(snapshot.element, for: observation)
    let didFinish = apply(
      observation.trackingState.observe(text: snapshot.text, target: snapshot.target),
      to: observation
    )
    if !didFinish,
      self.observation === observation,
      observation.trackingState.hasPendingCandidate,
      observation.confirmationChecks.isEmpty
    {
      scheduleConfirmationChecks(
        for: observation,
        delays: Self.inferredEndCheckDelays
      )
    }
    return true
  }

  @discardableResult
  private func apply(
    _ decision: SubmissionTrackingDecision,
    to observation: Observation
  ) -> Bool {
    guard self.observation === observation else { return true }
    switch decision {
    case .continueTracking:
      return false
    case .confirmed(let text, let evidence):
      finish(
        observation,
        outcome: .confirmed(text: text, evidence: evidence, submittedAt: Date())
      )
      Self.logger.notice("Captured the final text when editing ended")
      return true
    }
  }

  private func currentSnapshot(for observation: Observation) -> AccessibleTextSnapshot? {
    AccessibilityReader.focusedTextSnapshot(
      processIdentifier: observation.prepared.destination.processIdentifier
    )
  }

  private func schedulePoll(for observation: Observation, after delay: TimeInterval) {
    observation.poll?.cancel()
    let work = DispatchWorkItem { [weak self, weak observation] in
      guard let self, let observation, self.observation === observation else { return }
      self.poll(observation)
      if self.observation === observation {
        self.schedulePoll(for: observation, after: Self.pollingInterval)
      }
    }
    observation.poll = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func scheduleKeyRefresh(for observation: Observation) {
    observation.keyRefresh?.cancel()
    let work = DispatchWorkItem { [weak self, weak observation] in
      guard let self, let observation, self.observation === observation else { return }
      self.poll(observation)
    }
    observation.keyRefresh = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyRefreshDelay, execute: work)
  }

  private func scheduleConfirmationChecks(
    for observation: Observation,
    delays: [TimeInterval]
  ) {
    for work in observation.confirmationChecks {
      work.cancel()
    }
    observation.confirmationChecks.removeAll()

    for (index, delay) in delays.enumerated() {
      let work = DispatchWorkItem { [weak self, weak observation] in
        guard let self, let observation, self.observation === observation else { return }
        self.poll(observation)
        guard self.observation === observation, index == delays.count - 1 else { return }
        observation.trackingState.cancelInteractionCandidate()
        observation.confirmationChecks.removeAll()
      }
      observation.confirmationChecks.append(work)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
  }

  private func resetInactivityTimer(for observation: Observation) {
    observation.timeout?.cancel()
    let timeout = DispatchWorkItem { [weak self, weak observation] in
      guard let self, let observation, self.observation === observation else { return }
      let decision = observation.trackingState.concludeEditing(evidence: .inactivity)
      if !self.apply(decision, to: observation) {
        self.finish(observation, outcome: .unknown)
      }
    }
    observation.timeout = timeout
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.inactivityDuration,
      execute: timeout
    )
  }

  private func installAccessibilityObserver(for observation: Observation) {
    var accessibilityObserver: AXObserver?
    guard
      AXObserverCreate(
        observation.prepared.destination.processIdentifier,
        submittedTextAccessibilityChanged,
        &accessibilityObserver
      ) == .success,
      let accessibilityObserver
    else {
      Self.logger.notice("Accessibility notifications unavailable; using polling")
      return
    }

    let applicationElement = AXUIElementCreateApplication(
      observation.prepared.destination.processIdentifier
    )
    observation.accessibilityObserver = accessibilityObserver
    observation.applicationElement = applicationElement

    if AXObserverAddNotification(
      accessibilityObserver,
      applicationElement,
      kAXFocusedUIElementChangedNotification as CFString,
      Unmanaged.passUnretained(self).toOpaque()
    ) == .success {
      observation.observesFocusChanges = true
    }

    if let element = observation.prepared.destination.focusedElement {
      updateObservedElement(element, for: observation)
    }

    let source = AXObserverGetRunLoopSource(accessibilityObserver)
    observation.runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }

  private func updateObservedElement(_ element: AXUIElement, for observation: Observation) {
    guard let accessibilityObserver = observation.accessibilityObserver else { return }
    if let observedElement = observation.observedElement, CFEqual(observedElement, element) {
      return
    }
    if observation.observesValueChanges, let observedElement = observation.observedElement {
      AXObserverRemoveNotification(
        accessibilityObserver,
        observedElement,
        kAXValueChangedNotification as CFString
      )
    }
    observation.observedElement = element
    observation.observesValueChanges =
      AXObserverAddNotification(
        accessibilityObserver,
        element,
        kAXValueChangedNotification as CFString,
        Unmanaged.passUnretained(self).toOpaque()
      ) == .success
  }

  private func tearDown(_ observation: Observation) {
    observation.timeout?.cancel()
    observation.poll?.cancel()
    observation.keyRefresh?.cancel()
    for work in observation.confirmationChecks {
      work.cancel()
    }

    if let accessibilityObserver = observation.accessibilityObserver {
      if observation.observesValueChanges, let element = observation.observedElement {
        AXObserverRemoveNotification(
          accessibilityObserver,
          element,
          kAXValueChangedNotification as CFString
        )
      }
      if observation.observesFocusChanges, let applicationElement = observation.applicationElement {
        AXObserverRemoveNotification(
          accessibilityObserver,
          applicationElement,
          kAXFocusedUIElementChangedNotification as CFString
        )
      }
    }
    if let source = observation.runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
  }

  private func finishCurrent(as outcome: SubmissionObservationOutcome) {
    guard let observation else { return }
    finish(observation, outcome: outcome)
  }

  private func finishAfterDestinationLoss(_ observation: Observation) {
    let decision = observation.trackingState.concludeEditing(evidence: .focusChanged)
    if apply(decision, to: observation) {
      return
    }
    finish(observation, outcome: .unknown)
  }

  private func finish(
    _ observation: Observation,
    outcome: SubmissionObservationOutcome
  ) {
    guard self.observation === observation else { return }
    tearDown(observation)
    self.observation = nil
    if outcome == .unknown {
      Self.logger.notice("Ended final-edit tracking without a readable edited value")
    }
    onUpdate?(observation.entryID, outcome)
  }
}
