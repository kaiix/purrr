import SwiftUI

struct HistoryView: View {
  @ObservedObject var history: HistoryStore
  @ObservedObject var model: AppModel
  @State private var confirmDeleteAll = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if history.entries.isEmpty {
        emptyState
      } else {
        List {
          ForEach(history.entries) { entry in
            HistoryRow(entry: entry, history: history, model: model)
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
  let entry: HistoryEntry
  @ObservedObject var history: HistoryStore
  @ObservedObject var model: AppModel

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: statusSymbol)
        .foregroundStyle(statusColor)
        .frame(width: 20, height: 20)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Text(modeTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(timestamp)
            .font(.caption)
            .foregroundStyle(.secondary)
          if entry.usedRawFallback {
            Text("Not polished")
              .font(.caption.weight(.medium))
              .foregroundStyle(.orange)
          }
          if entry.status == .dismissed, let message = entry.failureMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if finalText != nil || processedText != nil || transcript != nil {
          VStack(alignment: .leading, spacing: 6) {
            HistoryTextStage(
              label: "Final",
              text: finalText,
              unavailableText: submittedUnavailableText,
              isPrimary: true,
              onCopy: { history.copy(finalText) }
            )
            HistoryTextStage(
              label: entry.mode == .translate ? "Translated" : "Polished",
              text: processedText,
              unavailableText: processedUnavailableText,
              isPrimary: finalText == nil,
              onCopy: { history.copy(processedText) }
            )
            HistoryTextStage(
              label: "Transcript",
              text: transcript,
              unavailableText: "Not available",
              isPrimary: finalText == nil && processedText == nil,
              onCopy: { history.copy(transcript) }
            )
          }
        }

        if let message = entry.failureMessage, entry.status == .failed {
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 18)

      HStack(spacing: 8) {
        if entry.status == .failed || entry.status == .dismissed || entry.usedRawFallback {
          Button {
            model.retry(entry)
          } label: {
            Label("Retry", systemImage: "arrow.clockwise")
          }
          .disabled(
            model.phase.isActive || (entry.audioFileName == nil && entry.rawTranscript == nil)
          )
        }

        Button(role: .destructive) {
          history.delete(entry)
        } label: {
          Image(systemName: "trash")
        }
        .help("Delete")
        .accessibilityLabel("Delete")
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 10)
  }

  private var finalText: String? { Self.clean(entry.submittedText) }
  private var transcript: String? { Self.clean(entry.rawTranscript) }

  // With the LLM off or failed, the stored output is the transcript itself; don't show it twice.
  private var processedText: String? {
    let processed = Self.clean(entry.processedText)
    return entry.usedRawFallback || processed == transcript ? nil : processed
  }

  private var processedUnavailableText: String {
    if entry.usedRawFallback || entry.failureStage == .languageModel { return "LLM failed" }
    return Self.clean(entry.processedText) == nil ? "Not available" : "Same as transcript"
  }

  private static func clean(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  private var modeTitle: String {
    guard entry.mode == .translate, let language = entry.targetLanguage else {
      return entry.mode.title
    }
    return "\(entry.mode.title) → \(language.title)"
  }

  private var timestamp: String {
    let time = entry.completedAt.formatted(date: .omitted, time: .shortened)
    return Calendar.current.isDateInToday(entry.completedAt) ? time : "Yesterday \(time)"
  }

  private var submittedUnavailableText: String {
    switch entry.submissionState {
    case .pending: "Watching for edits…"
    case .cancelled: "Editing cancelled"
    case .confirmed, .notObserved, .unknown: "Not captured"
    }
  }

  private var statusSymbol: String {
    switch entry.status {
    case .succeeded: "checkmark.circle.fill"
    case .failed: "exclamationmark.circle.fill"
    case .dismissed: "xmark.circle.fill"
    case .retrying: "arrow.clockwise.circle.fill"
    }
  }

  private var statusColor: Color {
    switch entry.status {
    case .succeeded: .green
    case .failed: .red
    case .dismissed: .secondary
    case .retrying: .accentColor
    }
  }
}

private struct HistoryTextStage: View {
  let label: String
  let text: String?
  let unavailableText: String
  var isPrimary = false
  let onCopy: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 66, alignment: .trailing)

      if let text {
        Text(text)
          .font(isPrimary ? .body : .callout)
          .foregroundStyle(isPrimary ? .primary : .secondary)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)

        Button(action: onCopy) {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Copy")
        .accessibilityLabel("Copy \(label.lowercased()) text")
      } else {
        Text(unavailableText)
          .font(.callout)
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}
