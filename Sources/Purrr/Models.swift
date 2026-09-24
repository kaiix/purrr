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

struct HistoryEntry: Identifiable, Codable, Equatable {
  let id: UUID
  let completedAt: Date
  var mode: SessionMode
  var audioFileName: String?
  var sourceText: String?
  var deliveredText: String?
  var targetLanguage: TranslationLanguage?
  var status: HistoryStatus
  var failureStage: FailureStage?
  var failureMessage: String?
  var usedRawFallback: Bool

  var expiresAt: Date {
    completedAt.addingTimeInterval(24 * 60 * 60)
  }

  var preferredCopyText: String? {
    let delivered = deliveredText?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let delivered, !delivered.isEmpty { return delivered }
    let source = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let source, !source.isEmpty { return source }
    return nil
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
