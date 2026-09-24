import SwiftUI

struct MenuBarView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var settings: AppSettings

  var body: some View {
    Button {
      model.toggle(.dictate)
    } label: {
      Label(dictateTitle, systemImage: "waveform")
    }
    .keyboardShortcut("d", modifiers: [])

    Button {
      model.toggle(.translate)
    } label: {
      Label(translateTitle, systemImage: "character.bubble")
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
      Label("Settings", systemImage: "gearshape")
    }

    Divider()

    Button("Quit Purrr") {
      NSApplication.shared.terminate(nil)
    }
  }

  private var dictateTitle: String {
    if model.phase == .recording, model.activeMode == .dictate {
      return "Finish Dictate"
    }
    return "Dictate  \(settings.dictateShortcut.displayName)"
  }

  private var translateTitle: String {
    if model.phase == .recording, model.activeMode == .translate {
      return "Finish Translate"
    }
    return "Translate  \(settings.translateShortcut.displayName)"
  }
}
