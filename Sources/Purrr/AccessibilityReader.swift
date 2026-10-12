import AppKit
import ApplicationServices

struct SubmissionTargetDescriptor: Equatable {
  enum ControlKind: Equatable {
    case singleLine
    case multiLine
    case unknown
  }

  struct Ancestor: Equatable, Hashable {
    let role: String?
    let subrole: String?
    let identifier: String?
    let domIdentifier: String?
  }

  let processIdentifier: pid_t
  let bundleIdentifier: String?
  let elementIdentity: UInt
  let windowNumber: Int?
  let windowIdentifier: String?
  let windowTitle: String?
  let documentIdentifier: String?
  let role: String?
  let subrole: String?
  let identifier: String?
  let domIdentifier: String?
  let placeholder: String?
  let capabilities: Set<String>
  let ancestors: [Ancestor]
  let frame: CGRect?

  init(
    processIdentifier: pid_t,
    bundleIdentifier: String? = nil,
    elementIdentity: UInt = 0,
    windowNumber: Int? = nil,
    windowIdentifier: String? = nil,
    windowTitle: String? = nil,
    documentIdentifier: String? = nil,
    role: String? = nil,
    subrole: String? = nil,
    identifier: String? = nil,
    domIdentifier: String? = nil,
    placeholder: String? = nil,
    capabilities: Set<String> = [],
    ancestors: [Ancestor] = [],
    frame: CGRect? = nil
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.elementIdentity = elementIdentity
    self.windowNumber = windowNumber
    self.windowIdentifier = windowIdentifier
    self.windowTitle = windowTitle
    self.documentIdentifier = documentIdentifier
    self.role = role
    self.subrole = subrole
    self.identifier = identifier
    self.domIdentifier = domIdentifier
    self.placeholder = placeholder
    self.capabilities = capabilities
    self.ancestors = ancestors
    self.frame = frame
  }

  var controlKind: ControlKind {
    let normalizedRole = role?.lowercased() ?? ""
    if role == kAXTextAreaRole as String || normalizedRole.contains("multiline")
      || normalizedRole.contains("textarea")
    {
      return .multiLine
    }
    if role == kAXTextFieldRole as String || role == kAXComboBoxRole as String
      || normalizedRole.contains("textfield")
    {
      return .singleLine
    }
    return .unknown
  }

  var isEditable: Bool {
    controlKind != .unknown
      || capabilities.contains("settable-value")
      || capabilities.contains("selected-text-range")
  }

  func match(_ other: SubmissionTargetDescriptor) -> SubmissionTargetMatch {
    guard processIdentifier == other.processIdentifier else {
      return SubmissionTargetMatch(
        relationship: .differentControl,
        controlConfidence: 1,
        contextConfidence: 0
      )
    }
    if let bundleIdentifier, let otherBundleIdentifier = other.bundleIdentifier,
      bundleIdentifier != otherBundleIdentifier
    {
      return SubmissionTargetMatch(
        relationship: .differentControl,
        controlConfidence: 1,
        contextConfidence: 0
      )
    }

    let contextConfidence = contextConfidence(with: other)
    if definitelyDifferentWindow(from: other) {
      return SubmissionTargetMatch(
        relationship: .differentControl,
        controlConfidence: 0.96,
        contextConfidence: contextConfidence
      )
    }
    if elementIdentity != 0, elementIdentity == other.elementIdentity {
      return SubmissionTargetMatch(
        relationship: .sameControl,
        controlConfidence: 0.99,
        contextConfidence: contextConfidence
      )
    }
    if hasSharedStableIdentifier(with: other), rolesAreCompatible(with: other) {
      return SubmissionTargetMatch(
        relationship: .sameControl,
        controlConfidence: 0.98,
        contextConfidence: contextConfidence
      )
    }

    var score = 0.02
    score += equalityScore(bundleIdentifier, other.bundleIdentifier, match: 0.02, mismatch: -0.1)
    score += equalityScore(windowNumber, other.windowNumber, match: 0.04, mismatch: -0.25)
    score += equalityScore(windowIdentifier, other.windowIdentifier, match: 0.04, mismatch: -0.2)
    score += equalityScore(
      documentIdentifier, other.documentIdentifier, match: 0.02, mismatch: -0.2)
    score += equalityScore(role, other.role, match: 0.12, mismatch: -0.24)
    score += equalityScore(subrole, other.subrole, match: 0.04, mismatch: -0.08)
    if controlKind != .unknown, controlKind == other.controlKind {
      score += 0.12
    } else if controlKind != .unknown, other.controlKind != .unknown {
      score -= 0.18
    }
    score += equalityScore(identifier, other.identifier, match: 0.28, mismatch: -0.12)
    score += equalityScore(domIdentifier, other.domIdentifier, match: 0.3, mismatch: -0.12)
    score += equalityScore(placeholder, other.placeholder, match: 0.08, mismatch: -0.04)
    score += ancestorSimilarity(with: other) * 0.1
    score += capabilitySimilarity(with: other) * 0.04
    score += geometrySimilarity(with: other) * 0.3
    score = min(1, max(0, score))

    let relationship: SubmissionTargetMatch.Relationship
    if score >= 0.65 {
      relationship = .sameControl
    } else if score <= 0.4 {
      relationship = .differentControl
    } else {
      relationship = .uncertain
    }
    return SubmissionTargetMatch(
      relationship: relationship,
      controlConfidence: score,
      contextConfidence: contextConfidence
    )
  }

