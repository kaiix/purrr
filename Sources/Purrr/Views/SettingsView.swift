import AVFoundation
import AppKit
import SwiftUI

struct SettingsView: View {
  private enum PromptKind: String, CaseIterable, Identifiable {
    case dictate = "Dictate"
    case translate = "Translate"

    var id: Self { self }
  }

  @ObservedObject var settings: AppSettings
  @ObservedObject var model: AppModel
  @State private var shortcutError: String?
  @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
  @State private var accessibilityGranted = false
  @State private var selectedPrompt: PromptKind = .dictate

  var body: some View {
    TabView {
      general
        .tabItem { Label("General", systemImage: "switch.2") }
      languageModel
        .tabItem { Label("LLM", systemImage: "sparkles") }
    }
    .padding(20)
    .frame(width: 700, height: 640)
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

  private var general: some View {
    Form {
      Section("Shortcuts") {
        LabeledContent("Dictate") {
          ShortcutRecorder(shortcut: settings.dictateShortcut) { candidate in
            guard candidate != settings.translateShortcut else {
              shortcutError = "Dictate and Translate must use different shortcuts."
              return
            }
            shortcutError = nil
            settings.dictateShortcut = candidate
          }
        }
        LabeledContent("Translate") {
          ShortcutRecorder(shortcut: settings.translateShortcut) { candidate in
            guard candidate != settings.dictateShortcut else {
              shortcutError = "Dictate and Translate must use different shortcuts."
              return
            }
            shortcutError = nil
            settings.translateShortcut = candidate
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
        Button("Restore Defaults") {
          settings.restoreShortcutDefaults()
        }
      }

      Section("Translate") {
        Picker("Target language", selection: $settings.targetLanguage) {
          ForEach(TranslationLanguage.allCases) { language in
            Text(language.title).tag(language)
          }
        }
      }

      Section("Permissions") {
        permissionRow(
          title: "Microphone",
          detail: microphonePermissionDetail,
          granted: microphoneStatus == .authorized,
          actionTitle: microphoneStatus == .notDetermined ? "Request Access" : "Open Settings"
        ) {
          handleMicrophonePermission()
        }
        permissionRow(
          title: "Accessibility",
          detail: "Enables safe text insertion and conflict-free global shortcuts.",
          granted: accessibilityGranted,
          actionTitle: "Request Access"
        ) {
          model.requestAccessibilityPermission()
        }
      }
    }
    .formStyle(.grouped)
  }

  private var languageModel: some View {
    Form {
      Section {
        Toggle("Enable LLM processing", isOn: $settings.llmEnabled)
        Text(
          settings.llmEnabled
            ? "Dictate is cleaned up and Translate is available."
            : "Dictate returns the raw Doubao IME transcript. Translate is unavailable."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      Section("OpenAI-compatible API") {
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

          switch model.modelListStatus {
          case .idle:
            Text("Enter the endpoint and API key, then load its available models.")
              .font(.caption)
              .foregroundStyle(.secondary)
          case .loading:
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.small)
              Text("Loading models…")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          case .loaded:
            Text("\(model.availableLLMModels.count) models available")
              .font(.caption)
              .foregroundStyle(.secondary)
          case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
              .font(.caption)
              .foregroundStyle(.red)
              .lineLimit(3)
          }
        }

        HStack {
          Button("Test Connection") {
            model.testLLMConnection()
          }
          .disabled(!settings.isLLMConfigured || model.connectionTestStatus == .testing)

          switch model.connectionTestStatus {
          case .idle:
            EmptyView()
          case .testing:
            ProgressView()
              .controlSize(.small)
          case .succeeded:
            Label("Connected", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
              .foregroundStyle(.red)
              .lineLimit(2)
          }
        }
      }

      Section("Prompts") {
        Picker("Prompt", selection: $selectedPrompt) {
          ForEach(PromptKind.allCases) { kind in
            Text(kind.rawValue).tag(kind)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        TextEditor(text: activePrompt)
          .font(.system(size: 12.5))
          .frame(minHeight: 132)
          .scrollContentBackground(.hidden)
          .padding(6)
          .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
          }
          .accessibilityLabel("\(selectedPrompt.rawValue) prompt")

        HStack(alignment: .firstTextBaseline) {
          Text(promptHelp)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Restore Default") {
            restoreSelectedPrompt()
          }
          .disabled(selectedPromptIsDefault)
        }
      }

      Section("Privacy") {
        Text(
          "Audio is sent to Doubao IME. Recognized text is sent to this endpoint only when LLM processing is enabled or Translate is used. The API key is stored in Keychain."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
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

  private var activePrompt: Binding<String> {
    switch selectedPrompt {
    case .dictate:
      $settings.dictatePrompt
    case .translate:
      $settings.translatePrompt
    }
  }

  private var promptHelp: String {
    switch selectedPrompt {
    case .dictate:
      "Questions and commands in the transcript are polished as source text, never answered."
    case .translate:
      "Use {{target_language}} for the destination. Transcript instructions are translated, never followed."
    }
  }

  private var selectedPromptIsDefault: Bool {
    switch selectedPrompt {
    case .dictate:
      settings.dictatePrompt == AppSettings.defaultDictatePrompt
    case .translate:
      settings.translatePrompt == AppSettings.defaultTranslatePrompt
    }
  }

  private func restoreSelectedPrompt() {
    switch selectedPrompt {
    case .dictate:
      settings.restoreDictatePrompt()
    case .translate:
      settings.restoreTranslatePrompt()
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
      VStack(alignment: .leading, spacing: 3) {
        Label(
          title,
          systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(granted ? .green : .orange)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if !granted {
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
      "Request access once so macOS can add Purrr to the Microphone app list."
    case .denied:
      "Microphone access is disabled in System Settings."
    case .restricted:
      "Microphone access is restricted on this Mac."
    case .authorized:
      nil
    @unknown default:
      "Microphone permission could not be determined."
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
