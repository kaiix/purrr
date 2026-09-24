import AppKit
import SwiftUI

extension Notification.Name {
  static let purrrShowSettings = Notification.Name("purrr.showSettings")
}

final class PurrrAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "didShowInitialSettings") {
      defaults.set(true, forKey: "didShowInitialSettings")
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .purrrShowSettings, object: nil)
      }
    }
  }
}

@main
struct PurrrApp: App {
  @NSApplicationDelegateAdaptor(PurrrAppDelegate.self) private var appDelegate
  @StateObject private var settings: AppSettings
  @StateObject private var history: HistoryStore
  @StateObject private var model: AppModel

  init() {
    let settings = AppSettings()
    let history = HistoryStore()
    _settings = StateObject(wrappedValue: settings)
    _history = StateObject(wrappedValue: history)
    _model = StateObject(wrappedValue: AppModel(settings: settings, history: history))
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(model: model, settings: settings)
    } label: {
      Image(nsImage: Self.menuBarIcon)
        .accessibilityLabel("Purrr")
    }
    .menuBarExtraStyle(.menu)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") {
          model.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
      }
      CommandGroup(after: .windowList) {
        Button("History") {
          model.showHistory()
        }
      }
    }
  }

  private static let menuBarIcon: NSImage = {
    guard
      let url = Bundle.main.url(forResource: "PurrrMenuBarIcon", withExtension: "png"),
      let image = NSImage(contentsOf: url)
    else {
      return NSImage(
        systemSymbolName: "waveform",
        accessibilityDescription: "Purrr"
      ) ?? NSImage()
    }

    image.isTemplate = true
    image.size = NSSize(width: 25, height: 16)
    image.accessibilityDescription = "Purrr"
    return image
  }()
}
