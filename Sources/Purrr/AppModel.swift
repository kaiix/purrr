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

enum SettingsTab: Hashable {
  case general, llm, vocabulary
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var phase: SessionPhase = .idle
  @Published private(set) var activeMode: SessionMode?
  @Published private(set) var audioLevel: Double = 0
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var statusMessage: String = ""
  @Published private(set) var failureTitle = "Failed"
  @Published private(set) var connectionTestStatus: ConnectionTestStatus = .idle
  @Published private(set) var availableLLMModels: [String] = []
  @Published private(set) var modelListStatus: ModelListStatus = .idle
  @Published private(set) var shortcutWarning: String?
  @Published var settingsTab: SettingsTab = .general
  @Published var vocabularyEditRequest: UUID?

  let settings: AppSettings
  let history: HistoryStore
  let vocabulary = VocabularyStore()

  private let shortcuts = GlobalShortcutMonitor()
  private let audioRecorder = AudioRecorder()
  private let speechEngine: any SpeechEngine
  private let textProcessor: any TextProcessor
  private let delivery = TextDeliveryService()
  private let submittedTextObserver = SubmittedTextObserver()
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
  private var vocabularyReviewTasks: [UUID: Task<Void, Never>] = [:]
  private var reviewingCandidateIDs = Set<String>()

  private lazy var panelController = TranscriptionPanelController(model: self)
  private lazy var vocabularyNotices = VocabularyNoticeController(vocabulary: vocabulary)

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

    vocabularyNotices.onEdit = { [weak self] id in
      self?.editVocabularyWord(id: id)
    }
    $phase.sink { [weak vocabularyNotices] phase in
      vocabularyNotices?.setSuspended(phase != .idle)
    }.store(in: &cancellables)

