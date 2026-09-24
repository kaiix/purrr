import ApplicationServices
import Carbon
import Foundation

private func purrrHotKeyHandler(
  _ nextHandler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let userData else { return noErr }
  var identifier = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &identifier
  )
  guard status == noErr else { return status }
  let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
  DispatchQueue.main.async {
    monitor.handleCarbonHotKey(identifier.id)
  }
  return noErr
}

private func purrrEventTapHandler(
  _ proxy: CGEventTapProxy,
  _ type: CGEventType,
  _ event: CGEvent,
  _ userData: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userData else { return Unmanaged.passUnretained(event) }
  let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()

  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    monitor.enableEventTap()
    return Unmanaged.passUnretained(event)
  }

  return monitor.consume(type: type, event: event)
    ? nil
    : Unmanaged.passUnretained(event)
}

final class GlobalShortcutMonitor {
  var onTrigger: ((SessionMode) -> Void)?
  var onRegistrationChange: ((String?) -> Void)?

  private let signature: OSType = 0x5075_7272  // "Purr"
  private var eventHandler: EventHandlerRef?
  private var hotKeys: [EventHotKeyRef] = []
  private var eventTap: CFMachPort?
  private var eventTapSource: CFRunLoopSource?
  private var shortcuts: [(shortcut: AppShortcut, mode: SessionMode)] = []
  private var consumedKeyCodes: Set<UInt32> = []

  init() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      purrrHotKeyHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
  }

  deinit {
    unregisterAll()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  func register(dictate: AppShortcut, translate: AppShortcut) {
    unregisterAll()
    shortcuts = [(dictate, .dictate), (translate, .translate)]

    if installEventTap() {
      onRegistrationChange?(nil)
      return
    }

    let failed = [
      registerCarbonHotKey(dictate, id: 1) ? nil : dictate.displayName,
      registerCarbonHotKey(translate, id: 2) ? nil : translate.displayName,
    ].compactMap { $0 }

    if failed.isEmpty {
      onRegistrationChange?(nil)
    } else {
      onRegistrationChange?(
        "Could not reserve \(failed.joined(separator: " and ")). Grant Accessibility so Purrr can override shortcuts used by another app."
      )
    }
  }

  fileprivate func handleCarbonHotKey(_ identifier: UInt32) {
    switch identifier {
    case 1: onTrigger?(.dictate)
    case 2: onTrigger?(.translate)
    default: break
    }
  }

  fileprivate func consume(type: CGEventType, event: CGEvent) -> Bool {
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .keyUp, consumedKeyCodes.remove(keyCode) != nil {
      return true
    }

    guard type == .keyDown,
      let mode = shortcuts.first(where: { matches(event, shortcut: $0.shortcut) })?.mode
    else {
      return false
    }

    consumedKeyCodes.insert(keyCode)
    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
      DispatchQueue.main.async { [weak self] in
        self?.onTrigger?(mode)
      }
    }
    return true
  }

  fileprivate func enableEventTap() {
    guard let eventTap else { return }
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  private func installEventTap() -> Bool {
    guard AXIsProcessTrusted() else { return false }

    let eventMask =
      (CGEventMask(1) << CGEventType.keyDown.rawValue)
      | (CGEventMask(1) << CGEventType.keyUp.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: purrrEventTapHandler,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      ),
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    else {
      return false
    }

    eventTap = tap
    eventTapSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  private func registerCarbonHotKey(_ shortcut: AppShortcut, id: UInt32) -> Bool {
    var reference: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: signature, id: id)
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      carbonModifiers(shortcut.modifiers),
      identifier,
      GetApplicationEventTarget(),
      0,
      &reference
    )
    guard status == noErr, let reference else { return false }
    hotKeys.append(reference)
    return true
  }

  private func unregisterAll() {
    for reference in hotKeys {
      UnregisterEventHotKey(reference)
    }
    hotKeys.removeAll()
    consumedKeyCodes.removeAll()

    if let eventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
    }
    eventTapSource = nil
    eventTap = nil
  }

  private func matches(_ event: CGEvent, shortcut: AppShortcut) -> Bool {
    guard UInt32(event.getIntegerValueField(.keyboardEventKeycode)) == shortcut.keyCode else {
      return false
    }
    let relevantFlags = event.flags.intersection([
      .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ])
    return relevantFlags == cgEventFlags(shortcut.modifiers)
  }

  private func cgEventFlags(_ modifiers: ShortcutModifiers) -> CGEventFlags {
    var value: CGEventFlags = []
    if modifiers.contains(.command) { value.insert(.maskCommand) }
    if modifiers.contains(.control) { value.insert(.maskControl) }
    if modifiers.contains(.option) { value.insert(.maskAlternate) }
    if modifiers.contains(.shift) { value.insert(.maskShift) }
    return value
  }

  private func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
    var value: UInt32 = 0
    if modifiers.contains(.command) { value |= UInt32(cmdKey) }
    if modifiers.contains(.control) { value |= UInt32(controlKey) }
    if modifiers.contains(.option) { value |= UInt32(optionKey) }
    if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
    return value
  }
}
