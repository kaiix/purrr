import AppKit
import SwiftUI

struct VocabularyNotice {
  let words: [VocabularyWord]
}

enum VocabularyNoticeLayout {
  static let size = NSSize(width: 380, height: 44)
  static let inset: CGFloat = 2
  static var panelSize: NSSize {
    NSSize(width: size.width + inset * 2, height: size.height + inset * 2)
  }
}

@MainActor
final class VocabularyNoticeController: ObservableObject {
  @Published private(set) var notice: VocabularyNotice?
  @Published private(set) var errorMessage: String?
  var onEdit: ((UUID) -> Void)?

  private let vocabulary: VocabularyStore
  private var pending: [VocabularyNotice] = []
  private var panel: NSPanel?
  private var dismissalTask: Task<Void, Never>?
  private var isSuspended = true
  private var isHovering = false

  init(vocabulary: VocabularyStore) {
    self.vocabulary = vocabulary
  }

  deinit { dismissalTask?.cancel() }

  func enqueue(_ words: [VocabularyWord]) {
    guard !words.isEmpty else { return }
    pending.append(VocabularyNotice(words: words))
    showNext()
  }

  func setSuspended(_ suspended: Bool) {
    isSuspended = suspended
    if suspended {
      dismissalTask?.cancel()
      panel?.orderOut(nil)
    } else if notice != nil {
      show()
    } else {
      showNext()
    }
  }

  func setHovering(_ hovering: Bool) {
    isHovering = hovering
    scheduleDismissal()
  }

  func undo() {
    guard let notice else { return }
    do {
      try vocabulary.undoAutoAdded(notice.words)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      scheduleDismissal()
    }
  }

  func edit() {
    guard let id = notice?.words.first?.id else { return }
    dismiss()
    onEdit?(id)
  }

  func dismiss() {
    dismissalTask?.cancel()
    panel?.orderOut(nil)
    notice = nil
    errorMessage = nil
    showNext()
  }

  private func showNext() {
    guard !isSuspended, notice == nil else { return }
    while !pending.isEmpty {
      let words = pending.removeFirst().words.filter { vocabulary.words.contains($0) }
      guard !words.isEmpty else { continue }
      notice = VocabularyNotice(words: words)
      show()
      break
    }
  }

  private func show() {
    if panel == nil { panel = makePanel() }
    guard let panel, let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
      return
    }
    panel.setFrameOrigin(
      NSPoint(
        x: frame.midX - panel.frame.width / 2, y: frame.minY + TranscriptionBarLayout.bottomOffset)
    )
    panel.orderFrontRegardless()
    scheduleDismissal()
  }

  private func scheduleDismissal() {
    dismissalTask?.cancel()
    guard notice != nil, !isSuspended, !isHovering else { return }
    dismissalTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .seconds(7))
        guard !Task.isCancelled else { return }
        self?.dismiss()
      } catch {}
    }
  }

  private func makePanel() -> NSPanel {
    let size = VocabularyNoticeLayout.panelSize
    let panel = VocabularyNoticePanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.acceptsMouseMovedEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let hosting = NSHostingView(rootView: VocabularyNoticeView(controller: self))
    hosting.sizingOptions = []
    hosting.safeAreaRegions = []
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.autoresizingMask = [.width, .height]
    panel.contentView = hosting
    panel.contentMinSize = size
    panel.contentMaxSize = size
    return panel
  }
}

private final class VocabularyNoticePanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
