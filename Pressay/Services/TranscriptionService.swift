import Foundation

struct TranscriptionResult: Equatable {
    let text: String
    let averageLogProbability: Double?

    var isLowConfidence: Bool {
        guard let averageLogProbability else { return false }
        return averageLogProbability < Constants.lowConfidenceLogProbability
    }
}

enum TranscriptionResponseValidator {
    static func validated(
        _ text: String,
        vocabulary: String,
        prompt: String? = nil
    ) throws -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            throw TranscriptionService.TranscriptionError.noSpeech
        }

        let normalizedText = normalized(cleanText)
        let rejectedEchoes = [vocabulary, prompt ?? ""]
            .map(normalized)
            .filter { !$0.isEmpty }
        if rejectedEchoes.contains(normalizedText) {
            throw TranscriptionService.TranscriptionError.noSpeech
        }
        return cleanText
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

final class TranscriptionService: SpeechTranscribing {
    static let shared = TranscriptionService()

    private let session: URLSession

    var identifier: String { "openai" }
    var isReady: Bool { KeychainHelper.shared.hasAPIKey }

    init(session: URLSession? = nil) {
        // Keep the cloud path identical to the deliberately small reference
        // implementation: one in-memory request on the shared session. The
        // previous upload task could spend many seconds waiting to stream a
        // temporary multipart file even for a tiny dictation.
        self.session = session ?? .shared
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private struct ErrorResponse: Decodable {
        let error: ErrorDetail
    }

    private struct ErrorDetail: Decodable {
        let message: String
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard let apiKey = KeychainHelper.shared.getAPIKey() else {
            throw TranscriptionError.noAPIKey
        }

        let preferences = UserDefaults.standard
        let language = preferences.string(forKey: Constants.transcriptionLanguageKey)
            ?? Constants.defaultTranscriptionLanguage
        let vocabulary = selectedVocabulary(preferences: preferences)
        let prompt = vocabulary.isEmpty
            ? nil
            : transcriptionPrompt(vocabulary: vocabulary, language: language)
        let model = preferences.string(forKey: Constants.transcriptionModelKey)
            ?? Constants.defaultTranscriptionModel
        let body = try makeBody(
            audioURL: audioURL,
            model: model,
            language: language,
            prompt: prompt
        )

        var request = try makeRequest(
            apiKey: apiKey,
            boundary: body.boundary
        )
        request.httpBody = body.data
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let decoded = try decodeResponse(data: data, response: response)
        let cleanText = try TranscriptionResponseValidator.validated(
            decoded.text,
            vocabulary: vocabulary,
            prompt: prompt
        )
        return TranscriptionResult(text: cleanText, averageLogProbability: nil)
    }

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard apiKey.hasPrefix("sk-") else { return false }

        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func makeBody(
        audioURL: URL,
        model: String,
        language: String,
        prompt: String?
    ) throws -> (data: Data, boundary: String) {
        let boundary = UUID().uuidString
        let audioData = try Data(contentsOf: audioURL, options: .mappedIfSafe)
        var data = Data()
        data.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: "audio.\(audioURL.pathExtension)",
            mimeType: Self.audioMIMEType(for: audioURL),
            contents: audioData
        )
        data.appendMultipartField(boundary: boundary, name: "model", value: model)
        data.appendMultipartField(
            boundary: boundary,
            name: "response_format",
            value: "json"
        )
        if !language.isEmpty {
            data.appendMultipartField(
                boundary: boundary,
                name: "language",
                value: language
            )
        }
        if let prompt {
            data.appendMultipartField(
                boundary: boundary,
                name: "prompt",
                value: prompt
            )
        }
        data.appendUTF8("--\(boundary)--\r\n")
        return (data, boundary)
    }

    private static func audioMIMEType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": "audio/wav"
        case "flac": "audio/flac"
        default: "audio/mp4"
        }
    }

    private func makeRequest(apiKey: String, boundary: String) throws -> URLRequest {
        guard let url = URL(string: Constants.openAITranscriptionURL) else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func decodeResponse(data: Data, response: URLResponse) throws -> TranscriptionResponse {
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw TranscriptionError.apiError(error.error.message)
            }
            throw TranscriptionError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    }

    private func selectedVocabulary(preferences: UserDefaults) -> String {
        let explicitProfile = preferences.string(forKey: Constants.vocabularyProfileKey)
        let existingCustomVocabulary = preferences.string(forKey: Constants.technicalVocabularyKey)
        let profile = explicitProfile ?? (existingCustomVocabulary == nil ? "development" : "custom")
        switch profile {
        case "general":
            return Constants.generalVocabulary
        case "custom":
            return (existingCustomVocabulary ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return Constants.defaultTechnicalVocabulary
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func transcriptionPrompt(vocabulary: String, language: String) -> String {
        if language == "en" {
            return "Natural dictation with accurate punctuation. Technical vocabulary may include: \(vocabulary)."
        }
        return "Dictée naturelle avec une ponctuation fidèle. Le vocabulaire technique peut inclure : \(vocabulary)."
    }

    enum TranscriptionError: LocalizedError, Equatable {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case noSpeech
        case apiError(String)
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Clé API non configurée"
            case .invalidURL:
                return "URL invalide"
            case .invalidResponse:
                return "Réponse invalide du serveur"
            case .noSpeech:
                return "Aucune parole détectée — rien n’a été collé"
            case .apiError(let message):
                return "Erreur API : \(message)"
            case .httpError(let code):
                return "Erreur HTTP : \(code)"
            }
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendMultipartField(
        boundary: String,
        name: String,
        value: String
    ) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendUTF8("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        boundary: String,
        name: String,
        filename: String,
        mimeType: String,
        contents: Data
    ) {
        appendUTF8("--\(boundary)\r\n")
        appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        append(contents)
        appendUTF8("\r\n")
    }
}