  private func definitelyDifferentWindow(from other: SubmissionTargetDescriptor) -> Bool {
    if let windowNumber, let otherWindowNumber = other.windowNumber,
      windowNumber != otherWindowNumber
    {
      return true
    }
    if let windowIdentifier, let otherWindowIdentifier = other.windowIdentifier,
      windowIdentifier != otherWindowIdentifier
    {
      return true
    }
    return false
  }

  private func hasSharedStableIdentifier(with other: SubmissionTargetDescriptor) -> Bool {
    (identifier != nil && identifier == other.identifier)
      || (domIdentifier != nil && domIdentifier == other.domIdentifier)
  }

  private func rolesAreCompatible(with other: SubmissionTargetDescriptor) -> Bool {
    if let role, let otherRole = other.role, role == otherRole {
      return true
    }
    return controlKind != .unknown && controlKind == other.controlKind
  }

  private func contextConfidence(with other: SubmissionTargetDescriptor) -> Double {
    var score = 0.2
    score += equalityScore(bundleIdentifier, other.bundleIdentifier, match: 0.15, mismatch: -0.3)
    score += equalityScore(windowNumber, other.windowNumber, match: 0.2, mismatch: -0.4)
    score += equalityScore(windowIdentifier, other.windowIdentifier, match: 0.15, mismatch: -0.3)
    score += equalityScore(
      documentIdentifier, other.documentIdentifier, match: 0.25, mismatch: -0.45)
    score += equalityScore(windowTitle, other.windowTitle, match: 0.05, mismatch: -0.03)
    return min(1, max(0, score))
  }

  private func equalityScore<T: Equatable>(
    _ lhs: T?,
    _ rhs: T?,
    match: Double,
    mismatch: Double
  ) -> Double {
    guard let lhs, let rhs else { return 0 }
    return lhs == rhs ? match : mismatch
  }

  private func ancestorSimilarity(with other: SubmissionTargetDescriptor) -> Double {
    let count = min(ancestors.count, other.ancestors.count)
    guard count > 0 else { return 0 }

    var total = 0.0
    for index in 0..<count {
      let lhs = ancestors[index]
      let rhs = other.ancestors[index]
      if lhs.role != nil, lhs.role == rhs.role { total += 0.5 }
      if lhs.subrole != nil, lhs.subrole == rhs.subrole { total += 0.1 }
      if lhs.identifier != nil, lhs.identifier == rhs.identifier { total += 0.2 }
      if lhs.domIdentifier != nil, lhs.domIdentifier == rhs.domIdentifier { total += 0.2 }
    }
    return total / Double(count)
  }

  private func capabilitySimilarity(with other: SubmissionTargetDescriptor) -> Double {
    guard !capabilities.isEmpty, !other.capabilities.isEmpty else { return 0 }
    let intersection = capabilities.intersection(other.capabilities).count
    let union = capabilities.union(other.capabilities).count
    return union == 0 ? 0 : Double(intersection) / Double(union)
  }

