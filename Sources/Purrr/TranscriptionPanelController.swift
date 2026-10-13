import AppKit
import SwiftUI

@MainActor
final class TranscriptionPanelController {
  private let panel: NSPanel
  private let shadow = CapsuleShadowPanel(capsuleSize: TranscriptionBarLayout.stripSize)
  private var generation = 0

  init(model: AppModel) {
    let panelSize = TranscriptionBarLayout.panelSize
    panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.acceptsMouseMovedEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let hostingView = NSHostingView(rootView: TranscriptionBarView(model: model))
    hostingView.sizingOptions = []
    hostingView.safeAreaRegions = []
    hostingView.frame = NSRect(origin: .zero, size: panelSize)
    hostingView.autoresizingMask = [.width, .height]
    panel.contentView = hostingView
    panel.contentMinSize = panelSize
    panel.contentMaxSize = panelSize
  }

  func show() {
    let panelSize = TranscriptionBarLayout.panelSize
    panel.setContentSize(panelSize)
    panel.contentView?.frame = NSRect(origin: .zero, size: panelSize)
    position()
    generation += 1
    if panel.isVisible || reduceMotion {
      panel.alphaValue = 1
      shadow.alphaValue = 1
      panel.orderFrontRegardless()
      shadow.attach(below: panel)
    } else {
      panel.alphaValue = 0
      shadow.alphaValue = 0
      panel.orderFrontRegardless()
      shadow.attach(below: panel)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = Self.fadeDuration
        panel.animator().alphaValue = 1
        shadow.animator().alphaValue = 1
      }
    }
  }

  func hide() {
    generation += 1
    guard !reduceMotion else {
      panel.orderOut(nil)
      return
    }
    let hiding = generation
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      panel.animator().alphaValue = 0
      shadow.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      Task { @MainActor in
        guard let self, self.generation == hiding else { return }
        self.panel.orderOut(nil)
      }
    }
  }

  private static let fadeDuration = 0.12

  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private func position() {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else { return }
    let origin = NSPoint(
      x: visibleFrame.midX - panel.frame.width / 2,
      y: visibleFrame.minY + TranscriptionBarLayout.bottomOffset
    )
    panel.setFrameOrigin(origin)
  }

}

// The soft shadow under a charcoal capsule. It is a separate click-through window so the
// shadow's halo never swallows clicks meant for whatever sits behind it.
@MainActor
final class CapsuleShadowPanel: NSPanel {
  private static let margin: CGFloat = 32

  init(capsuleSize: NSSize) {
    let size = NSSize(
      width: capsuleSize.width + Self.margin * 2, height: capsuleSize.height + Self.margin * 2)
    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let hosting = NSHostingView(
      rootView: Capsule(style: .circular)
        .fill(Color.black)
        .frame(width: capsuleSize.width - 2, height: capsuleSize.height - 2)
        .shadow(color: .black.opacity(0.3), radius: 11, y: 8)
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity))
    hosting.sizingOptions = []
    hosting.safeAreaRegions = []
    hosting.frame = NSRect(origin: .zero, size: size)
    contentView = hosting
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func attach(below parent: NSPanel) {
    setFrameOrigin(
      NSPoint(x: parent.frame.midX - frame.width / 2, y: parent.frame.midY - frame.height / 2))
    if self.parent !== parent { parent.addChildWindow(self, ordered: .below) }
  }
}

