import AVFoundation
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var settings: AppSettings

  var body: some View {
    if let blocker {
      Button(blocker.title) {
        model.settingsTab = blocker.tab
        model.showSettings()
      }
      Divider()
    }

    modeButton(.dictate, shortcut: settings.dictateShortcut)
    modeButton(.translate, shortcut: settings.translateShortcut)
    if [.recording, .recognizing, .processing].contains(model.phase) {
      Button("Cancel") {
        model.cancel()
      }
      .keyboardShortcut(.escape, modifiers: [])
    }

    Divider()

    Button {
      model.showHistory()
    } label: {
      Label("History", systemImage: "clock.arrow.circlepath")
    }

    Button {
      model.showSettings()
    } label: {
      Label("Settings…", systemImage: "gearshape")
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button("Quit Purrr") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }

  @ViewBuilder
  private func modeButton(_ mode: SessionMode, shortcut: AppShortcut) -> some View {
    let isRecordingMode = model.phase == .recording && model.activeMode == mode
    let needsLLM = mode == .translate && !settings.llmEnabled
    let button = Button {
      model.toggle(mode)
    } label: {
      Label(title(mode, isRecording: isRecordingMode, needsLLM: needsLLM), systemImage: mode.symbol)
    }
    .disabled(needsLLM || (model.phase.isActive && !isRecordingMode))

    if let key = shortcut.keyEquivalent {
      button.keyboardShortcut(key, modifiers: shortcut.modifiers.eventModifiers)
    } else {
      button
    }
  }

  private func title(_ mode: SessionMode, isRecording: Bool, needsLLM: Bool) -> String {
    if isRecording { return "Finish \(mode.title)" }
    return needsLLM ? "\(mode.title) (LLM off)" : mode.title
  }

  private var blocker: (title: String, tab: SettingsTab)? {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .denied, .restricted:
      return ("Allow Microphone Access…", .general)
    default:
      break
    }
    if settings.llmEnabled && !settings.isLLMConfigured {
      return ("Finish LLM Setup…", .llm)
    }
    return nil
  }
}

extension AppShortcut {
  fileprivate var keyEquivalent: KeyEquivalent? {
    switch keyLabel {
    case "Space": .space
    case "Return": .return
    case "Tab": .tab
    default:
      keyLabel.count == 1 ? keyLabel.lowercased().first.map { KeyEquivalent($0) } : nil
    }
  }
}

extension ShortcutModifiers {
  fileprivate var eventModifiers: EventModifiers {
    var value: EventModifiers = []
    if contains(.command) { value.insert(.command) }
    if contains(.control) { value.insert(.control) }
    if contains(.option) { value.insert(.option) }
    if contains(.shift) { value.insert(.shift) }
    return value
  }
}
