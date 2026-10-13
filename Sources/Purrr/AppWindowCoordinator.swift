import AppKit
import SwiftUI

@MainActor
final class AppWindowCoordinator: NSObject, NSWindowDelegate {
  private var settingsWindow: NSWindow?
  private var historyWindow: NSWindow?

  func showSettings(settings: AppSettings, model: AppModel) {
    if let settingsWindow {
      present(settingsWindow)
      return
    }

    let window = makeWindow(
      title: "Settings",
      contentSize: NSSize(width: 560, height: 496),
      autosaveName: "PurrrSettingsWindow"
    )
    window.contentViewController = NSHostingController(
      rootView: SettingsView(settings: settings, model: model)
    )
    settingsWindow = window
    present(window)
  }

  func showHistory(history: HistoryStore, model: AppModel) {
    if let historyWindow {
      present(historyWindow)
      return
    }

    let window = makeWindow(
      title: "History",
      contentSize: NSSize(width: 780, height: 560),
      autosaveName: "PurrrHistoryWindow"
    )
    window.contentViewController = NSHostingController(
      rootView: HistoryView(history: history, model: model)
    )
    historyWindow = window
    present(window)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if window === settingsWindow {
      settingsWindow = nil
    } else if window === historyWindow {
      historyWindow = nil
    }
    // Back to a menu bar-only app once the last window is gone.
    if settingsWindow == nil && historyWindow == nil {
      DispatchQueue.main.async { [weak self] in
        guard let self, self.settingsWindow == nil, self.historyWindow == nil else { return }
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }

  private func makeWindow(
    title: String,
    contentSize: NSSize,
    autosaveName: String
  ) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.setFrameAutosaveName(autosaveName)
    window.center()
    return window
  }

  private func present(_ window: NSWindow) {
    // Show in the Dock and App Switcher while a window is open.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
