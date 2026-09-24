import AppKit
import ApplicationServices
import Foundation

enum DeliveryResult {
  case pasted
  case copiedBecauseFocusChanged
  case copiedBecauseAccessibilityUnavailable
  case copiedBecausePasteFailed

  var message: String {
    switch self {
    case .pasted:
      "Inserted"
    case .copiedBecauseFocusChanged:
      "Focus changed — copied"
    case .copiedBecauseAccessibilityUnavailable:
      "Accessibility unavailable — copied"
    case .copiedBecausePasteFailed:
      "Paste failed — copied"
    }
  }
}

final class TextDeliveryService {
  func captureDestination() -> CapturedDestination? {
    guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
    return CapturedDestination(
      processIdentifier: application.processIdentifier,
      bundleIdentifier: application.bundleIdentifier,
      focusedElement: focusedElement()
    )
  }

  func deliver(_ text: String, to destination: CapturedDestination?) -> DeliveryResult {
    let pasteboard = NSPasteboard.general
    let previousString = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      return .copiedBecausePasteFailed
    }
    let insertedChangeCount = pasteboard.changeCount

    guard AXIsProcessTrusted() else {
      return .copiedBecauseAccessibilityUnavailable
    }
    guard let destination,
      NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
      let originalElement = destination.focusedElement,
      let currentElement = focusedElement(),
      CFEqual(originalElement, currentElement)
    else {
      return .copiedBecauseFocusChanged
    }

    guard let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
    else {
      return .copiedBecausePasteFailed
    }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)

    if let previousString {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        guard pasteboard.changeCount == insertedChangeCount,
          pasteboard.string(forType: .string) == text
        else {
          return
        }
        pasteboard.clearContents()
        pasteboard.setString(previousString, forType: .string)
      }
    }
    return .pasted
  }

  static func requestAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  private func focusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedUIElementAttribute as CFString,
        &value
      ) == .success,
      let value
    else {
      return nil
    }
    return (value as! AXUIElement)
  }
}
