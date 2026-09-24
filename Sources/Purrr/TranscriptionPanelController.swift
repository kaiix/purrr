import AppKit
import SwiftUI

@MainActor
final class TranscriptionPanelController {
  private let panel: NSPanel

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
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
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
