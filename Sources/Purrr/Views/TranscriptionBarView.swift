import AppKit
import SwiftUI

enum TranscriptionBarLayout {
  static let stripSize = NSSize(width: 136, height: 40)
  static let panelInset: CGFloat = 2
  static let bottomOffset: CGFloat = 12

  static var panelSize: NSSize {
    NSSize(
      width: stripSize.width + panelInset * 2,
      height: stripSize.height + panelInset * 2
    )
  }
}

struct TranscriptionBarView: View {
  @ObservedObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false

  var body: some View {
    ZStack {
      switch model.phase {
      case .recording:
        recordingControls.transition(.opacity)
      case .recognizing, .processing, .delivering:
        workingStatus.transition(.opacity)
      case .succeeded:
        resultStatus(symbol: "checkmark", tint: .green, title: successTitle)
          .transition(.opacity)
      case .failed:
        failureStatus.transition(.opacity)
      case .idle:
        EmptyView()
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: stateID)
    .environment(\.colorScheme, .dark)
    .onHover { hovering in
      isHovered = hovering
      model.setStripHovering(hovering)
    }
    .frame(
      width: TranscriptionBarLayout.stripSize.width,
      height: TranscriptionBarLayout.stripSize.height
    )
    .padding(TranscriptionBarLayout.panelInset)
  }

  private var recordingControls: some View {
    HStack(spacing: 8) {
      StripActionButton(
        symbol: "xmark",
        help: "Cancel recording",
        appearance: .cancel
      ) {
        model.cancelRecording()
      }

      Group {
        if model.isInFinalMinute {
          Text(countdownText)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
        } else {
          VoiceWaveformView(level: model.audioLevel, reduceMotion: reduceMotion)
        }
      }
      .frame(width: 44, height: 28)
      .accessibilityHidden(true)

      StripActionButton(
        symbol: "checkmark",
        help: "Finish recording",
        appearance: .finish
      ) {
        guard let mode = model.activeMode else { return }
        model.toggle(mode)
      }
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(stripBackground)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibilitySummary)
  }

  // Every state after recording keeps its mark in the slot the Cancel button occupied.
  private var workingStatus: some View {
    HStack(spacing: 0) {
      ZStack {
        if isHovered && model.phase != .delivering {
          StripActionButton(symbol: "xmark", help: "Cancel", appearance: .cancel) {
            model.cancelProcessing()
          }
        } else {
          ProcessingIndicator(reduceMotion: reduceMotion)
        }
      }
      .frame(width: 28, height: 28)
      label(primaryText)
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(stripBackground)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibilitySummary)
  }

  @ViewBuilder
  private var failureStatus: some View {
    let status = resultStatus(
      symbol: "exclamationmark", tint: .red, title: model.failureTitle,
      showsChevron: model.failureAction != nil)
    if model.failureAction == nil {
      status.help(model.statusMessage)
    } else {
      Button(action: model.openFailureFix) { status }
        .buttonStyle(.plain)
        .help("\(model.statusMessage) Click to open Settings.")
        .accessibilityHint("Opens Settings")
    }
  }

  private func resultStatus(
    symbol: String,
    tint: Color,
    title: String,
    showsChevron: Bool = false
  ) -> some View {
    HStack(spacing: 0) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)
        .background(tint.opacity(0.3), in: Circle())
      label(title)
        .padding(.trailing, showsChevron ? 0 : 4)
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.white.opacity(0.5))
      }
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(stripBackground)
    .contentShape(Capsule(style: .circular))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilitySummary)
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.white.opacity(0.94))
      .lineLimit(1)
      .minimumScaleFactor(0.9)
      .frame(maxWidth: .infinity)
      .padding(.leading, 6)
      .padding(.trailing, 2)
  }

  private var stripBackground: some View {
    Capsule(style: .circular)
      .fill(Color(red: 0.035, green: 0.035, blue: 0.04).opacity(0.98))
      .overlay {
        Capsule(style: .circular)
          .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
      }
  }

  private var primaryText: String {
    switch model.phase {
    case .recognizing:
      "Transcribing"
    case .processing:
      model.activeMode == .translate ? "Translating" : "Polishing"
    case .delivering:
      "Inserting"
    default:
      model.activeMode?.title ?? "Purrr"
    }
  }

  // Transitions follow the kind of state, not its message.
  private var stateID: Int {
    switch model.phase {
    case .idle: 0
    case .recording: 1
    case .recognizing, .processing, .delivering: 2
    case .succeeded: 3
    case .failed: 4
    }
  }

  private var countdownText: String {
    let seconds = max(0, Int(model.remainingTime.rounded(.up)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private var successTitle: String {
    if model.statusMessage.localizedCaseInsensitiveContains("copied") {
      return "Copied"
    }
    return model.statusMessage
  }

  private var accessibilitySummary: String {
    switch model.phase {
    case .recording where model.isInFinalMinute:
      "Purrr \(model.activeMode?.title ?? "recording"), ends in \(Int(model.remainingTime.rounded(.up))) seconds"
    case .recording:
      "Purrr \(model.activeMode?.title ?? "recording"), recording"
    case .failed:
      "Purrr could not finish. \(model.statusMessage)"
    case .succeeded:
      "Purrr \(model.statusMessage)"
    default:
      "Purrr \(primaryText)"
    }
  }
}

private struct VoiceWaveformView: View {
  let level: Double
  let reduceMotion: Bool

  @State private var samples = Array(repeating: CGFloat(0), count: 10)

  var body: some View {
    HStack(spacing: 2) {
      ForEach(samples.indices, id: \.self) { index in
        Capsule(style: .continuous)
          .fill(Color.white.opacity(barOpacity(at: index)))
          .frame(width: 2, height: barHeight(for: samples[index]))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      append(level)
    }
    .onChange(of: level) { _, newLevel in
      append(newLevel)
    }
  }

  private func append(_ newLevel: Double) {
    let clamped = min(1, max(0, newLevel))
    let normalized = clamped < 0.025 ? CGFloat(0) : CGFloat(pow(clamped, 0.58))

    if reduceMotion {
      samples = Array(repeating: normalized, count: samples.count)
      return
    }

    var next = samples
    next.removeFirst()
    next.append(normalized)
    withAnimation(.easeOut(duration: 0.08)) {
      samples = next
    }
  }

  private func barHeight(for sample: CGFloat) -> CGFloat {
    // Silence keeps a short baseline so the strip never looks switched off.
    3 + sample * 15
  }

  private func barOpacity(at index: Int) -> Double {
    let distanceFromLatest = samples.count - index - 1
    // Quiet bars recede; the newest stays bright as proof the microphone is live.
    let age = max(0.5, 0.96 - Double(distanceFromLatest) * 0.05)
    return distanceFromLatest == 0 ? age : age * (0.6 + 0.4 * min(1, Double(samples[index]) * 3))
  }
}

private struct ProcessingIndicator: View {
  let reduceMotion: Bool

  @State private var isAnimating = false
  private let heights: [CGFloat] = [5, 10, 7]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(heights.indices, id: \.self) { index in
        Capsule(style: .continuous)
          .fill(Color.white.opacity(0.72))
          .frame(width: 2, height: isAnimating ? heights[index] : 4)
          .animation(
            reduceMotion
              ? nil
              : .easeInOut(duration: 0.52)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.11),
            value: isAnimating
          )
      }
    }
    .frame(width: 10, height: 14)
    .onAppear {
      isAnimating = !reduceMotion
    }
  }
}

