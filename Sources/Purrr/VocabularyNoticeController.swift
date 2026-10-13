import AppKit
import SwiftUI

enum VocabularyNotice {
  case added([VocabularyWord])
  case suggestion(VocabularyCandidate)
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
  var onReview: ((String) -> Void)?

  private let vocabulary: VocabularyStore
  private var pending: [VocabularyNotice] = []
  private var panel: NSPanel?
  private lazy var shadow = CapsuleShadowPanel(capsuleSize: VocabularyNoticeLayout.size)
  private var dismissalTask: Task<Void, Never>?
  private var isSuspended = true
  private var isHovering = false

  init(vocabulary: VocabularyStore) {
    self.vocabulary = vocabulary
  }

  deinit { dismissalTask?.cancel() }

  func enqueue(_ words: [VocabularyWord]) {
    guard !words.isEmpty else { return }
    pending.append(.added(words))
    showNext()
  }

  func enqueue(suggestions: [VocabularyCandidate]) {
    for candidate in suggestions {
      // One prompt per spelling while a notice is already displayed or queued.
      let alreadyQueued = (pending + [notice].compactMap { $0 }).contains {
        if case .suggestion(let other) = $0 {
          return VocabularyStore.key(other.correctedTerm)
            == VocabularyStore.key(candidate.correctedTerm)
        }
        return false
      }
      if !alreadyQueued { pending.append(.suggestion(candidate)) }
    }
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
    guard case .added(let words) = notice else { return }
    do {
      try vocabulary.undoAutoAdded(words)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      scheduleDismissal()
    }
  }

  func edit() {
    guard let notice else { return }
    dismiss()
    switch notice {
    case .added(let words):
      if let id = words.first?.id { onEdit?(id) }
    case .suggestion(let candidate):
      onReview?(candidate.id)
    }
  }

  func addSuggestion() {
    guard case .suggestion(let candidate) = notice else { return }
    // Recheck validity after the notice's network delay or queue wait.
    guard vocabulary.candidates.contains(candidate) else {
      dismiss()
      return
    }
    do {
      try vocabulary.confirm(candidate, term: candidate.correctedTerm)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      scheduleDismissal()
    }
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
      let next = pending.removeFirst()
      guard vocabulary.collectsEdits else { continue }
      switch next {
      case .added(let batch):
        let words = batch.filter { vocabulary.words.contains($0) }
        guard !words.isEmpty else { continue }
        notice = .added(words)
      case .suggestion(let candidate):
        guard vocabulary.candidates.contains(candidate) else { continue }
        notice = next
      }
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
    shadow.attach(below: panel)
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
