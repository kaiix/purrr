import AVFoundation
import AppKit
import Combine
import Foundation

enum ConnectionTestStatus: Equatable {
  case idle
  case testing
  case succeeded
  case failed(String)
}

enum ModelListStatus: Equatable {
  case idle
  case loading
  case loaded
  case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var phase: SessionPhase = .idle
  @Published private(set) var activeMode: SessionMode?
  @Published private(set) var audioLevel: Double = 0
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var statusMessage: String = ""
  @Published private(set) var connectionTestStatus: ConnectionTestStatus = .idle
  @Published private(set) var availableLLMModels: [String] = []
  @Published private(set) var modelListStatus: ModelListStatus = .idle
  @Published private(set) var shortcutWarning: String?

  let settings: AppSettings
  let history: HistoryStore

  private let shortcuts = GlobalShortcutMonitor()
  private let audioRecorder = AudioRecorder()
  private let speechEngine: any SpeechEngine
  private let textProcessor: any TextProcessor
  private let delivery = TextDeliveryService()
  private let windows = AppWindowCoordinator()
  private var destination: CapturedDestination?
  private var activeTargetLanguage: TranslationLanguage?
  private var isStartingSession = false
  private var currentSessionID: UInt64 = 0
  private var pendingRecording: AudioRecording?
  private var pendingRetryID: UUID?
  private var sessionStartedAt: Date?
  private var clockTask: Task<Void, Never>?
  private var escapeMonitor: Any?
  private var cancellables: Set<AnyCancellable> = []
  private var cleanupTimer: Timer?

  private lazy var panelController = TranscriptionPanelController(model: self)