private struct StripActionButton: View {
  enum Appearance {
    case cancel
    case finish
  }

  let symbol: String
  let help: String
  let appearance: Appearance
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
    }
    .buttonStyle(StripCircleButtonStyle(appearance: appearance, isHovered: isHovered))
    .onHover { isHovered = $0 }
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct StripCircleButtonStyle: ButtonStyle {
  let appearance: StripActionButton.Appearance
  let isHovered: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 10.5, weight: .semibold))
      .foregroundStyle(
        appearance == .finish ? Color.black.opacity(0.88) : Color.white.opacity(0.94)
      )
      .frame(width: 28, height: 28)
      .background(backgroundColor(isPressed: configuration.isPressed), in: Circle())
      .contentShape(Circle())
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.1), value: isHovered)
  }

  private func backgroundColor(isPressed: Bool) -> Color {
    switch appearance {
    case .cancel:
      Color.white.opacity(isPressed ? 0.25 : (isHovered ? 0.2 : 0.14))
    case .finish:
      Color(white: isPressed ? 0.78 : (isHovered ? 0.9 : 0.96))
    }
  }
}

// Text actions on the charcoal capsules share the Cancel button's quiet fill.
struct StripTextButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.white.opacity(0.94))
      .padding(.horizontal, 11)
      .frame(height: 24)
      .background(Color.white.opacity(configuration.isPressed ? 0.25 : 0.14), in: Capsule())
      .contentShape(Capsule())
  }
}
