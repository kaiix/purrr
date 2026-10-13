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
            Text(controller.errorMessage == nil ? message(notice) : "Couldn’t undo. Click to edit.")
              .font(.system(size: 13, weight: .medium))
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(controller.errorMessage ?? "Edit in Vocabulary")
          .accessibilityLabel(controller.errorMessage ?? message(notice))
          .accessibilityHint("Opens Vocabulary to edit")

          if controller.errorMessage == nil {
            Button("Undo") { controller.undo() }
              .controlSize(.small)
          }
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(width: VocabularyNoticeLayout.size.width, height: VocabularyNoticeLayout.size.height)
        .background(Capsule().fill(Color(red: 0.035, green: 0.035, blue: 0.04)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onHover { controller.setHovering($0) }
      }
    }
    .padding(VocabularyNoticeLayout.inset)
  }

  private func message(_ notice: VocabularyNotice) -> String {
    guard notice.words.count == 1, let word = notice.words.first else {
      return "\(notice.words.count) words added to vocabulary"
    }
    return "“\(word.term)” added to vocabulary"
  }
}