  init(
    settings: AppSettings,
    history: HistoryStore,
    speechEngine: any SpeechEngine = DoubaoImeSpeechEngine(),
    textProcessor: any TextProcessor = OpenAICompatibleTextProcessor()
  ) {
    self.settings = settings
    self.history = history
    self.speechEngine = speechEngine
    self.textProcessor = textProcessor

    shortcuts.onTrigger = { [weak self] mode in
      Task { @MainActor in
        self?.toggle(mode)
      }
    }
    shortcuts.onRegistrationChange = { [weak self] message in
      Task { @MainActor in
        self?.shortcutWarning = message
      }
    }
    speechEngine.onEvent = { [weak self] sessionID, event in
      Task { @MainActor in
        self?.handleSpeechEvent(sessionID: sessionID, event: event)
      }
    }
    audioRecorder.onPCMChunk = { [weak speechEngine] chunk in
      speechEngine?.send(chunk)
    }
    audioRecorder.onLevel = { [weak self] level in
      DispatchQueue.main.async {
        self?.audioLevel = level
      }
    }

    settings.$dictateShortcut
      .combineLatest(settings.$translateShortcut)
      .sink { [weak self] dictate, translate in
        guard let self else { return }
        self.shortcutWarning = nil
        self.shortcuts.register(dictate: dictate, translate: translate)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: .purrrShowSettings)
      .sink { [weak self] _ in
        Task { @MainActor in
          self?.showSettings()
        }
      }
      .store(in: &cancellables)

    cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60 * 30, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        self?.history.cleanupExpired()
      }
    }
  }

  deinit {
    clockTask?.cancel()
    cleanupTimer?.invalidate()
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
    }
  }

  var remainingTime: TimeInterval {
    max(0, 9 * 60 - elapsed)
  }

  var isInFinalMinute: Bool {
    elapsed >= 8 * 60
  }

  func showSettings() {
    windows.showSettings(settings: settings, model: self)
  }

  func showHistory() {
    windows.showHistory(history: history, model: self)
  }

  func toggle(_ mode: SessionMode) {
    if phase == .recording {
      guard activeMode == mode else { return }
      stopRecording()
      return
    }
    guard phase == .idle, !isStartingSession else { return }
    isStartingSession = true
    Task {
      defer { isStartingSession = false }
      await begin(mode)
    }
  }

  func cancelRecording() {
    guard phase == .recording, let mode = activeMode else { return }
    let recording = audioRecorder.stop()
    speechEngine.cancel()
    stopClock()
    history.add(
      mode: mode,
      recording: recording,
      sourceText: nil,
      deliveredText: nil,
      targetLanguage: activeTargetLanguage,
      status: .dismissed,
      failureMessage: "The transcription was dismissed."
    )
    resetSession()
    panelController.hide()
  }

  func retry(_ entry: HistoryEntry) {
    guard phase == .idle, !isStartingSession else { return }
    guard entry.expiresAt > Date() else {
      showTransientFailure("This recording has expired.")
      return
    }
    let retryNeedsLanguageModel =
      entry.mode == .translate || entry.failureStage == .languageModel
    if retryNeedsLanguageModel && (!settings.llmEnabled || !settings.isLLMConfigured) {
      showTransientFailure("Enable and configure the LLM before retrying.")
      return
    }
    if settings.llmEnabled && !settings.isLLMConfigured {
      showTransientFailure("Finish the LLM setup before retrying.")
      return
    }

    pendingRetryID = entry.id
    activeMode = entry.mode
    activeTargetLanguage = entry.targetLanguage
    history.markRetrying(id: entry.id)
    panelController.show()

    if entry.failureStage == .languageModel,
      let source = entry.sourceText,
      !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      phase = .processing
      statusMessage = "Processing again"
      Task {
        await processTranscript(source)
      }
      return
    }

    guard let pcm = history.pcmAudio(for: entry) else {
      finishRetryFailure("The retained audio is unavailable.", stage: .speechRecognition)
      return
    }

    currentSessionID &+= 1
    phase = .recognizing
    statusMessage = "Using retained audio"
    do {
      try speechEngine.start(sessionID: currentSessionID)
      let chunkSize = 6_400
      var offset = 0
      while offset < pcm.count {
        let end = min(offset + chunkSize, pcm.count)
        speechEngine.send(pcm.subdata(in: offset..<end))
        offset = end
      }
      speechEngine.finish()
    } catch {
      finishRetryFailure(error.localizedDescription, stage: .speechRecognition)
    }
  }

  func testLLMConnection() {
    guard settings.isLLMConfigured else {
      connectionTestStatus = .failed("Complete Base URL, API key, and model first.")
      return
    }
    connectionTestStatus = .testing
    let configuration = llmConfiguration()
    Task {
      do {
        try await textProcessor.validate(configuration: configuration)
        connectionTestStatus = .succeeded
      } catch {
        connectionTestStatus = .failed(error.localizedDescription)
      }
    }
  }

  func refreshLLMModels() {
    guard settings.hasLLMCredentials else {
      modelListStatus = .failed("Enter a valid Base URL and API key first.")
      return
    }

    modelListStatus = .loading
    let baseURL = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    Task {
      do {
        let models = try await textProcessor.listModels(baseURL: baseURL, apiKey: apiKey)
        guard !models.isEmpty else {
          availableLLMModels = []
          modelListStatus = .failed("The endpoint returned no models.")
          return
        }
        availableLLMModels = models
        if !models.contains(settings.model) {
          settings.model = models[0]
        }
        modelListStatus = .loaded
      } catch {
        availableLLMModels = []
        modelListStatus = .failed(error.localizedDescription)
      }
    }
  }

  func invalidateLLMModels() {
    availableLLMModels = []
    modelListStatus = .idle
    connectionTestStatus = .idle
    settings.model = ""
  }

  func requestAccessibilityPermission() {
    TextDeliveryService.requestAccessibilityPermission()
  }

  func refreshGlobalShortcuts() {
    shortcuts.register(
      dictate: settings.dictateShortcut,
      translate: settings.translateShortcut
    )
  }

  private func begin(_ mode: SessionMode) async {
    if settings.llmEnabled && !settings.isLLMConfigured {
      showTransientFailure("Finish the LLM setup before recording.")
      return
    }
    if mode == .translate && !settings.llmEnabled {
      showTransientFailure("Enable the LLM in Settings to use Translate.")
      return
    }
    let requestedDestination = delivery.captureDestination()
    guard await AudioRecorder.requestPermission() else {
      showTransientFailure("Allow microphone access in System Settings to record speech.")
      return
    }

    currentSessionID &+= 1
    activeMode = mode
    activeTargetLanguage = mode == .translate ? settings.targetLanguage : nil
    pendingRetryID = nil
    pendingRecording = nil
    destination = requestedDestination
    elapsed = 0
    audioLevel = 0
    statusMessage = mode.title

    do {
      try speechEngine.start(sessionID: currentSessionID)
      try audioRecorder.start()
    } catch {
      speechEngine.cancel()
      resetSession()
      showTransientFailure(error.localizedDescription)
      return
    }

    phase = .recording
    sessionStartedAt = Date()
    startClock()
    installEscapeMonitor()
    panelController.show()
  }

  private func stopRecording() {
    guard phase == .recording else { return }
    pendingRecording = audioRecorder.stop()
    stopClock()
    audioLevel = 0
    phase = .recognizing
    statusMessage = "Waiting for final text"
    speechEngine.finish()
  }

  private func handleSpeechEvent(sessionID: UInt64, event: SpeechEngineEvent) {
    guard sessionID == currentSessionID else { return }
    switch event {
    case .connecting, .ready, .interim:
      break
    case .final(let text):
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else {
        finishEmptySession()
        return
      }
      Task {
        await processTranscript(value)
      }
    case .failed(let message):
      if phase == .recording {
        pendingRecording = audioRecorder.stop()
        stopClock()
      }
      finishFailure(message, stage: .speechRecognition)
    case .cancelled:
      break
    }
  }

  private func processTranscript(_ transcript: String) async {
    guard let mode = activeMode else { return }
    let configuration = llmConfiguration()
    var output = transcript
    var usedFallback = false
    var fallbackMessage: String?

    if mode == .translate || settings.llmEnabled {
      phase = .processing
      statusMessage =
        mode == .translate
        ? "Into \((activeTargetLanguage ?? settings.targetLanguage).title)"
        : "Removing filler and repetitions"
      do {
        switch mode {
        case .dictate:
          output = try await textProcessor.dictate(
            transcript,
            configuration: configuration
          )
        case .translate:
          output = try await textProcessor.translate(
            transcript,
            targetLanguage: activeTargetLanguage ?? settings.targetLanguage,
            configuration: configuration
          )
        }
      } catch {
        if mode == .translate {
          finishFailure(
            error.localizedDescription,
            stage: .languageModel,
            sourceText: transcript
          )
          return
        }
        output = transcript
        usedFallback = true
        fallbackMessage = error.localizedDescription
      }
    }

    if let retryID = pendingRetryID {
      history.update(
        id: retryID,
        sourceText: transcript,
        deliveredText: output,
        status: .succeeded,
        failureStage: usedFallback ? .languageModel : nil,
        failureMessage: fallbackMessage,
        usedRawFallback: usedFallback
      )
      showSuccess("Retry complete")
      return
    }

    phase = .delivering
    statusMessage = "Returning to the original app"
    let deliveryResult = delivery.deliver(output, to: destination)
    history.add(
      mode: mode,
      recording: pendingRecording,
      sourceText: transcript,
      deliveredText: output,
      targetLanguage: activeTargetLanguage,
      status: .succeeded,
      failureStage: usedFallback ? .languageModel : nil,
      failureMessage: fallbackMessage,
      usedRawFallback: usedFallback
    )
    showSuccess(deliveryResult.message)
  }

  private func finishEmptySession() {
    if pendingRetryID != nil {
      finishRetryFailure("No speech was detected.", stage: .speechRecognition)
    } else if let mode = activeMode {
      history.add(
        mode: mode,
        recording: pendingRecording,
        sourceText: nil,
        deliveredText: nil,
        targetLanguage: activeTargetLanguage,
        status: .dismissed,
        failureStage: .speechRecognition,
        failureMessage: "No speech was detected."
      )
      resetSession()
      panelController.hide()
    }
  }

  private func finishFailure(
    _ message: String,
    stage: FailureStage,
    sourceText: String? = nil
  ) {
    if pendingRetryID != nil {
      finishRetryFailure(message, stage: stage, sourceText: sourceText)
      return
    }
    if let mode = activeMode {
      history.add(
        mode: mode,
        recording: pendingRecording,
        sourceText: sourceText,
        deliveredText: nil,
        targetLanguage: activeTargetLanguage,
        status: .failed,
        failureStage: stage,
        failureMessage: message
      )
    }
    phase = .failed(message)
    statusMessage = message
    scheduleReset(after: 2.5)
  }

  private func finishRetryFailure(
    _ message: String,
    stage: FailureStage,
    sourceText: String? = nil
  ) {
    if let retryID = pendingRetryID {
      history.update(
        id: retryID,
        sourceText: sourceText,
        deliveredText: nil,
        status: .failed,
        failureStage: stage,
        failureMessage: message
      )
    }
    phase = .failed(message)
    statusMessage = message
    scheduleReset(after: 2.5)
  }

  private func showSuccess(_ message: String) {
    phase = .succeeded
    statusMessage = message
    scheduleReset(after: 1)
  }

  private func showTransientFailure(_ message: String) {
    phase = .failed(message)
    statusMessage = message
    panelController.show()
    scheduleReset(after: 2.5)
  }

  private func scheduleReset(after delay: TimeInterval) {
    let scheduledSessionID = currentSessionID
    Task {
      try? await Task.sleep(for: .seconds(delay))
      guard currentSessionID == scheduledSessionID, phase != .recording else { return }
      resetSession()
      panelController.hide()
    }
  }

  private func resetSession() {
    stopClock()
    phase = .idle
    activeMode = nil
    activeTargetLanguage = nil
    pendingRecording = nil
    pendingRetryID = nil
    destination = nil
    audioLevel = 0
    elapsed = 0
    statusMessage = ""
  }

  private func startClock() {
    clockTask?.cancel()
    clockTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        guard let self, let startedAt = self.sessionStartedAt else { return }
        self.elapsed = Date().timeIntervalSince(startedAt)
        if self.elapsed >= 9 * 60 {
          self.stopRecording()
          return
        }
      }
    }
  }

  private func stopClock() {
    clockTask?.cancel()
    clockTask = nil
    sessionStartedAt = nil
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
      self.escapeMonitor = nil
    }
  }

  private func installEscapeMonitor() {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
    }
    escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return }
      Task { @MainActor in
        self?.cancelRecording()
      }
    }
  }

  private func llmConfiguration() -> LLMConfiguration {
    LLMConfiguration(
      baseURL: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
      apiKey: settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
      model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
      dictatePrompt: settings.dictatePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
      translatePrompt: settings.translatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}
