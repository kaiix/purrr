import Foundation

struct LLMConfiguration {
  let baseURL: String
  let apiKey: String
  let model: String
  let dictatePrompt: String
  let translatePrompt: String
  var vocabulary: [String] = []
}

protocol TextProcessor {
  func dictate(_ transcript: String, configuration: LLMConfiguration) async throws -> String
  func translate(
    _ transcript: String,
    targetLanguage: TranslationLanguage,
    configuration: LLMConfiguration
  ) async throws -> String
  func validate(configuration: LLMConfiguration) async throws
  func listModels(baseURL: String, apiKey: String) async throws -> [String]
  func reviewVocabulary(
    _ candidates: [VocabularyCandidate], configuration: LLMConfiguration
  ) async throws -> [VocabularyReviewDecision]
}

enum TextProcessorError: LocalizedError {
  case invalidConfiguration
  case invalidResponse
  case requestFailed(String)
  case emptyOutput

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      "The LLM settings are incomplete."
    case .invalidResponse:
      "The LLM returned an unreadable response."
    case .requestFailed(let message):
      message
    case .emptyOutput:
      "The LLM returned empty text."
    }
  }
}

final class OpenAICompatibleTextProcessor: TextProcessor {
  private struct Message: Codable {
    let role: String
    let content: String
  }

  private struct SourceTextEnvelope: Encodable {
    let sourceText: String

    enum CodingKeys: String, CodingKey {
      case sourceText = "source_text"
    }
  }

  private struct RequestBody: Codable {
    let model: String
    let messages: [Message]
    let temperature: Double?
    let stream: Bool
  }

  private struct ResponseBody: Decodable {
    struct Choice: Decodable {
      struct ResponseMessage: Decodable {
        let content: String?
      }

      let message: ResponseMessage
    }

    let choices: [Choice]
  }

  private struct ModelListBody: Decodable {
    struct Model: Decodable {
      let id: String
    }

    let data: [Model]
  }

  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func dictate(_ transcript: String, configuration: LLMConfiguration) async throws -> String {
    let prompt = try TextProcessingPrompt.make(
      mode: .dictate, transcript: transcript, configuration: configuration
    )
    if prompt.isPassthrough { return transcript }
    return try await completeRequest(
      systemInstructions: prompt.systemInstructions, userPayload: prompt.userPayload,
      configuration: configuration)
  }

  func translate(
    _ transcript: String,
    targetLanguage: TranslationLanguage,
    configuration: LLMConfiguration
  ) async throws -> String {
    let prompt = try TextProcessingPrompt.make(
      mode: .translate, transcript: transcript, configuration: configuration,
      targetLanguage: targetLanguage)
    return try await completeRequest(
      systemInstructions: prompt.systemInstructions, userPayload: prompt.userPayload,
      configuration: configuration)
  }

  func validate(configuration: LLMConfiguration) async throws {
    _ = try await complete(
      instructions: "Return only the word OK.",
      input: "Connection test",
      configuration: configuration
    )
  }

  func reviewVocabulary(
    _ candidates: [VocabularyCandidate], configuration: LLMConfiguration
  ) async throws -> [VocabularyReviewDecision] {
    guard !candidates.isEmpty else { return [] }
    let output = try await completeRequest(
      systemInstructions: VocabularySemanticReview.instructions,
      userPayload: VocabularySemanticReview.payload(for: candidates), configuration: configuration
    )
    return try VocabularySemanticReview.decode(output, candidates: candidates)
  }

  func listModels(baseURL: String, apiKey: String) async throws -> [String] {
    guard let endpoint = modelsURL(from: baseURL),
      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw TextProcessorError.invalidConfiguration
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw TextProcessorError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let serverMessage = Self.serverErrorMessage(from: data)
      throw TextProcessorError.requestFailed(
        serverMessage ?? "Loading models failed with HTTP \(http.statusCode)."
      )
    }
    guard let decoded = try? JSONDecoder().decode(ModelListBody.self, from: data) else {
      throw TextProcessorError.invalidResponse
    }

    let models = Set(
      decoded.data
        .map(\.id)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
    return models.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private func complete(
    instructions: String,
    input: String,
    configuration: LLMConfiguration
  ) async throws -> String {
    let sourceData = try JSONEncoder().encode(SourceTextEnvelope(sourceText: input))
    let systemInstructions = [instructions, TextProcessingPrompt.sourceTextContract]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n\n")
    return try await completeRequest(
      systemInstructions: systemInstructions,
      userPayload: String(decoding: sourceData, as: UTF8.self), configuration: configuration
    )
  }

  private func completeRequest(
    systemInstructions: String, userPayload: String, configuration: LLMConfiguration
  ) async throws -> String {
    guard let endpoint = endpointURL(from: configuration.baseURL),
      !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw TextProcessorError.invalidConfiguration
    }

    do {
      return try await send(
        endpoint: endpoint,
        systemInstructions: systemInstructions,
        userPayload: userPayload,
        configuration: configuration,
        temperature: 0
      )
    } catch let TextProcessorError.requestFailed(message)
      where message.localizedCaseInsensitiveContains("temperature")
    {
      return try await send(
        endpoint: endpoint,
        systemInstructions: systemInstructions,
        userPayload: userPayload,
        configuration: configuration,
        temperature: nil
      )
    }
  }

  private func send(
    endpoint: URL,
    systemInstructions: String,
    userPayload: String,
    configuration: LLMConfiguration,
    temperature: Double?
  ) async throws -> String {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(
      RequestBody(
        model: configuration.model,
        messages: [
          Message(role: "system", content: systemInstructions),
          Message(role: "user", content: userPayload),
        ],
        temperature: temperature,
        stream: false
      )
    )

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw TextProcessorError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let serverMessage = Self.serverErrorMessage(from: data)
      throw TextProcessorError.requestFailed(
        serverMessage ?? "The LLM request failed with HTTP \(http.statusCode)."
      )
    }

    guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data),
      let content = decoded.choices.first?.message.content
    else {
      throw TextProcessorError.invalidResponse
    }
    let cleaned = Self.cleanOutput(content)
    guard !cleaned.isEmpty else {
      throw TextProcessorError.emptyOutput
    }
    return cleaned
  }

  private func endpointURL(from baseURL: String) -> URL? {
    var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    if value.hasSuffix("/chat/completions") {
      return URL(string: value)
    }
    return URL(string: value + "/chat/completions")
  }

  private func modelsURL(from baseURL: String) -> URL? {
    var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    if value.hasSuffix("/chat/completions") {
      value.removeLast("/chat/completions".count)
    } else if value.hasSuffix("/models") {
      return URL(string: value)
    }
    return URL(string: value + "/models")
  }

  private static func serverErrorMessage(from data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let error = object["error"] as? [String: Any],
      let message = error["message"] as? String
    else {
      return nil
    }
    return String(message.prefix(300))
  }

  private static func cleanOutput(_ output: String) -> String {
    var value = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("```") && value.hasSuffix("```") {
      value.removeFirst(3)
      value.removeLast(3)
      if let newline = value.firstIndex(of: "\n") {
        let prefix = value[..<newline]
        if !prefix.contains(" ") && prefix.count < 20 {
          value = String(value[value.index(after: newline)...])
        }
      }
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
