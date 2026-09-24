import CPurrrSpeechBridge
import Foundation

enum SpeechEngineEvent {
  case connecting
  case ready
  case interim(String)
  case final(String)
  case failed(String)
  case cancelled
}

protocol SpeechEngine: AnyObject {
  var onEvent: ((UInt64, SpeechEngineEvent) -> Void)? { get set }

  func start(sessionID: UInt64) throws
  func send(_ pcm: Data)
  func finish()
  func cancel()
}

private let speechBridgeCallback:
  @convention(c) (
    UnsafeMutableRawPointer?,
    UInt64,
    Int32,
    UnsafePointer<CChar>?
  ) -> Void = { context, sessionID, kind, message in
    guard let context else { return }
    let engine = Unmanaged<DoubaoImeSpeechEngine>.fromOpaque(context).takeUnretainedValue()
    let value = message.map { String(cString: $0) } ?? ""
    engine.receive(sessionID: sessionID, kind: kind, message: value)
  }

final class DoubaoImeSpeechEngine: SpeechEngine {
  var onEvent: ((UInt64, SpeechEngineEvent) -> Void)?

  private var handle: OpaquePointer?

  init() {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent("Purrr", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: applicationSupport,
      withIntermediateDirectories: true
    )
    let credentialPath =
      applicationSupport
      .appendingPathComponent("doubaoime_credentials.json")
      .path
    let callbacks = PurrrAsrCallbacks(
      context: Unmanaged.passUnretained(self).toOpaque(),
      on_event: speechBridgeCallback
    )
    handle = credentialPath.withCString { pointer in
      purrr_asr_create(callbacks, pointer)
    }
  }

  deinit {
    if let handle {
      purrr_asr_destroy(handle)
    }
  }

  func start(sessionID: UInt64) throws {
    guard let handle, purrr_asr_start(handle, sessionID) == 0 else {
      throw SpeechEngineError.unavailable
    }
  }

  func send(_ pcm: Data) {
    guard let handle else { return }
    pcm.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }
      _ = purrr_asr_push_audio(handle, baseAddress, UInt32(bytes.count))
    }
  }

  func finish() {
    guard let handle else { return }
    _ = purrr_asr_finish(handle)
  }

  func cancel() {
    guard let handle else { return }
    _ = purrr_asr_cancel(handle)
  }

  fileprivate func receive(sessionID: UInt64, kind: Int32, message: String) {
    let event: SpeechEngineEvent
    switch kind {
    case 0: event = .connecting
    case 1: event = .ready
    case 2: event = .interim(message)
    case 3: event = .final(message)
    case 4: event = .failed(message)
    case 5: event = .cancelled
    default: return
    }
    DispatchQueue.main.async { [weak self] in
      self?.onEvent?(sessionID, event)
    }
  }
}

enum SpeechEngineError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "The Doubao IME speech engine could not be initialized."
  }
}
