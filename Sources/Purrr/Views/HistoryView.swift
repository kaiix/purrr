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
      Text("This permanently deletes all retained audio and transcripts.")
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 20) {
      VStack(alignment: .leading, spacing: 5) {
        Text("History")
          .font(.system(size: 28, weight: .bold))
        Text("Audio and transcripts stay on this Mac for 24 hours.")
          .foregroundStyle(.secondary)
      }
      Spacer()
      if !history.entries.isEmpty {
        Button("Delete All", role: .destructive) {
          confirmDeleteAll = true
        }
      }
    }
    .padding(24)
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No recent dictations", systemImage: "waveform")
    } description: {
      Text("Completed, failed, and dismissed sessions will appear here for 24 hours.")
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

      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 8) {
          Text(entry.mode.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(entry.completedAt, style: .time)
            .font(.caption)
            .foregroundStyle(.secondary)
          if entry.usedRawFallback {
            Text("Raw fallback")
              .font(.caption.weight(.medium))
              .foregroundStyle(.orange)
          }
        }

        Text(displayText)
          .font(.body)
          .foregroundStyle(entry.preferredCopyText == nil ? .secondary : .primary)
          .lineLimit(3)

        if let message = entry.failureMessage, entry.status != .succeeded {
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 18)

      HStack(spacing: 8) {
        Button {
          history.copy(entry)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(entry.preferredCopyText == nil)

        if entry.status == .failed || entry.status == .dismissed || entry.usedRawFallback {
          Button {
            model.retry(entry)
          } label: {
            Label("Retry", systemImage: "arrow.clockwise")
          }
          .disabled(model.phase.isActive || (entry.audioFileName == nil && entry.sourceText == nil))
        }

        Button(role: .destructive) {
          history.delete(entry)
        } label: {
          Image(systemName: "trash")
        }
        .help("Delete audio and transcript")
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 10)
  }

  private var displayText: String {
    if let text = entry.preferredCopyText { return text }
    return switch entry.status {
    case .dismissed: "The transcription was dismissed."
    case .retrying: "Retrying transcription…"
    case .failed: "No transcript is available."
    case .succeeded: "No speech was detected."
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