    history.$entries
      .combineLatest(vocabulary.$collectsEdits)
      .sink { [weak vocabulary] entries, enabled in
        vocabulary?.refresh(from: entries, collectingEdits: enabled)
      }
      .store(in: &cancellables)

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
    let submittedTextObserver = self.submittedTextObserver
    shortcuts.onKeyDown = { [weak submittedTextObserver] event in
      submittedTextObserver?.handleKeyDown(event)
    }
    shortcuts.onPointerDown = { [weak submittedTextObserver] location in
      submittedTextObserver?.handlePointerDown(at: location)
    }
    submittedTextObserver.onUpdate = { [weak self] id, outcome in
      Task { @MainActor in
        guard let self else { return }
        self.history.applySubmissionOutcome(id: id, outcome: outcome)
        guard case .confirmed = outcome else { return }
        self.startVocabularyReview(
          self.vocabulary.unreviewedCandidates.filter { $0.historyID == id }, automaticallyAdd: true
        )
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
    for task in vocabularyReviewTasks.values { task.cancel() }
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

  func editVocabularyWord(id: UUID) {
    guard vocabulary.words.contains(where: { $0.id == id }) else { return }
    settingsTab = .vocabulary
    vocabularyEditRequest = id
    showSettings()
  }

  func reviewVocabularyEdits() {
    startVocabularyReview(vocabulary.unreviewedCandidates, automaticallyAdd: false)
  }

  private func startVocabularyReview(_ candidates: [VocabularyCandidate], automaticallyAdd: Bool) {
    guard settings.llmEnabled, settings.isLLMConfigured, vocabulary.collectsEdits else { return }
    let proposals = Array(
      candidates.filter { !reviewingCandidateIDs.contains($0.id) }
        .prefix(VocabularySemanticReview.maximumBatchSize))
    guard !proposals.isEmpty else { return }
    let configuration = llmConfiguration()
    let id = UUID()
    reviewingCandidateIDs.formUnion(proposals.map(\.id))
    vocabulary.beginReview()
    vocabularyReviewTasks[id] = Task { @MainActor [weak self] in
      guard let self else { return }
      var failure: String?
      defer {
        self.reviewingCandidateIDs.subtract(proposals.map(\.id))
        self.vocabularyReviewTasks[id] = nil
        self.vocabulary.finishReview(error: failure)
      }
      do {
        let decisions = try await self.textProcessor.reviewVocabulary(
          proposals, configuration: configuration)
        guard !Task.isCancelled, self.settings.llmEnabled, self.settings.isLLMConfigured,
          self.settings.baseURL == configuration.baseURL,
          self.settings.apiKey == configuration.apiKey, self.settings.model == configuration.model
        else { return }
        // Recheck deletion, expiry, retries, and the collection toggle after the network wait.
        self.vocabulary.refresh(from: self.history.entries)
        let added = try self.vocabulary.applyReview(
          decisions, proposals: proposals, automaticallyAdd: automaticallyAdd
        )
        self.vocabularyNotices.enqueue(added)
      } catch {
        if !Task.isCancelled {
          failure =
            "Check failed. Nothing was added."
        }
      }
    }
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
      rawTranscript: nil,
      processedText: nil,
      targetLanguage: activeTargetLanguage,
      status: .dismissed,
      failureMessage: "Cancelled"
    )
    resetSession()
    panelController.hide()
  }

  func retry(_ entry: HistoryEntry) {
    guard phase == .idle, !isStartingSession else { return }
    guard entry.expiresAt > Date() else {
      showTransientFailure("This recording has expired.", title: "Expired")
      return
    }
    let retryNeedsLanguageModel =
      entry.mode == .translate || entry.failureStage == .languageModel
    if retryNeedsLanguageModel && !settings.llmEnabled {
      showTransientFailure("Turn on the LLM to retry.", title: "LLM is off")
      return
    }
    if settings.llmEnabled && !settings.isLLMConfigured {
      showTransientFailure("Finish LLM setup first.", title: "Set up LLM")
      return
    }

    pendingRetryID = entry.id
    activeMode = entry.mode
    activeTargetLanguage = entry.targetLanguage
    history.markRetrying(id: entry.id)
    panelController.show()

    if entry.failureStage == .languageModel,
      let source = entry.rawTranscript,
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
      finishRetryFailure("The audio is no longer available.", stage: .speechRecognition)
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
      connectionTestStatus = .failed("Add a base URL, API key, and model first.")
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
      modelListStatus = .failed("Add a base URL and API key first.")
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
          modelListStatus = .failed("No models found.")
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
      showTransientFailure("Finish LLM setup first.", title: "Set up LLM")
      return
    }
    if mode == .translate && !settings.llmEnabled {
      showTransientFailure("Turn on the LLM to use Translate.", title: "LLM is off")
      return
    }
    let requestedDestination = delivery.captureDestination()
    guard await AudioRecorder.requestPermission() else {
      showTransientFailure("Allow microphone access in System Settings.", title: "Mic blocked")
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
    let configuration = llmConfiguration(includeVocabulary: true)
    var output = transcript
    var usedFallback = false
    var fallbackMessage: String?

    if mode == .translate || settings.llmEnabled {
      phase = .processing
      statusMessage =
        mode == .translate
        ? "Into \((activeTargetLanguage ?? settings.targetLanguage).title)"
        : (configuration.dictatePrompt.isEmpty ? "Checking spellings" : "Polishing text")
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
        rawTranscript: transcript,
        processedText: output,
        status: .succeeded,
        failureStage: usedFallback ? .languageModel : nil,
        failureMessage: fallbackMessage,
        usedRawFallback: usedFallback
      )
      showSuccess("Done")
      return
    }

    phase = .delivering
    statusMessage = "Returning to the original app"
    let preparedObservation = submittedTextObserver.prepare(
      destination: destination,
      processedText: output
    )
    let deliveryResult = delivery.deliver(output, to: destination)
    let historyID = UUID()
    let isObservingSubmission: Bool
    if case .pasted = deliveryResult, let preparedObservation {
      isObservingSubmission = submittedTextObserver.start(
        entryID: historyID,
        prepared: preparedObservation
      )
    } else {
      isObservingSubmission = false
    }
    history.add(
      id: historyID,
      mode: mode,
      recording: pendingRecording,
      rawTranscript: transcript,
      processedText: output,
      submissionState: isObservingSubmission ? .pending : .notObserved,
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
      finishRetryFailure("No speech detected.", stage: .speechRecognition, title: "No speech")
    } else if let mode = activeMode {
      history.add(
        mode: mode,
        recording: pendingRecording,
        rawTranscript: nil,
        processedText: nil,
        targetLanguage: activeTargetLanguage,
        status: .dismissed,
        failureStage: .speechRecognition,
        failureMessage: "No speech detected."
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
    failureTitle = Self.failureTitle(for: stage)
    if let mode = activeMode {
      history.add(
        mode: mode,
        recording: pendingRecording,
        rawTranscript: sourceText,
        processedText: nil,
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
    sourceText: String? = nil,
    title: String? = nil
  ) {
    failureTitle = title ?? Self.failureTitle(for: stage)
    if let retryID = pendingRetryID {
      history.update(
        id: retryID,
        rawTranscript: sourceText,
        processedText: nil,
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

  private static func failureTitle(for stage: FailureStage) -> String {
    stage == .languageModel ? "LLM failed" : "Failed"
  }

  private func showTransientFailure(_ message: String, title: String = "Failed") {
    failureTitle = title
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

  private func llmConfiguration(includeVocabulary: Bool = false) -> LLMConfiguration {
    LLMConfiguration(
      baseURL: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
      apiKey: settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
      model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
      dictatePrompt: settings.dictatePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
      translatePrompt: settings.translatePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
      vocabulary: includeVocabulary && settings.llmEnabled ? vocabulary.processingTerms : []
    )
  }
}
