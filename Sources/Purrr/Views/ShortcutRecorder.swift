import AppKit
import SwiftUI

@MainActor
final class ShortcutRecorderSession: ObservableObject {
  @Published var isRecording = false
  private var monitor: Any?

  deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
  }

  func begin(onCapture: @escaping (AppShortcut) -> Void) {
    stop()
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      if event.keyCode == 53 {
        self.stop()
        return nil
      }
      let modifiers = ShortcutModifiers(
        eventFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      )
      guard !modifiers.isEmpty else {
        NSSound.beep()
        return nil
      }
      let label: String
      if event.keyCode == 49 {
        label = "Space"
      } else if event.keyCode == 36 {
        label = "Return"
      } else if event.keyCode == 48 {
        label = "Tab"
      } else {
        label = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
      }
      onCapture(
        AppShortcut(
          keyCode: UInt32(event.keyCode),
          modifiers: modifiers,
          keyLabel: label
        )
      )
      self.stop()
      return nil
    }
  }

  func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    isRecording = false
  }
}

struct ShortcutRecorder: View {
  let shortcut: AppShortcut
  let onChange: (AppShortcut) -> Void
  @StateObject private var session = ShortcutRecorderSession()

  var body: some View {
    Button {
      session.begin(onCapture: onChange)
    } label: {
      Text(session.isRecording ? "Type shortcut…" : shortcut.displayName)
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .frame(minWidth: 112)
    }
    .buttonStyle(.bordered)
    .tint(session.isRecording ? .accentColor : nil)
    .onDisappear {
      session.stop()
    }
  }
}
