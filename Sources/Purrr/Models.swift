import AppKit
import Foundation

enum SessionMode: String, Codable, CaseIterable, Identifiable {
  case dictate
  case translate

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dictate: "Dictate"
    case .translate: "Translate"
    }
  }

  var symbol: String {
    switch self {
    case .dictate: "waveform"
    case .translate: "character.bubble"
    }
  }
}

enum SessionPhase: Equatable {
  case idle
  case recording
  case recognizing
  case processing
  case delivering
  case succeeded
  case failed(String)

  var isActive: Bool {
    self != .idle
  }
}

enum TranslationLanguage: String, Codable, CaseIterable, Identifiable {
  case english
  case simplifiedChinese

  var id: String { rawValue }

  var title: String {
    switch self {
    case .english: "English"
    case .simplifiedChinese: "Simplified Chinese"
    }
  }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
  let rawValue: UInt

  static let command = ShortcutModifiers(rawValue: 1 << 0)
  static let control = ShortcutModifiers(rawValue: 1 << 1)
  static let option = ShortcutModifiers(rawValue: 1 << 2)
  static let shift = ShortcutModifiers(rawValue: 1 << 3)

  init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  init(eventFlags: NSEvent.ModifierFlags) {
    var value: ShortcutModifiers = []
    if eventFlags.contains(.command) { value.insert(.command) }
    if eventFlags.contains(.control) { value.insert(.control) }
    if eventFlags.contains(.option) { value.insert(.option) }
    if eventFlags.contains(.shift) { value.insert(.shift) }
    self = value
  }

  var symbols: String {
    var value = ""
    if contains(.control) { value += "⌃" }
    if contains(.option) { value += "⌥" }
    if contains(.shift) { value += "⇧" }
    if contains(.command) { value += "⌘" }
    return value
  }
}

struct AppShortcut: Codable, Hashable {
  let keyCode: UInt32
  let modifiers: ShortcutModifiers
  let keyLabel: String

  static let dictateDefault = AppShortcut(
    keyCode: 49,
    modifiers: [.option],
    keyLabel: "Space"
  )

  static let translateDefault = AppShortcut(
    keyCode: 49,
    modifiers: [.option, .shift],
    keyLabel: "Space"
  )

  var displayName: String {
    "\(modifiers.symbols)\(keyLabel)"
  }

  var isValid: Bool {
    !modifiers.isEmpty && keyCode != 53
  }
}

enum HistoryStatus: String, Codable {
  case succeeded
  case failed
  case dismissed
  case retrying
}

enum FailureStage: String, Codable {
  case speechRecognition
  case languageModel
  case delivery
}

enum SubmissionState: String, Codable {
  case notObserved
  case pending
  case confirmed
  case unknown
  case cancelled
}

enum SubmissionEvidence: String, Codable {
  case returnKey
  case commandReturn
  case pointerInteraction
  case fieldCleared
  case focusChanged
  case inactivity
}

enum SubmissionObservationOutcome: Equatable {
  case confirmed(text: String, evidence: SubmissionEvidence, submittedAt: Date)
  case unknown
}

struct HistoryEntry: Identifiable, Codable, Equatable {
  let id: UUID
  let completedAt: Date
  var mode: SessionMode
  var audioFileName: String?
  var rawTranscript: String?
  var processedText: String?
  var submittedText: String?
  var submissionState: SubmissionState
  var submittedAt: Date?
  var submissionEvidence: SubmissionEvidence?
  var targetLanguage: TranslationLanguage?
  var status: HistoryStatus
  var failureStage: FailureStage?
  var failureMessage: String?
  var usedRawFallback: Bool

  init(
    id: UUID,
    completedAt: Date,
    mode: SessionMode,
    audioFileName: String?,
    rawTranscript: String?,
    processedText: String?,
    submittedText: String? = nil,
    submissionState: SubmissionState = .notObserved,
    submittedAt: Date? = nil,
    submissionEvidence: SubmissionEvidence? = nil,
    targetLanguage: TranslationLanguage?,
    status: HistoryStatus,
    failureStage: FailureStage?,
    failureMessage: String?,
    usedRawFallback: Bool
  ) {
    self.id = id
    self.completedAt = completedAt
    self.mode = mode
    self.audioFileName = audioFileName
    self.rawTranscript = rawTranscript
    self.processedText = processedText
    self.submittedText = submittedText
    self.submissionState = submissionState
    self.submittedAt = submittedAt
    self.submissionEvidence = submissionEvidence
    self.targetLanguage = targetLanguage
    self.status = status
    self.failureStage = failureStage
    self.failureMessage = failureMessage
    self.usedRawFallback = usedRawFallback
  }

