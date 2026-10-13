import SwiftUI

struct VocabularyView: View {
  private enum Page: String, CaseIterable, Identifiable {
    case words = "Saved Words"
    case review = "Review Edits"
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
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Collect words, without changing your dictations.")
          .font(.headline)
        Text(
          "Edit snippets are reviewed by your configured LLM. Saved words do not change dictation output or sync to Doubao IME."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Toggle(
        "Automatically add LLM-reviewed words from new Dictate edits",
        isOn: Binding(
          get: { vocabulary.collectsEdits },
          set: { enabled in perform { try vocabulary.setCollectsEdits(enabled) } }
        )
      )
      Text(
        llmAvailable
          ? "Only clear name and fixed-term corrections are collected, with Undo and Edit. Ordinary rewrites are ignored."
          : "Enable and configure the LLM to review edits. Automatic collection is paused; manual words are still available."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Picker("Vocabulary", selection: $page) {
        Text("Saved Words (\(vocabulary.words.count))").tag(Page.words)
        Text(
          "Review Edits (\(vocabulary.candidates.count + vocabulary.unreviewedCandidates.count))"
        ).tag(Page.review)
      }
      .pickerStyle(.segmented)

      if let message = vocabulary.storageError ?? errorMessage ?? vocabulary.reviewError {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      if page == .words {
        if vocabulary.words.contains(where: { $0.source == .autoAdded && $0.reviewedByLLM != true })
        {
          Text(
            "Earlier auto-added words have not been semantically reviewed. Remove any unwanted entries."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 8) {
          TextField("Correct spelling of a name or term", text: $newTerm)
            .textFieldStyle(.roundedBorder)
            .onSubmit(addWord)
            .accessibilityLabel("New vocabulary word")
          Button("Add Word", action: addWord)
            .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if vocabulary.words.isEmpty {
          emptyState(
            title: "No saved words",
            detail: "Add a name or term yourself, or confirm one from Review Edits."
          )
        } else {
          ScrollViewReader { reader in
            List(vocabulary.words) { word in
              VocabularyWordRow(
                word: word, vocabulary: vocabulary, editingWordID: $editingWordID
              )
              .id(word.id)
            }
            .listStyle(.inset)
            .onAppear {
              if let editingWordID { reader.scrollTo(editingWordID, anchor: .center) }
            }
            .onChange(of: editingWordID) { _, id in
              if let id { reader.scrollTo(id, anchor: .center) }
            }
          }
        }
      } else {
        Text(
          "Only LLM-approved term corrections appear below. Review sends local before/after snippets to your configured API. Evidence expires with History after 24 hours."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          Button("Review Edits with LLM", action: onReview)
            .disabled(
              !llmAvailable || vocabulary.isReviewing || vocabulary.unreviewedCandidates.isEmpty)
          if vocabulary.isReviewing {
            ProgressView().controlSize(.small)
            Text("Reviewing names and terms…")
          } else {
            Text("\(vocabulary.unreviewedCandidates.count) edits awaiting review")
          }
        }
        .font(.callout)
        if vocabulary.candidates.isEmpty {
          emptyState(
            title: vocabulary.collectsEdits
              ? "No approved term corrections" : "Candidate collection is off",
            detail:
              "Use Review Edits with LLM to check older edits. Ordinary rewrites and uncertain results are not offered as words."
          )
        } else {
          List(vocabulary.candidates) { candidate in
            VocabularyCandidateRow(candidate: candidate, vocabulary: vocabulary)
          }
          .listStyle(.inset)
        }
      }
    }
    .padding(.top, 16)
    .onChange(of: editRequest, initial: true) { _, id in
      guard let id else { return }
      editingWordID = id
      page = .words
      editRequest = nil
    }
  }

  private func emptyState(title: String, detail: String) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: "text.book.closed")
    } description: {
      Text(detail)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
          TextField("Word or phrase", text: $editedTerm)
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
          VStack(alignment: .leading, spacing: 3) {
            Text(word.term).textSelection(.enabled)
            Text(sourceDescription)
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
      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }
    }
    .padding(.vertical, 6)
    .buttonStyle(.borderless)
    .onChange(of: editingWordID, initial: true) { _, id in
      if id == word.id {
        editedTerm = word.term
        errorMessage = nil
      }
    }
  }

  private var sourceDescription: String {
    switch word.source {
    case .manual: "Added manually"
    case .confirmedEdit: "Confirmed from an edit"
    case .autoAdded:
      word.reviewedByLLM == true ? "Added after LLM review" : "Added before semantic review"
    }
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
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Edited from “\(candidate.originalTerm)”")
          .font(.callout)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        Spacer()
        Text(candidate.observedAt, style: .time)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        TextField("Word to save", text: $term)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("Candidate word to save")
        Button("Keep Word") {
          perform { try vocabulary.confirm(candidate, term: term) }
        }
        .disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Dismiss") {
          perform { try vocabulary.dismiss(candidate) }
        }
      }
      Button {
        showsContext.toggle()
      } label: {
        Label(
          showsContext ? "Hide surrounding text" : "Compare surrounding text",
          systemImage: showsContext ? "chevron.down" : "chevron.right"
        )
      }
      .buttonStyle(.borderless)
      .accessibilityValue(showsContext ? "Expanded" : "Collapsed")
      if showsContext {
        VStack(alignment: .leading, spacing: 6) {
          Text("Before: \(candidate.originalContext)")
          Text("After: \(candidate.correctedContext)")
        }
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }
    }
    .padding(.vertical, 8)
  }

  private func perform(_ operation: () throws -> Void) {
    do {
      try operation()
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
  }
}
