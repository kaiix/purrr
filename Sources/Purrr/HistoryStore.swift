import AppKit
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry] = []

  private let rootURL: URL
  private let indexURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileManager: FileManager = .default) {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    rootURL =
      applicationSupport
      .appendingPathComponent("Purrr", isDirectory: true)
      .appendingPathComponent("History", isDirectory: true)
    indexURL = rootURL.appendingPathComponent("history.json")
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    load()
    cleanupExpired()
  }

  @discardableResult
  func add(
    mode: SessionMode,
    recording: AudioRecording?,
    sourceText: String?,
    deliveredText: String?,
    targetLanguage: TranslationLanguage?,
    status: HistoryStatus,
    failureStage: FailureStage? = nil,
    failureMessage: String? = nil,
    usedRawFallback: Bool = false
  ) -> UUID {
    let id = UUID()
    let audioFileName: String?
    if let recording, !recording.pcmData.isEmpty {
      let name = "\(id.uuidString).wav"
      let url = rootURL.appendingPathComponent(name)
      try? WAVEncoder.data(from: recording.pcmData).write(to: url, options: .atomic)
      audioFileName = name
    } else {
      audioFileName = nil
    }

    let entry = HistoryEntry(
      id: id,
      completedAt: Date(),
      mode: mode,
      audioFileName: audioFileName,
      sourceText: sourceText,
      deliveredText: deliveredText,
      targetLanguage: targetLanguage,
      status: status,
      failureStage: failureStage,
      failureMessage: failureMessage,
      usedRawFallback: usedRawFallback
    )
    entries.insert(entry, at: 0)
    save()
    return id
  }

  func update(
    id: UUID,
    sourceText: String?,
    deliveredText: String?,
    status: HistoryStatus,
    failureStage: FailureStage? = nil,
    failureMessage: String? = nil,
    usedRawFallback: Bool = false
  ) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[index].sourceText = sourceText ?? entries[index].sourceText
    entries[index].deliveredText = deliveredText
    entries[index].status = status
    entries[index].failureStage = failureStage
    entries[index].failureMessage = failureMessage
    entries[index].usedRawFallback = usedRawFallback
    save()
  }

  func markRetrying(id: UUID) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[index].status = .retrying
    entries[index].failureMessage = nil
    save()
  }

  func entry(id: UUID) -> HistoryEntry? {
    entries.first(where: { $0.id == id })
  }

  func pcmAudio(for entry: HistoryEntry) -> Data? {
    guard let name = entry.audioFileName,
      let data = try? Data(contentsOf: rootURL.appendingPathComponent(name)),
      data.count > WAVEncoder.headerSize
    else {
      return nil
    }
    return data.subdata(in: WAVEncoder.headerSize..<data.count)
  }

  func copy(_ entry: HistoryEntry) {
    guard let text = entry.preferredCopyText else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func delete(_ entry: HistoryEntry) {
    if let name = entry.audioFileName {
      try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(name))
    }
    entries.removeAll(where: { $0.id == entry.id })
    save()
  }

  func deleteAll() {
    for entry in entries {
      if let name = entry.audioFileName {
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(name))
      }
    }
    entries.removeAll()
    save()
  }

  func cleanupExpired(now: Date = Date()) {
    let expired = entries.filter { $0.expiresAt <= now }
    guard !expired.isEmpty else { return }
    for entry in expired {
      if let name = entry.audioFileName {
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(name))
      }
    }
    let expiredIDs = Set(expired.map(\.id))
    entries.removeAll(where: { expiredIDs.contains($0.id) })
    save()
  }

  private func load() {
    guard let data = try? Data(contentsOf: indexURL),
      let decoded = try? decoder.decode([HistoryEntry].self, from: data)
    else {
      return
    }
    entries =
      decoded
      .map { entry in
        guard entry.status == .retrying else { return entry }
        var recovered = entry
        recovered.status = .failed
        recovered.failureMessage = "The retry was interrupted."
        return recovered
      }
      .sorted(by: { $0.completedAt > $1.completedAt })
    save()
  }

  private func save() {
    guard let data = try? encoder.encode(entries) else { return }
    try? data.write(to: indexURL, options: .atomic)
  }
}

enum WAVEncoder {
  static let headerSize = 44

  static func data(from pcm: Data) -> Data {
    var result = Data()
    result.append(contentsOf: Array("RIFF".utf8))
    result.appendLittleEndian(UInt32(36 + pcm.count))
    result.append(contentsOf: Array("WAVE".utf8))
    result.append(contentsOf: Array("fmt ".utf8))
    result.appendLittleEndian(UInt32(16))
    result.appendLittleEndian(UInt16(1))
    result.appendLittleEndian(UInt16(1))
    result.appendLittleEndian(UInt32(16_000))
    result.appendLittleEndian(UInt32(32_000))
    result.appendLittleEndian(UInt16(2))
    result.appendLittleEndian(UInt16(16))
    result.append(contentsOf: Array("data".utf8))
    result.appendLittleEndian(UInt32(pcm.count))
    result.append(pcm)
    return result
  }
}

extension Data {
  fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { bytes in
      append(contentsOf: bytes)
    }
  }
}
