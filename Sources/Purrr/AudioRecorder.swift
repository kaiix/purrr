import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
  case microphoneDenied
  case unavailable
  case conversionFailed

  var errorDescription: String? {
    switch self {
    case .microphoneDenied:
      "Microphone access is required to record speech."
    case .unavailable:
      "The current microphone is unavailable."
    case .conversionFailed:
      "Purrr could not convert microphone audio to the speech format."
    }
  }
}

final class AudioRecorder {
  private let engine = AVAudioEngine()
  private let recordingQueue = DispatchQueue(label: "io.github.kaiix.purrr.audio-recording")
  private var pcmData = Data()
  private var startedAt: Date?
  private var converter: AVAudioConverter?
  private var targetFormat: AVAudioFormat?

  var onPCMChunk: ((Data) -> Void)?
  var onLevel: ((Double) -> Void)?

  static func requestPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      true
    case .notDetermined:
      await AVCaptureDevice.requestAccess(for: .audio)
    default:
      false
    }
  }

  func start() throws {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      throw AudioRecorderError.microphoneDenied
    }

    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0,
      inputFormat.channelCount > 0,
      let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
      ),
      let converter = AVAudioConverter(from: inputFormat, to: target)
    else {
      throw AudioRecorderError.unavailable
    }

    self.converter = converter
    targetFormat = target
    pcmData.removeAll(keepingCapacity: true)
    startedAt = Date()

    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
      self?.consume(buffer)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw AudioRecorderError.unavailable
    }
  }

  func stop() -> AudioRecording {
    if engine.isRunning {
      engine.stop()
    }
    engine.inputNode.removeTap(onBus: 0)
    let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    startedAt = nil
    let data = recordingQueue.sync { pcmData }
    converter = nil
    targetFormat = nil
    return AudioRecording(pcmData: data, duration: duration)
  }

  private func consume(_ inputBuffer: AVAudioPCMBuffer) {
    guard let converter, let targetFormat else { return }
    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(inputBuffer.frameLength) * ratio).rounded(.up) + 8)
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
    else {
      return
    }

    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
      if supplied {
        inputStatus.pointee = .noDataNow
        return nil
      }
      supplied = true
      inputStatus.pointee = .haveData
      return inputBuffer
    }
    guard status != .error,
      conversionError == nil,
      outputBuffer.frameLength > 0,
      let pointer = outputBuffer.int16ChannelData?[0]
    else {
      return
    }

    let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
    let chunk = Data(bytes: pointer, count: byteCount)
    let level = Self.level(from: inputBuffer)
    recordingQueue.async { [weak self] in
      guard let self else { return }
      self.pcmData.append(chunk)
      self.onPCMChunk?(chunk)
      self.onLevel?(level)
    }
  }

  private static func level(from buffer: AVAudioPCMBuffer) -> Double {
    guard let channels = buffer.floatChannelData,
      buffer.frameLength > 0
    else {
      return 0
    }
    let samples = channels[0]
    let count = Int(buffer.frameLength)
    let stride = max(1, count / 128)
    var squareSum: Float = 0
    var sampleCount = 0
    for index in Swift.stride(from: 0, to: count, by: stride) {
      let value = samples[index]
      squareSum += value * value
      sampleCount += 1
    }
    let rms = sqrt(squareSum / Float(max(sampleCount, 1)))
    return min(1, max(0, Double(rms) * 5))
  }
}
