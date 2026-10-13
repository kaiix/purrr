import SwiftUI

struct HistoryView: View {
  @ObservedObject var history: HistoryStore
  @ObservedObject var model: AppModel
  @State private var confirmDeleteAll = false
  @State private var expanded: Set<UUID> = []

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if history.entries.isEmpty {
        emptyState
      } else {
        List {
          ForEach(history.entries) { entry in
            HistoryRow(entry: entry, history: history, model: model, expanded: $expanded)
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(minWidth: 720, minHeight: 480)
    .alert("Delete all history?", isPresented: $confirmDeleteAll) {
      Button("Cancel", role: .cancel) {}
      Button("Delete All", role: .destructive) {
        history.deleteAll()
      }
    } message: {
      Text("All audio and text are deleted from this Mac.")
    }
  }

  private var header: some View {
    HStack(spacing: 20) {
      Text("Kept on this Mac for 24 hours.")
        .foregroundStyle(.secondary)
      Spacer()
      Button("Delete All…", role: .destructive) {
        confirmDeleteAll = true
      }
      .disabled(history.entries.isEmpty)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No history", systemImage: "waveform")
    } description: {
      Text("Press \(model.settings.dictateShortcut.displayName) in any text field to dictate.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
  @ObservedObject var history: HistoryStore
  @ObservedObject var model: AppModel
  @Binding var expanded: Set<UUID>
  @State private var isHovered = false
  @State private var copied: String?

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
      .foregroundStyle(.tertiary)

      VStack(alignment: .leading, spacing: 4) {
        caption

        if let leadText {
          Button {
            copy(leadText, confirmation: "Copied")
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
                copy(stage.text, confirmation: "Copied \(stage.label.lowercased())")
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
      copy(leadText, confirmation: "Copied")
    }
    .onHover { isHovered = $0 }
    .listRowBackground(isHovered ? Color.primary.opacity(0.05) : Color.clear)
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
      Button {
        history.delete(entry)
      } label: {
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

  private func copy(_ text: String?, confirmation: String) {
    guard let text else { return }
    history.copy(text)
    copied = confirmation
    Task {
      try? await Task.sleep(for: .seconds(1.5))
      if copied == confirmation { copied = nil }
    }
  }

  private var finalText: String? { Self.clean(entry.submittedText) }
  private var processedText: String? { Self.clean(entry.processedText) }
  private var transcript: String? { Self.clean(entry.rawTranscript) }
  private var leadText: String? { finalText ?? processedText ?? transcript }

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

  private static func clean(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
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
        .foregroundStyle(.tertiary)
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
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .font(.callout)
    .padding(.vertical, 2)
  }
}
