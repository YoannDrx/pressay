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
    private static let knownHallucinatedEndings = [
        "faites ce que vous voulez"
    ]
    private static let wordExpression = try! NSRegularExpression(
        pattern: "[\\p{L}\\p{N}]+"
    )

    static func validated(
        _ text: String,
        vocabulary: String,
        prompt: String? = nil
    ) throws -> String {
        let cleanText = removeKnownHallucinatedEnding(
            from: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

    private static func removeKnownHallucinatedEnding(from text: String) -> String {
        for ending in knownHallucinatedEndings {
            let textRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let wordMatches = wordExpression.matches(in: text, range: textRange)
            let endingWords = normalized(ending).split(separator: " ").map(String.init)
            guard wordMatches.count >= endingWords.count else { continue }

            let suffixMatches = wordMatches.suffix(endingWords.count)
            let suffixWords = suffixMatches.compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else { return nil }
                return normalized(String(text[range]))
            }
            guard suffixWords == endingWords,
                  let firstMatch = suffixMatches.first,
                  let phraseRange = Range(firstMatch.range, in: text) else {
                continue
            }

            return cleanedPrefix(String(text[..<phraseRange.lowerBound]))
        }
        return text
    }

    private static func cleanedPrefix(_ prefix: String) -> String {
        var result = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let softSeparators = CharacterSet(charactersIn: ",;:\u{2013}\u{2014}-")
        while let scalar = result.unicodeScalars.last,
              softSeparators.contains(scalar) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
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
        let logprobs: [TokenLogProbability]?
    }

    private struct TokenLogProbability: Decodable {
        let logprob: Double
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
        let model = preferences.string(forKey: Constants.transcriptionModelKey)
            ?? Constants.defaultTranscriptionModel
        let prompt = transcriptionPrompt(
            vocabulary: vocabulary,
            language: language,
            model: model
        )
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
        let probabilities = decoded.logprobs?.map(\.logprob) ?? []
        let averageLogProbability = probabilities.isEmpty
            ? nil
            : probabilities.reduce(0, +) / Double(probabilities.count)
        return TranscriptionResult(
            text: cleanText,
            averageLogProbability: averageLogProbability
        )
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
        if TranscriptionRequestPolicy.supportsVoiceActivityDetection(
            model: model
        ) {
            data.appendMultipartField(
                boundary: boundary,
                name: "chunking_strategy",
                value: "auto"
            )
            data.appendMultipartField(
                boundary: boundary,
                name: "include[]",
                value: "logprobs"
            )
        }
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

    private func transcriptionPrompt(
        vocabulary: String,
        language: String,
        model: String
    ) -> String? {
        if model == "whisper-1" {
            return vocabulary.isEmpty ? nil : vocabulary
        }
        let vocabularyGuidance = vocabulary.isEmpty
            ? ""
            : language == "en"
                ? " Expected technical vocabulary: \(vocabulary)."
                : " Vocabulaire technique attendu : \(vocabulary)."
        if language == "en" {
            return "Transcribe only words actually spoken. Stop at the last spoken word; never complete trailing silence with extra text. Preserve natural punctuation.\(vocabularyGuidance)"
        }
        return "Transcris uniquement les mots réellement prononcés. Arrête-toi au dernier mot prononcé ; ne complète jamais le silence final par du texte. Conserve une ponctuation naturelle.\(vocabularyGuidance)"
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

enum TranscriptionRequestPolicy {
    static func supportsVoiceActivityDetection(model: String) -> Bool {
        model.hasPrefix("gpt-4o-")
            && model.contains("transcribe")
            && !model.contains("diarize")
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