  private func geometrySimilarity(with other: SubmissionTargetDescriptor) -> Double {
    guard let frame, let otherFrame = other.frame else { return 0 }
    let reference = max(max(frame.width, frame.height), 80)
    let distance = hypot(frame.midX - otherFrame.midX, frame.midY - otherFrame.midY)
    let positionScore = max(0, 1 - distance / (reference * 1.5))
    let widthReference = max(max(frame.width, otherFrame.width), 1)
    let widthScore = max(0, 1 - abs(frame.width - otherFrame.width) / widthReference)
    let topScore = max(0, 1 - abs(frame.minY - otherFrame.minY) / reference)
    return positionScore * 0.55 + widthScore * 0.3 + topScore * 0.15
  }
}

struct SubmissionTargetMatch: Equatable {
  enum Relationship: Equatable {
    case sameControl
    case differentControl
    case uncertain
  }

  let relationship: Relationship
  let controlConfidence: Double
  let contextConfidence: Double
}

struct AccessibleTextSnapshot {
  let element: AXUIElement
  let text: String?
  let target: SubmissionTargetDescriptor
}

enum AccessibilityReader {
  private static let maximumTextLength = 100_000
  private static let maximumAncestorDepth = 8

  static func focusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    return elementAttribute(systemWide, kAXFocusedUIElementAttribute as String)
  }

  static func focusedTextSnapshot(processIdentifier: pid_t) -> AccessibleTextSnapshot? {
    guard let element = focusedElement(), pid(of: element) == processIdentifier else {
      return nil
    }
    return textSnapshot(startingAt: element, processIdentifier: processIdentifier)
  }

  static func textSnapshot(
    startingAt element: AXUIElement,
    processIdentifier: pid_t
  ) -> AccessibleTextSnapshot? {
    guard pid(of: element) == processIdentifier else { return nil }

    var current: AXUIElement? = element
    for _ in 0..<maximumAncestorDepth {
      guard let candidate = current else { break }
      let role = stringAttribute(candidate, kAXRoleAttribute as String)
      if isEditableTextElement(candidate, role: role) {
        return AccessibleTextSnapshot(
          element: candidate,
          text: textValue(of: candidate),
          target: descriptor(of: candidate, processIdentifier: processIdentifier)
        )
      }
      current = elementAttribute(candidate, kAXParentAttribute as String)
    }

    return AccessibleTextSnapshot(
      element: element,
      text: textValue(of: element),
      target: descriptor(of: element, processIdentifier: processIdentifier)
    )
  }

  static func textValue(of element: AXUIElement) -> String? {
    if let value = attribute(element, kAXValueAttribute as String) {
      if let string = value as? String {
        return string
      }
      if let attributedString = value as? NSAttributedString {
        return attributedString.string
      }
    }
    return parameterizedTextValue(of: element)
  }

  static func descriptor(
    of element: AXUIElement,
    processIdentifier: pid_t
  ) -> SubmissionTargetDescriptor {
    let window = elementAttribute(element, kAXWindowAttribute as String)
    let attributeNames = Set(attributeNames(of: element))
    var capabilities = Set<String>()
    if isAttributeSettable(element, kAXValueAttribute as String) {
      capabilities.insert("settable-value")
    }
    if attributeNames.contains(kAXSelectedTextRangeAttribute as String) {
      capabilities.insert("selected-text-range")
    }
    if attributeNames.contains(kAXNumberOfCharactersAttribute as String) {
      capabilities.insert("character-range")
    }
    capabilities.formUnion(actionNames(of: element).map { "action:\($0)" })

    return SubmissionTargetDescriptor(
      processIdentifier: processIdentifier,
      bundleIdentifier: NSRunningApplication(processIdentifier: processIdentifier)?
        .bundleIdentifier,
      elementIdentity: CFHash(element),
      windowNumber: window.flatMap { integerAttribute($0, "AXWindowNumber") },
      windowIdentifier: window.flatMap { stringAttribute($0, kAXIdentifierAttribute as String) },
      windowTitle: window.flatMap { stringAttribute($0, kAXTitleAttribute as String) },
      documentIdentifier: firstStringLikeAttribute(
        startingAt: element,
        window: window,
        names: [kAXDocumentAttribute as String, kAXURLAttribute as String]
      ),
      role: stringAttribute(element, kAXRoleAttribute as String),
      subrole: stringAttribute(element, kAXSubroleAttribute as String),
      identifier: stringAttribute(element, kAXIdentifierAttribute as String),
      domIdentifier: stringAttribute(element, kAXDOMIdentifierAttribute as String),
      placeholder: stringAttribute(element, kAXPlaceholderValueAttribute as String),
      capabilities: capabilities,
      ancestors: ancestors(of: element),
      frame: frame(of: element)
    )
  }

  private static func ancestors(of element: AXUIElement) -> [SubmissionTargetDescriptor.Ancestor] {
    var result: [SubmissionTargetDescriptor.Ancestor] = []
    var current = elementAttribute(element, kAXParentAttribute as String)
    while let candidate = current, result.count < maximumAncestorDepth {
      result.append(
        SubmissionTargetDescriptor.Ancestor(
          role: stringAttribute(candidate, kAXRoleAttribute as String),
          subrole: stringAttribute(candidate, kAXSubroleAttribute as String),
          identifier: stringAttribute(candidate, kAXIdentifierAttribute as String),
          domIdentifier: stringAttribute(candidate, kAXDOMIdentifierAttribute as String)
        )
      )
      current = elementAttribute(candidate, kAXParentAttribute as String)
    }
    return result
  }

  private static func firstStringLikeAttribute(
    startingAt element: AXUIElement,
    window: AXUIElement?,
    names: [String]
  ) -> String? {
    var current: AXUIElement? = element
    for _ in 0..<maximumAncestorDepth {
      guard let candidate = current else { break }
      for name in names {
        if let value = stringLikeAttribute(candidate, name) {
          return value
        }
      }
      current = elementAttribute(candidate, kAXParentAttribute as String)
    }
    if let window {
      for name in names {
        if let value = stringLikeAttribute(window, name) {
          return value
        }
      }
    }
    return nil
  }

  private static func parameterizedTextValue(of element: AXUIElement) -> String? {
    guard
      let numberOfCharacters = integerAttribute(
        element,
        kAXNumberOfCharactersAttribute as String
      )
    else {
      return nil
    }
    guard numberOfCharacters > 0 else { return "" }

    var range = CFRange(
      location: 0,
      length: min(numberOfCharacters, maximumTextLength)
    )
    guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
      ) == .success,
      let value
    else {
      return nil
    }
    if let string = value as? String {
      return string
    }
    if let attributedString = value as? NSAttributedString {
      return attributedString.string
    }
    return nil
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attribute(element, kAXPositionAttribute as String),
      let sizeValue = attribute(element, kAXSizeAttribute as String),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else {
      return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
      AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
      return nil
    }
    return CGRect(origin: position, size: size)
  }

  private static func pid(of element: AXUIElement) -> pid_t? {
    var processIdentifier: pid_t = 0
    guard AXUIElementGetPid(element, &processIdentifier) == .success else { return nil }
    return processIdentifier
  }

  private static func isTextControl(role: String?) -> Bool {
    let normalizedRole = role?.lowercased() ?? ""
    return role == kAXTextFieldRole as String
      || role == kAXTextAreaRole as String
      || role == kAXComboBoxRole as String
      || normalizedRole.contains("textfield")
      || normalizedRole.contains("textarea")
      || normalizedRole.contains("multiline")
  }

  private static func isEditableTextElement(_ element: AXUIElement, role: String?) -> Bool {
    if isTextControl(role: role) || isAttributeSettable(element, kAXValueAttribute as String) {
      return true
    }
    return attributeNames(of: element).contains(kAXSelectedTextRangeAttribute as String)
  }

  private static func attributeNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
      let names = names as? [String]
    else {
      return []
    }
    return names
  }

  private static func actionNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
      let names = names as? [String]
    else {
      return []
    }
    return names
  }

  private static func isAttributeSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else {
      return false
    }
    return settable.boolValue
  }

  private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
  }

  private static func stringLikeAttribute(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    if let string = value as? String { return string }
    if let url = value as? URL { return url.absoluteString }
    return nil
  }

  private static func integerAttribute(_ element: AXUIElement, _ name: String) -> Int? {
    guard let value = attribute(element, name) else { return nil }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return value as? Int
  }

  private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return (value as! AXUIElement)
  }

  private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
      let value
    else {
      return nil
    }
    return value
  }
}
