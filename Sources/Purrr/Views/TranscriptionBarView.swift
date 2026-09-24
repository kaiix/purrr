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

  var body: some View {
    Group {
      switch model.phase {
      case .recording:
        recordingControls
      case .recognizing, .processing, .delivering:
        workingStatus
      case .succeeded:
        resultStatus(
          symbol: "checkmark",
          symbolBackground: .green,
          title: successTitle,
          help: model.statusMessage
        )
      case .failed:
        resultStatus(
          symbol: "exclamationmark",
          symbolBackground: .red,
          title: "Couldn’t finish",
          help: model.statusMessage
        )
      case .idle:
        EmptyView()
      }
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

  private var workingStatus: some View {
    HStack(spacing: 8) {
      ProcessingIndicator(reduceMotion: reduceMotion)
      Text(primaryText)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(stripBackground)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilitySummary)
  }

  private func resultStatus(
    symbol: String,
    symbolBackground: Color,
    title: String,
    help: String
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(symbolBackground.opacity(0.95), in: Circle())
        .frame(width: 28, height: 28)
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.94))
        .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(stripBackground)
    .help(help)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilitySummary)
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
    2 + sample * 16
  }

  private func barOpacity(at index: Int) -> Double {
    let distanceFromLatest = samples.count - index - 1
    return max(0.42, 0.96 - Double(distanceFromLatest) * 0.035)
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
