import SwiftUI

struct VocabularyNoticeView: View {
  @ObservedObject var controller: VocabularyNoticeController

  var body: some View {
    Group {
      if let notice = controller.notice {
        HStack(spacing: 10) {
          Button {
            controller.edit()
          } label: {
            Text(
              controller.errorMessage == nil ? message(notice) : recoveryMessage(notice)
            )
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(controller.errorMessage ?? "\(message(notice)). Open in Vocabulary")
          .accessibilityLabel(controller.errorMessage ?? message(notice))
          .accessibilityHint("Opens Vocabulary to edit")

          if controller.errorMessage == nil {
            switch notice {
            case .added:
              Button("Undo") { controller.undo() }
            case .suggestion:
              Button("Add") { controller.addSuggestion() }
              Button("Review") { controller.edit() }
            }
          }
        }
        .buttonStyle(StripTextButtonStyle())
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(width: VocabularyNoticeLayout.size.width, height: VocabularyNoticeLayout.size.height)
        .background(Capsule().fill(Color(red: 0.035, green: 0.035, blue: 0.04)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.75))
        .environment(\.colorScheme, .dark)
        .onHover { controller.setHovering($0) }
      }
    }
    .padding(VocabularyNoticeLayout.inset)
  }

  private func message(_ notice: VocabularyNotice) -> String {
    switch notice {
    case .added(let words):
      guard words.count == 1, let word = words.first else {
        return "\(words.count) words added to vocabulary"
      }
      return "“\(word.term)” added to vocabulary"
    case .suggestion(let candidate):
      return "Possible word: “\(candidate.correctedTerm)”"
    }
  }

  private func recoveryMessage(_ notice: VocabularyNotice) -> String {
    switch notice {
    case .added: return "Couldn’t undo. Click to edit."
    case .suggestion: return "Couldn’t add. Click to review."
    }
  }
}