  var expiresAt: Date {
    completedAt.addingTimeInterval(24 * 60 * 60)
  }

  var preferredCopyText: String? {
    let submitted = submittedText?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let submitted, !submitted.isEmpty { return submitted }
    let processed = processedText?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let processed, !processed.isEmpty { return processed }
    let transcript = rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let transcript, !transcript.isEmpty { return transcript }
    return nil
  }

  mutating func resetSubmissionObservation() {
    submittedText = nil
    submissionState = .notObserved
    submittedAt = nil
    submissionEvidence = nil
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case completedAt
    case mode
    case audioFileName
    case rawTranscript
    case processedText
    case submittedText
    case submissionState
    case submittedAt
    case submissionEvidence
    case targetLanguage
    case status
    case failureStage
    case failureMessage
    case usedRawFallback
    case sourceText
    case deliveredText
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    completedAt = try values.decode(Date.self, forKey: .completedAt)
    mode = try values.decode(SessionMode.self, forKey: .mode)
    audioFileName = try values.decodeIfPresent(String.self, forKey: .audioFileName)
    rawTranscript =
      try values.decodeIfPresent(String.self, forKey: .rawTranscript)
      ?? (try values.decodeIfPresent(String.self, forKey: .sourceText))
    processedText =
      try values.decodeIfPresent(String.self, forKey: .processedText)
      ?? (try values.decodeIfPresent(String.self, forKey: .deliveredText))
    submittedText = try values.decodeIfPresent(String.self, forKey: .submittedText)
    let decodedSubmissionState =
      try values.decodeIfPresent(SubmissionState.self, forKey: .submissionState)
      ?? .notObserved
    submissionState = decodedSubmissionState == .pending ? .unknown : decodedSubmissionState
    submittedAt = try values.decodeIfPresent(Date.self, forKey: .submittedAt)
    submissionEvidence = try values.decodeIfPresent(
      SubmissionEvidence.self,
      forKey: .submissionEvidence
    )
    targetLanguage = try values.decodeIfPresent(
      TranslationLanguage.self,
      forKey: .targetLanguage
    )
    status = try values.decode(HistoryStatus.self, forKey: .status)
    failureStage = try values.decodeIfPresent(FailureStage.self, forKey: .failureStage)
    failureMessage = try values.decodeIfPresent(String.self, forKey: .failureMessage)
    usedRawFallback = try values.decodeIfPresent(Bool.self, forKey: .usedRawFallback) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(completedAt, forKey: .completedAt)
    try values.encode(mode, forKey: .mode)
    try values.encodeIfPresent(audioFileName, forKey: .audioFileName)
    try values.encodeIfPresent(rawTranscript, forKey: .rawTranscript)
    try values.encodeIfPresent(processedText, forKey: .processedText)
    try values.encodeIfPresent(submittedText, forKey: .submittedText)
    try values.encode(submissionState, forKey: .submissionState)
    try values.encodeIfPresent(submittedAt, forKey: .submittedAt)
    try values.encodeIfPresent(submissionEvidence, forKey: .submissionEvidence)
    try values.encodeIfPresent(targetLanguage, forKey: .targetLanguage)
    try values.encode(status, forKey: .status)
    try values.encodeIfPresent(failureStage, forKey: .failureStage)
    try values.encodeIfPresent(failureMessage, forKey: .failureMessage)
    try values.encode(usedRawFallback, forKey: .usedRawFallback)
  }
}

struct AudioRecording {
  let pcmData: Data
  let duration: TimeInterval
}

struct CapturedDestination {
  let processIdentifier: pid_t
  let bundleIdentifier: String?
  let focusedElement: AXUIElement?
}
