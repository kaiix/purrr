import AVFoundation
import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var model: AppModel
  @State private var shortcutError: String?
  @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
  @State private var accessibilityGranted = false

  var body: some View {
    TabView(selection: $model.settingsTab) {
      general
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsTab.general)
      languageModel
        .tabItem { Label("LLM", systemImage: "sparkles") }
        .tag(SettingsTab.llm)
      VocabularyView(
        vocabulary: model.vocabulary, editRequest: $model.vocabularyEditRequest,
        suggestionRequest: $model.vocabularySuggestionRequest,
        llmAvailable: settings.llmEnabled && settings.isLLMConfigured,
        onReview: { model.reviewVocabularyEdits() }
      )
      .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
      .tag(SettingsTab.vocabulary)
    }
    .padding(20)
    .frame(width: 620, height: height)
    .onAppear(perform: refreshPermissions)
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      refreshPermissions()
    }
    .task {
      while !Task.isCancelled {
        refreshPermissions()
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return
        }
      }
    }
  }

  // Each tab shows its whole content without scrolling; Vocabulary scrolls its list.
  private var height: CGFloat {
    switch model.settingsTab {
    case .general: 520
    case .llm: 820
    case .vocabulary: 640
    }
  }

  private var general: some View {
    Form {
      Section("Permissions") {
        permissionRow(
          title: "Microphone",
          detail: microphonePermissionDetail,
          granted: microphoneStatus == .authorized,
          actionTitle: microphoneStatus == .notDetermined ? "Allow" : "Open Settings"
        ) {
          handleMicrophonePermission()
        }
        permissionRow(
          title: "Accessibility",
          detail: "Needed to insert text and reserve shortcuts.",
          granted: accessibilityGranted,
          actionTitle: "Allow"
        ) {
          model.requestAccessibilityPermission()
        }
      }

      Section {
        LabeledContent("Dictate") {
          ShortcutRecorder(shortcut: settings.dictateShortcut) { candidate in
            setShortcut(candidate, other: settings.translateShortcut) {
              settings.dictateShortcut = candidate
            }
          }
        }
        LabeledContent {
          ShortcutRecorder(shortcut: settings.translateShortcut) { candidate in
            setShortcut(candidate, other: settings.dictateShortcut) {
              settings.translateShortcut = candidate
            }
          }
        } label: {
          Text("Translate")
          if !settings.llmEnabled {
            Text("Needs the LLM")
          }
        }
        Picker("Translate into", selection: $settings.targetLanguage) {
          ForEach(TranslationLanguage.allCases) { language in
            Text(language.title).tag(language)
          }
        }
        if let shortcutError {
          Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .font(.callout)
        } else if let warning = model.shortcutWarning {
          Label(warning, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.callout)
        }
      } header: {
        Text("Shortcuts")
      } footer: {
        HStack(alignment: .firstTextBaseline) {
          Text("Press to start, press again to finish. Esc cancels.")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Restore Defaults") {
            shortcutError = nil
            settings.restoreShortcutDefaults()
          }
          .disabled(
            settings.dictateShortcut == .dictateDefault
              && settings.translateShortcut == .translateDefault
          )
        }
      }

      Section("Privacy") {
        HStack {
          Text("Audio is sent to Doubao IME. History stays on this Mac for 24 hours.")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Open History") {
            model.showHistory()
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func setShortcut(_ candidate: AppShortcut, other: AppShortcut, apply: () -> Void) {
    guard candidate != other else {
      shortcutError = "Dictate and Translate need different shortcuts."
      return
    }
    shortcutError = nil
    apply()
  }

  private var languageModel: some View {
    Form {
      Section {
        Toggle("Polish and translate with an LLM", isOn: $settings.llmEnabled)
        if !settings.llmEnabled {
          Text("Off: Dictate inserts the raw transcript. Translate is unavailable.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if !settings.isLLMConfigured {
          Label("Finish setup below.", systemImage: "exclamationmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text("Base URL")
            .font(.subheadline.weight(.medium))
          TextField(
            text: $settings.baseURL,
            prompt: Text("https://api.openai.com/v1")
          ) {
            EmptyView()
          }
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("API key")
            .font(.subheadline.weight(.medium))
          SecureField(
            text: $settings.apiKey,
            prompt: Text("Enter API key")
          ) {
            EmptyView()
          }
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          Text("Stored in Keychain.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Model")
            .font(.subheadline.weight(.medium))
          HStack(spacing: 8) {
            Picker("Model", selection: $settings.model) {
              if !settings.model.isEmpty && !model.availableLLMModels.contains(settings.model) {
                Text(settings.model).tag(settings.model)
              }
              ForEach(model.availableLLMModels, id: \.self) { modelID in
                Text(modelID).tag(modelID)
              }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(model.availableLLMModels.isEmpty)

            Button {
              model.refreshLLMModels()
            } label: {
              Label(
                model.availableLLMModels.isEmpty ? "Load Models" : "Refresh",
                systemImage: "arrow.clockwise"
              )
            }
            .disabled(!settings.hasLLMCredentials || model.modelListStatus == .loading)
          }
        }

        HStack {
          apiStatus
            .font(.callout)
          Spacer()
          Button("Test Connection") {
            model.testLLMConnection()
          }
          .disabled(!settings.isLLMConfigured || model.connectionTestStatus == .testing)
        }
      } header: {
        Text("OpenAI-compatible API")
      } footer: {
        Text("Text is sent to this API only when the LLM is on.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      LLMPromptEditorView(
        dictatePrompt: $settings.dictatePrompt, translatePrompt: $settings.translatePrompt,
        vocabulary: model.vocabulary, targetLanguage: settings.targetLanguage,
        llmAvailable: settings.llmEnabled && settings.isLLMConfigured)
    }
    .formStyle(.grouped)
    .task {
      guard settings.hasLLMCredentials, model.modelListStatus == .idle else { return }
      model.refreshLLMModels()
    }
    .onChange(of: settings.baseURL) { _, _ in
      model.invalidateLLMModels()
    }
    .onChange(of: settings.apiKey) { _, _ in
      model.invalidateLLMModels()
    }
  }

  // One status line: the connection test once it has run, otherwise the model list.
  @ViewBuilder
  private var apiStatus: some View {
    switch (model.connectionTestStatus, model.modelListStatus) {
    case (.testing, _):
      ProgressView().controlSize(.small)
    case (.succeeded, _):
      Label("Connected", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case (.failed(let message), _), (.idle, .failed(let message)):
      Label(message, systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
        .lineLimit(3)
    case (.idle, .idle):
      Text("Add a base URL and API key to load models.")
        .foregroundStyle(.secondary)
    case (.idle, .loading):
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text("Loading models…")
          .foregroundStyle(.secondary)
      }
    case (.idle, .loaded):
      Text("^[\(model.availableLLMModels.count) model](inflect: true)")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func permissionRow(
    title: String,
    detail: String? = nil,
    granted: Bool,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .foregroundStyle(granted ? .green : .orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
        if !granted, let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if granted {
        Text("Allowed")
          .foregroundStyle(.secondary)
      } else {
        Button(actionTitle, action: action)
      }
    }
  }

  private func openPrivacyPane(_ anchor: String) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  private var microphonePermissionDetail: String? {
    switch microphoneStatus {
    case .notDetermined:
      "Needed to record."
    case .denied:
      "Turned off in System Settings."
    case .restricted:
      "Restricted on this Mac."
    case .authorized:
      nil
    @unknown default:
      "Needed to record."
    }
  }

  private func handleMicrophonePermission() {
    guard microphoneStatus == .notDetermined else {
      openPrivacyPane("Privacy_Microphone")
      return
    }

    Task { @MainActor in
      _ = await AudioRecorder.requestPermission()
      refreshPermissions()
    }
  }

  private func refreshPermissions() {
    let hadAccessibilityPermission = accessibilityGranted
    microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    accessibilityGranted = AXIsProcessTrusted()
    if !hadAccessibilityPermission && accessibilityGranted {
      model.refreshGlobalShortcuts()
    }
  }
}
