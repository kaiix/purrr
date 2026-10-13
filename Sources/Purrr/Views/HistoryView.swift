import SwiftUI

struct HistoryView: View {
  @ObservedObject var history: HistoryStore
  @ObservedObject var model: AppModel
  @State private var confirmDeleteAll = false
  @State private var expanded: Set<UUID> = []
  @State private var selection: UUID?
  @State private var copied: (id: UUID, label: String)?
  // Hidden at once, deleted when the Undo window ends.
  @State private var removed: HistoryEntry?
  @State private var removalTask: Task<Void, Never>?
  @FocusState private var listFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if entries.isEmpty {
        emptyState
      } else {
        list
      }
    }
    .frame(minWidth: 720, minHeight: 480)
    .onDisappear(perform: commitRemoval)
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
    ) { _ in
      commitRemoval()
    }
    .alert("Delete all history?", isPresented: $confirmDeleteAll) {
      Button("Cancel", role: .cancel) {}
      Button("Delete All", role: .destructive) {
        removalTask?.cancel()
        removed = nil
        history.deleteAll()
      }
    } message: {
      Text("All audio and text are deleted from this Mac.")
    }
  }

  private var entries: [HistoryEntry] {
    history.entries.filter { $0.id != removed?.id }
  }

  private var header: some View {
    HStack(spacing: 8) {
      if removed == nil {
        Text("Kept on this Mac for 24 hours.")
          .foregroundStyle(.secondary)
      } else {
        Text("Removed.")
          .foregroundStyle(.secondary)
        Button("Undo", action: undoRemoval)
          .keyboardShortcut("z", modifiers: .command)
      }
      Spacer(minLength: 12)
      Button("Delete All…", role: .destructive) {
        confirmDeleteAll = true
      }
      .disabled(history.entries.isEmpty)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
  }

  private var list: some View {
    ScrollViewReader { reader in
      List {
        ForEach(entries) { entry in
          HistoryRow(
            entry: entry, model: model, expanded: $expanded,
            isSelected: selection == entry.id,
            copied: copied?.id == entry.id ? copied?.label : nil,
            onCopy: { text, label in copy(text, label: label, from: entry) },
            onRemove: { remove(entry) }
          )
          .id(entry.id)
        }
      }
      .listStyle(.inset)
      .focusable()
      .focused($listFocused)
      .focusEffectDisabled()
      .onKeyPress(.upArrow) { move(-1, reader) }
      .onKeyPress(.downArrow) { move(1, reader) }
      .onKeyPress(.rightArrow) { setExpanded(true) }
      .onKeyPress(.leftArrow) { setExpanded(false) }
      .onKeyPress(.return) {
        guard let entry = selectedEntry, let text = entry.leadText else { return .ignored }
        copy(text, label: "Copied", from: entry)
        return .handled
      }
      .onDeleteCommand {
        if let entry = selectedEntry { remove(entry) }
      }
      .onAppear { listFocused = true }
      .accessibilityLabel("History")
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No history", systemImage: "waveform")
    } description: {
      Text("Press \(model.settings.dictateShortcut.displayName) in any text field to dictate.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var selectedEntry: HistoryEntry? {
    entries.first { $0.id == selection }
  }

  private func move(_ offset: Int, _ reader: ScrollViewProxy) -> KeyPress.Result {
    guard !entries.isEmpty else { return .ignored }
    let current = entries.firstIndex { $0.id == selection }
    let next = current.map { min(max($0 + offset, 0), entries.count - 1) } ?? 0
    selection = entries[next].id
    reader.scrollTo(entries[next].id)
    return .handled
  }

  private func setExpanded(_ isExpanded: Bool) -> KeyPress.Result {
    guard let entry = selectedEntry, entry.leadText != nil else { return .ignored }
    if isExpanded {
      expanded.insert(entry.id)
    } else {
      expanded.remove(entry.id)
    }
    return .handled
  }

  private func copy(_ text: String?, label: String, from entry: HistoryEntry) {
    guard let text else { return }
    history.copy(text)
    selection = entry.id
    listFocused = true
    copied = (entry.id, label)
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      if copied?.id == entry.id, copied?.label == label { copied = nil }
    }
  }

  private func remove(_ entry: HistoryEntry) {
    commitRemoval()
    if selection == entry.id, let index = entries.firstIndex(where: { $0.id == entry.id }) {
      let neighbor = index + 1 < entries.count ? index + 1 : index - 1
      selection = neighbor >= 0 ? entries[neighbor].id : nil
    }
    removed = entry
    removalTask = Task {
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled { commitRemoval() }
    }
  }

  private func undoRemoval() {
    removalTask?.cancel()
    selection = removed?.id
    removed = nil
  }

  private func commitRemoval() {
    removalTask?.cancel()
    guard let entry = removed else { return }
    removed = nil
    history.delete(entry)
  }
}

private struct HistoryRow: View {
  private struct Stage: Identifiable {
    let label: String
    var text: String?
    var placeholder = ""
    var id: String { label }
  }

  let entry: HistoryEntry
  @ObservedObject var model: AppModel
  @Binding var expanded: Set<UUID>
  let isSelected: Bool
  let copied: String?
  let onCopy: (String?, String) -> Void
  let onRemove: () -> Void
  @State private var isHovered = false

  var body: some View {
    HStack(alignment: .top, spacing: 4) {
      Group {
        if leadText != nil {
          Button {
            expanded.formSymmetricDifference([entry.id])
          } label: {
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .frame(width: 16, height: 16)
              .contentShape(Rectangle())
          }
          .help(isExpanded ? "Hide stages" : "Show stages")
          .accessibilityLabel(isExpanded ? "Hide stages" : "Show stages")
        } else {
          Color.clear.frame(width: 16, height: 16)
        }
      }
      .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 4) {
        caption

        if let leadText {
          Button {
            onCopy(leadText, "Copied")
          } label: {
            Text(leadText)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
          .accessibilityHint("Copies this text")
        }

        if isExpanded {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(stages) { stage in
              HistoryStageLine(label: stage.label, text: stage.text, placeholder: stage.placeholder)
              {
                onCopy(stage.text, "Copied \(stage.label.lowercased())")
              }
            }
          }
          .padding(.top, 4)
        }
      }
    }
    .buttonStyle(.plain)
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture {
      onCopy(leadText, "Copied")
    }
    .onHover { isHovered = $0 }
    .listRowBackground(
      isSelected
        ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
    )
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
  }

  private var caption: some View {
    HStack(spacing: 8) {
      Text(entry.mode.title)
        .fontWeight(.semibold)
      Text(timestamp)
      if let note {
        Text(note.text)
          .foregroundStyle(note.color)
          .lineLimit(1)
      }
      Spacer(minLength: 12)
      if let copied {
        Label(copied, systemImage: "checkmark")
          .foregroundStyle(.green)
      } else if isHovered, leadText != nil {
        Text("Click to copy")
          .foregroundStyle(.tertiary)
      }
      if entry.status == .failed || entry.status == .dismissed || entry.usedRawFallback {
        Button {
          model.retry(entry)
        } label: {
          Label("Retry", systemImage: "arrow.clockwise")
            .foregroundStyle(Color.accentColor)
        }
        .disabled(
          model.phase.isActive || (entry.audioFileName == nil && entry.rawTranscript == nil)
        )
      }
      Button(action: onRemove) {
        Image(systemName: "xmark")
          .frame(width: 16, height: 16)
          .contentShape(Rectangle())
      }
      .opacity(isHovered ? 1 : 0.5)
      .help("Remove")
      .accessibilityLabel("Remove from history")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var isExpanded: Bool { expanded.contains(entry.id) }

  private var finalText: String? { entry.finalText }
  private var processedText: String? { HistoryEntry.clean(entry.processedText) }
  private var transcript: String? { HistoryEntry.clean(entry.rawTranscript) }
  private var leadText: String? { entry.leadText }

  // Always Final, Polished or Translated, Transcript. A stage that adds nothing says why
  // instead of repeating the text of the stage before it.
  private var stages: [Stage] {
    let llmFailed = entry.usedRawFallback || entry.failureStage == .languageModel
    var processed = Stage(label: entry.mode == .translate ? "Translated" : "Polished")
    if llmFailed {
      processed.placeholder = "LLM failed"
    } else if processedText == nil {
      processed.placeholder = "Not available"
    } else if processedText == transcript {
      processed.placeholder = "Same as transcript"
    } else {
      processed.text = processedText
    }

    var final = Stage(label: "Final")
    if finalText == nil {
      final.placeholder =
        switch entry.submissionState {
        case .pending: "Watching for edits…"
        case .cancelled: "Editing cancelled"
        case .confirmed, .notObserved, .unknown: "Not captured"
        }
    } else if finalText == processedText {
      let source = entry.mode == .translate ? "translation" : "polished"
      final.placeholder = "Same as \(processed.text == nil ? "transcript" : source)"
    } else {
      final.text = finalText
    }

    return [
      final, processed,
      Stage(label: "Transcript", text: transcript, placeholder: "Not available"),
    ]
  }

  private var note: (text: String, color: Color)? {
    switch entry.status {
    case .failed:
      return (entry.failureMessage ?? "Failed", .red)
    case .dismissed:
      return (entry.failureStage == nil ? "Cancelled" : "No speech", .secondary)
    case .retrying:
      return ("Retrying…", .secondary)
    case .succeeded:
      if entry.usedRawFallback { return ("Not polished", .orange) }
      return entry.submissionState == .pending ? ("Watching for edits…", .secondary) : nil
    }
  }

  private var timestamp: String {
    let time = entry.completedAt.formatted(date: .omitted, time: .shortened)
    return Calendar.current.isDateInToday(entry.completedAt) ? time : "Yesterday \(time)"
  }
}

extension HistoryEntry {
  fileprivate var finalText: String? { Self.clean(submittedText) }
  // The text that ended up in the user's app: the captured final edit, else what Purrr inserted.
  fileprivate var leadText: String? {
    finalText ?? Self.clean(processedText) ?? Self.clean(rawTranscript)
  }

  // A field emptied after sending can leave only invisible characters behind.
  fileprivate static func clean(_ text: String?) -> String? {
    let invisible = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
      .union(CharacterSet(charactersIn: "\u{FFFC}"))
    guard let trimmed = text?.trimmingCharacters(in: invisible), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}

private struct HistoryStageLine: View {
  let label: String
  let text: String?
  let placeholder: String
  let onCopy: () -> Void
  @State private var isHovered = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 62, alignment: .leading)
      if let text {
        Button(action: onCopy) {
          Text(text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        .accessibilityHint("Copies this text")
      } else {
        Text(placeholder)
          .italic()
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.callout)
    .padding(.vertical, 2)
  }
}
