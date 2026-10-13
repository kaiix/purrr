import SwiftUI

struct LLMPromptEditorView: View {
  @Binding var dictatePrompt: String
  @Binding var translatePrompt: String
  @ObservedObject var vocabulary: VocabularyStore
  let targetLanguage: TranslationLanguage
  let llmAvailable: Bool
  @State private var mode: SessionMode = .dictate
  @State private var showsRules = false
  @State private var showsPreview = false

  var body: some View {
    Section("Prompts") {
      Picker("Prompt", selection: $mode) {
        ForEach(SessionMode.allCases) { mode in Text(mode.title).tag(mode) }
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
        .accessibilityLabel("\(mode.title) prompt template")

      VStack(alignment: .leading, spacing: 4) {
        Text(promptHelp)
        Text(vocabularyStatus)
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Button("Vocabulary Instructions…") { showsRules = true }
        Spacer()
        Button("Preview Request…") { showsPreview = true }
        Button("Restore Default") { activePrompt.wrappedValue = defaultPrompt }
          .disabled(activePrompt.wrappedValue == defaultPrompt)
      }
    }
    .sheet(isPresented: $showsRules) {
      PromptDetailsView(mode: mode, prompt: preview, rulesOnly: true, llmAvailable: llmAvailable)
    }
    .sheet(isPresented: $showsPreview) {
      PromptDetailsView(mode: mode, prompt: preview, rulesOnly: false, llmAvailable: llmAvailable)
    }
  }

  private var activePrompt: Binding<String> {
    mode == .dictate ? $dictatePrompt : $translatePrompt
  }

  private var defaultPrompt: String {
    mode == .dictate ? AppSettings.defaultDictatePrompt : AppSettings.defaultTranslatePrompt
  }

  private var promptHelp: String {
    if mode == .translate {
      if translatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Empty: translate into the selected language without extra style instructions."
      }
      return
        "{{target_language}} becomes the target language. Questions and commands are translated, not followed."
    }
    if dictatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return
        "Empty: correct vocabulary spellings only. Without vocabulary, return the raw transcript."
    }
    return "Questions and commands are polished, not answered. Your template stays unchanged."
  }

  private var vocabularyStatus: String {
    if !vocabulary.collectsEdits {
      return "Vocabulary is off; no words or vocabulary rules are sent."
    }
    if !llmAvailable { return "Vocabulary is paused until the LLM is enabled and configured." }
    let count = vocabulary.processingTerms.count
    return count == 0
      ? "No eligible words yet. Vocabulary rules are added when words are available."
      : "Vocabulary: \(count) \(count == 1 ? "saved word" : "saved words") included automatically with built-in rules."
  }

  private var preview: TextProcessingPrompt? {
    let configuration = LLMConfiguration(
      baseURL: "", apiKey: "", model: "",
      dictatePrompt: dictatePrompt, translatePrompt: translatePrompt,
      vocabulary: llmAvailable ? vocabulary.processingTerms : [])
    return try? TextProcessingPrompt.make(
      mode: mode, transcript: "Please open the AllDay app on my Mac.",
      configuration: configuration, targetLanguage: targetLanguage)
  }
}

private struct PromptDetailsView: View {
  let mode: SessionMode
  let prompt: TextProcessingPrompt?
  let rulesOnly: Bool
  let llmAvailable: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(rulesOnly ? "Vocabulary Instructions" : "\(mode.title) Request Preview")
        .font(.title2.weight(.semibold))
      Text(
        rulesOnly
          ? "Built-in rules, added during LLM processing when vocabulary is enabled and eligible words are available."
          : "Example transcript with your current template and eligible words. No request is sent; credentials are not shown."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      if !rulesOnly && !llmAvailable {
        Label(
          "The LLM is off or not configured. No live request will be sent.",
          systemImage: "info.circle"
        )
        .font(.callout)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if rulesOnly {
            block("\(mode.title) rules", TextProcessingPrompt.instructionsForVocabulary(mode: mode))
          } else if let prompt {
            if prompt.isPassthrough {
              Text("This configuration returns raw text without an LLM request.")
                .font(.callout)
            }
            block("System instructions", prompt.systemInstructions)
            block("Input data", formattedInput(prompt.userPayload))
          } else {
            Text("Couldn’t build the preview. Close it and try again.")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .defaultScrollAnchor(.top)
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }
    .padding(20)
    .frame(width: 620, height: 560)
  }

  private func block(_ title: String, _ content: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline)
      Text(content)
        .font(.system(size: 12.5, design: .monospaced))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func formattedInput(_ input: String) -> String {
    guard let value = try? JSONSerialization.jsonObject(with: Data(input.utf8)),
      let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    else { return input }
    return String(decoding: data, as: UTF8.self)
  }
}
