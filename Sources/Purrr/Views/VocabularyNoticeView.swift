import SwiftUI

struct VocabularyNoticeView: View {
  @ObservedObject var controller: VocabularyNoticeController

  var body: some View {
    Group {
      if let notice = controller.notice {
        HStack(spacing: 10) {
          Image(systemName: "text.badge.plus")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(controller.errorMessage == nil ? title(notice) : "Couldn’t undo")
              .font(.system(size: 13, weight: .semibold))
            Text(summary(notice))
              .font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.8))
          }
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
          .help(controller.errorMessage ?? notice.words.map(\.term).joined(separator: ", "))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            title(notice) + ": " + notice.words.map(\.term).joined(separator: ", ")
          )
          .accessibilityValue(controller.errorMessage ?? "")

          Button("Undo") { controller.undo() }
            .help("Remove only the words added by this notice")
          Button("Edit") { controller.edit() }
            .help("Open the first added word in Vocabulary")
          Button {
            controller.dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Keep words and dismiss notice")
          .help("Keep words and close")
        }
        .controlSize(.small)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(width: VocabularyNoticeLayout.size.width, height: VocabularyNoticeLayout.size.height)
        .background(Capsule().fill(Color(red: 0.035, green: 0.035, blue: 0.04)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onHover { controller.setHovering($0) }
      }
    }
    .padding(VocabularyNoticeLayout.inset)
  }

  private func title(_ notice: VocabularyNotice) -> String {
    notice.words.count == 1 ? "Added to vocabulary" : "Added \(notice.words.count) words"
  }

  private func summary(_ notice: VocabularyNotice) -> String {
    guard let first = notice.words.first else { return "" }
    return notice.words.count == 1 ? first.term : "\(first.term) + \(notice.words.count - 1) more"
  }
}
