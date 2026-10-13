import SwiftUI

struct VocabularyView: View {
  private enum Page: Identifiable {
    case words
    case review
    var id: Self { self }
  }

  @ObservedObject var vocabulary: VocabularyStore
  var llmAvailable: Bool
  var onReview: () -> Void
  @Binding private var editRequest: UUID?
  @State private var page: Page = .words
  @State private var editingWordID: UUID?
  @State private var newTerm = ""
  @State private var errorMessage: String?

  init(
    vocabulary: VocabularyStore, editRequest: Binding<UUID?> = .constant(nil),
    llmAvailable: Bool = false, onReview: @escaping () -> Void = {}
  ) {
    self.vocabulary = vocabulary
    self.llmAvailable = llmAvailable
    self.onReview = onReview
    _editRequest = editRequest
  }

  var body: some View {
    ScrollViewReader { reader in
      Form {
        Section {
          Toggle(
            "Use vocabulary",
            isOn: Binding(
              get: { vocabulary.collectsEdits },
              set: { enabled in perform { try vocabulary.setCollectsEdits(enabled) } }
            )
          )
          if vocabulary.collectsEdits && !llmAvailable {
            Label(
              "Requires an enabled, configured LLM.", systemImage: "exclamationmark.circle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
          } else {
            Text(
              vocabulary.collectsEdits
                ? "Learns names from your edits and uses saved spellings when processing text. Words are sent to your configured LLM API."
                : "Off: no automatic learning or spelling guidance. Saved words are kept and can still be managed."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }
          if vocabulary.words.contains(where: {
            $0.source == .autoAdded && $0.reviewedByLLM != true
          }) {
            Text("Unchecked auto-added words are excluded. Edit and save to confirm them.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Picker("Vocabulary", selection: $page) {
            Text("Words").tag(Page.words)
            Text(
              vocabulary.candidates.isEmpty
                ? "Suggestions" : "Suggestions (\(vocabulary.candidates.count))"
            ).tag(Page.review)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())

          if let message = vocabulary.storageError ?? errorMessage ?? vocabulary.reviewError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.red)
          }
        }

        if page == .words {
          words
        } else {
          suggestions
        }
      }
      .formStyle(.grouped)
      .onAppear {
        if let editingWordID { reader.scrollTo(editingWordID, anchor: .center) }
      }
      .onChange(of: editingWordID) { _, id in
        if let id { reader.scrollTo(id, anchor: .center) }
      }
    }
    .onChange(of: editRequest, initial: true) { _, id in
      guard let id else { return }
      editingWordID = id
      page = .words
      editRequest = nil
    }
  }

  private var words: some View {
    Section {
      HStack(spacing: 8) {
        TextField("New word", text: $newTerm, prompt: Text("Add a name or term"))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .onSubmit(addWord)
        Button("Add", action: addWord)
          .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      ForEach(vocabulary.words) { word in
        VocabularyWordRow(word: word, vocabulary: vocabulary, editingWordID: $editingWordID)
          .id(word.id)
      }
    } footer: {
      Text("Saved words remain until deleted. They are not synced to Doubao IME.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var suggestions: some View {
    let unchecked = vocabulary.unreviewedCandidates.count
    if unchecked > 0 || vocabulary.isReviewing {
      Section {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 3) {
            Text("^[\(unchecked) older edit](inflect: true) not checked")
            Text("Sends short before/after snippets to your LLM.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if vocabulary.isReviewing {
            ProgressView().controlSize(.small)
          }
          Button("Check", action: onReview)
            .disabled(!llmAvailable || vocabulary.isReviewing || unchecked == 0)
        }
      }
    }

    Section {
      if vocabulary.candidates.isEmpty {
        Text(
          vocabulary.collectsEdits
            ? "No suggestions. Corrections the LLM approves appear here." : "Collection is off."
        )
        .foregroundStyle(.secondary)
      } else {
        ForEach(vocabulary.candidates) { candidate in
          VocabularyCandidateRow(candidate: candidate, vocabulary: vocabulary)
        }
      }
    } footer: {
      Text("Unchecked edits are deleted after 24 hours.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func addWord() {
    perform {
      try vocabulary.add(newTerm)
      newTerm = ""
    }
  }

  private func perform(_ operation: () throws -> Void) {
    do {
      try operation()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct VocabularyWordRow: View {
  let word: VocabularyWord
  @ObservedObject var vocabulary: VocabularyStore
  @Binding var editingWordID: UUID?
  @State private var editedTerm = ""
  @State private var errorMessage: String?
  @FocusState private var termIsFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        if editingWordID == word.id {
          TextField("Word", text: $editedTerm)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused($termIsFocused)
            .onAppear { termIsFocused = true }
            .onSubmit(save)
            .accessibilityLabel("Edit \(word.term)")
          Button("Save", action: save)
          Button("Cancel") {
            editingWordID = nil
            errorMessage = nil
          }
        } else {
          Text(word.term).textSelection(.enabled)
          if let sourceNote {
            Text(sourceNote)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Edit") {
            editedTerm = word.term
            editingWordID = word.id
          }
          Button(role: .destructive) {
            perform { try vocabulary.delete(word) }
          } label: {
            Image(systemName: "trash")
          }
          .accessibilityLabel("Delete \(word.term)")
        }
      }
      .frame(minHeight: 22)
      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }
    }
    .buttonStyle(.borderless)
    .onChange(of: editingWordID, initial: true) { _, id in
      if id == word.id {
        editedTerm = word.term
        errorMessage = nil
      }
    }
  }

  private var sourceNote: String? {
    guard word.source == .autoAdded else { return nil }
    return word.reviewedByLLM == true ? "Auto-added" : "Auto-added, not checked"
  }

  private func save() {
    perform {
      try vocabulary.update(word, term: editedTerm)
      editingWordID = nil
    }
  }

  private func perform(_ operation: () throws -> Void) {
    do {
      try operation()
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
  }
}

private struct VocabularyCandidateRow: View {
  let candidate: VocabularyCandidate
  @ObservedObject var vocabulary: VocabularyStore
  @State private var term: String
  @State private var errorMessage: String?
  @State private var showsContext = false

  init(candidate: VocabularyCandidate, vocabulary: VocabularyStore) {
    self.candidate = candidate
    self.vocabulary = vocabulary
    _term = State(initialValue: candidate.correctedTerm)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextField("Word", text: $term)
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("Suggested word")
        Button("Add") {
          perform { try vocabulary.confirm(candidate, term: term) }
        }
        .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Dismiss") {
          perform { try vocabulary.dismiss(candidate) }
        }
      }
      DisclosureGroup(isExpanded: $showsContext) {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
          GridRow {
            Text("Before").foregroundStyle(.secondary)
            Text(candidate.originalContext)
          }
          GridRow {
            Text("After").foregroundStyle(.secondary)
            Text(candidate.correctedContext)
          }
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text("Was “\(candidate.originalTerm)”")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }
    }
  }

  private func perform(_ operation: () throws -> Void) {
    do {
      try operation()
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
  }
}
