import Foundation

final class TranscriptionService {
    static let shared = TranscriptionService()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    struct TranscriptionResponse: Codable {
        let text: String
    }

    struct ErrorResponse: Codable {
        let error: ErrorDetail
    }

    struct ErrorDetail: Codable {
        let message: String
        let type: String?
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let apiKey = KeychainHelper.shared.getAPIKey() else {
            throw TranscriptionError.noAPIKey
        }

        guard let url = URL(string: Constants.openAITranscriptionURL) else {
            throw TranscriptionError.invalidURL
        }

        let audioData = try Data(contentsOf: audioURL)
        let boundary = UUID().uuidString
        let preferences = UserDefaults.standard
        let language = preferences.string(forKey: Constants.transcriptionLanguageKey)
            ?? Constants.defaultTranscriptionLanguage
        let vocabulary = preferences.string(forKey: Constants.technicalVocabularyKey)
            ?? Constants.defaultTechnicalVocabulary

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n", to: &body)
        append("Content-Type: audio/m4a\r\n\r\n", to: &body)
        body.append(audioData)
        append("\r\n", to: &body)

        appendFormField(name: "model", value: Constants.openAIModel, boundary: boundary, to: &body)

        // Fournir la langue améliore à la fois la précision et la latence. Une valeur
        // vide laisse le modèle la détecter pour les usages multilingues.
        if !language.isEmpty {
            appendFormField(name: "language", value: language, boundary: boundary, to: &body)
        }

        let cleanVocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanVocabulary.isEmpty {
            let prompt = transcriptionPrompt(vocabulary: cleanVocabulary, language: language)
            appendFormField(name: "prompt", value: prompt, boundary: boundary, to: &body)
        }

        // Une température basse rend la dictée plus déterministe.
        appendFormField(name: "temperature", value: "0", boundary: boundary, to: &body)
        append("--\(boundary)--\r\n", to: &body)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return try validatedText(transcriptionResponse.text, vocabulary: cleanVocabulary)
        } else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw TranscriptionError.apiError(errorResponse.error.message)
            }
            throw TranscriptionError.httpError(httpResponse.statusCode)
        }
    }

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard apiKey.hasPrefix("sk-") else { return false }

        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return false
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {}

        return false
    }

    private func appendFormField(name: String, value: String, boundary: String, to body: inout Data) {
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
        append("\(value)\r\n", to: &body)
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }

    private func transcriptionPrompt(vocabulary: String, language: String) -> String {
        if language == "en" {
            return "Natural dictation with accurate punctuation. Technical vocabulary may include: \(vocabulary)."
        }

        return "Dictée naturelle avec une ponctuation fidèle. Le vocabulaire technique peut inclure : \(vocabulary)."
    }

    private func validatedText(_ text: String, vocabulary: String) throws -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            throw TranscriptionError.noSpeech
        }

        // Dernière protection si le service renvoie le vocabulaire de contexte à la
        // place d'une transcription (le bug historique observé sur un audio silencieux).
        if normalized(cleanText) == normalized(vocabulary), !vocabulary.isEmpty {
            throw TranscriptionError.noSpeech
        }

        return cleanText
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    enum TranscriptionError: LocalizedError {
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
                return "Erreur API: \(message)"
            case .httpError(let code):
                return "Erreur HTTP: \(code)"
            }
        }
    }
}
