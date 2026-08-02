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
    private let realtimeLock = NSLock()
    private var realtimeSocket: URLSessionWebSocketTask?
    private var realtimeAudioContinuation: AsyncStream<Data>.Continuation?
    private var realtimeSenderTask: Task<Void, Error>?
    private var realtimeReceiverTask: Task<Void, Never>?
    private var realtimeCompletion: Result<TranscriptionResult, Error>?
    private var realtimeWaiter: CheckedContinuation<TranscriptionResult, Error>?
    private var realtimePendingAudio: [Data] = []

    var identifier: String { "openai" }
    var isReady: Bool { KeychainHelper.shared.hasAPIKey }

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // Dictation is an interactive path. A stalled request should fail
            // quickly so the HUD never stays in “Transcription” for minutes.
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 15
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    private struct TranscriptionResponse: Decodable {
        struct LogProbability: Decodable {
            let logprob: Double
        }

        let text: String
        let logprobs: [LogProbability]?
    }

    private struct ErrorResponse: Decodable {
        let error: ErrorDetail
    }

    private struct ErrorDetail: Decodable {
        let message: String
    }

    private struct RealtimeServerEvent: Decodable {
        struct RealtimeError: Decodable {
            let message: String
        }

        let type: String
        let transcript: String?
        let error: RealtimeError?
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
        let bodyURL = try makeBodyFile(
            audioURL: audioURL,
            model: model,
            language: language,
            prompt: prompt
        )
        defer { try? FileManager.default.removeItem(at: bodyURL.url) }

        let request = try makeRequest(
            apiKey: apiKey,
            boundary: bodyURL.boundary
        )
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL.url)
        try Task.checkCancellation()
        let decoded = try decodeResponse(data: data, response: response)
        let cleanText = try TranscriptionResponseValidator.validated(
            decoded.text,
            vocabulary: vocabulary,
            prompt: prompt
        )
        let average = decoded.logprobs.flatMap { probabilities -> Double? in
            guard !probabilities.isEmpty else { return nil }
            return probabilities.map(\.logprob).reduce(0, +) / Double(probabilities.count)
        }
        return TranscriptionResult(text: cleanText, averageLogProbability: average)
    }

    func startRealtimeTranscription() async throws {
        guard let apiKey = KeychainHelper.shared.getAPIKey() else {
            throw TranscriptionError.noAPIKey
        }
        guard let url = URL(
            string: "wss://api.openai.com/v1/realtime?model=gpt-live-transcribe"
        ) else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        let (audioStream, continuation) = AsyncStream<Data>.makeStream()

        let pendingAudio = realtimeLock.withLock {
            realtimeSocket = socket
            realtimeAudioContinuation = continuation
            realtimeCompletion = nil
            realtimeWaiter = nil
            let pending = realtimePendingAudio
            realtimePendingAudio.removeAll(keepingCapacity: true)
            return pending
        }
        pendingAudio.forEach { continuation.yield($0) }

        socket.resume()
        realtimeReceiverTask = Task { [weak self, socket] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    self?.handleRealtime(message)
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.completeRealtime(.failure(error))
                    return
                }
            }
        }

        do {
            try await socket.send(.string(try realtimeSessionUpdate()))
        } catch {
            completeRealtime(.failure(error))
            throw error
        }

        realtimeSenderTask = Task { [weak self, socket] in
            do {
                for await chunk in audioStream {
                    try Task.checkCancellation()
                    try await socket.send(
                        .string(try Self.audioAppendEvent(for: chunk))
                    )
                }
            } catch {
                self?.completeRealtime(.failure(error))
                throw error
            }
        }
    }

    func appendRealtimeAudio(_ data: Data) {
        let continuation = realtimeLock.withLock {
            if realtimeAudioContinuation == nil {
                realtimePendingAudio.append(data)
            }
            return realtimeAudioContinuation
        }
        continuation?.yield(data)
    }

    func finishRealtimeTranscription() async throws -> TranscriptionResult {
        let (continuation, sender, socket) = realtimeLock.withLock {
            let state = (
                realtimeAudioContinuation,
                realtimeSenderTask,
                realtimeSocket
            )
            realtimeAudioContinuation = nil
            return state
        }

        guard let socket else {
            throw TranscriptionError.realtimeUnavailable
        }
        defer { cancelRealtimeTranscription() }
        continuation?.finish()
        try await sender?.value
        try await socket.send(
            .string("{\"type\":\"input_audio_buffer.commit\"}")
        )

        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.completeRealtime(.failure(TranscriptionError.realtimeTimeout))
        }
        defer { timeout.cancel() }
        return try await waitForRealtimeCompletion()
    }

    func cancelRealtimeTranscription() {
        realtimeLock.lock()
        let socket = realtimeSocket
        let continuation = realtimeAudioContinuation
        let sender = realtimeSenderTask
        let receiver = realtimeReceiverTask
        let waiter = realtimeWaiter
        realtimeSocket = nil
        realtimeAudioContinuation = nil
        realtimeSenderTask = nil
        realtimeReceiverTask = nil
        realtimeCompletion = nil
        realtimeWaiter = nil
        realtimePendingAudio.removeAll(keepingCapacity: true)
        realtimeLock.unlock()

        continuation?.finish()
        sender?.cancel()
        receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        waiter?.resume(throwing: CancellationError())
    }

    private func realtimeSessionUpdate() throws -> String {
        let preferences = UserDefaults.standard
        let language = preferences.string(forKey: Constants.transcriptionLanguageKey)
            ?? Constants.defaultTranscriptionLanguage
        let vocabulary = selectedVocabulary(preferences: preferences)
        let keywords = vocabulary
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var transcription: [String: Any] = [
            "model": "gpt-live-transcribe",
            "delay": "minimal"
        ]
        if !language.isEmpty {
            transcription["languages"] = [language]
        }
        if !keywords.isEmpty {
            transcription["keywords"] = keywords
        }
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: event)
        return String(decoding: data, as: UTF8.self)
    }

    private static func audioAppendEvent(for data: Data) throws -> String {
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        let encoded = try JSONSerialization.data(withJSONObject: event)
        return String(decoding: encoded, as: UTF8.self)
    }

    private func handleRealtime(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = Data(value.utf8)
        @unknown default:
            return
        }
        guard let event = try? JSONDecoder().decode(
            RealtimeServerEvent.self,
            from: data
        ) else { return }
        switch event.type {
        case "conversation.item.input_audio_transcription.completed":
            do {
                let preferences = UserDefaults.standard
                let vocabulary = selectedVocabulary(preferences: preferences)
                let text = try TranscriptionResponseValidator.validated(
                    event.transcript ?? "",
                    vocabulary: vocabulary
                )
                completeRealtime(
                    .success(
                        TranscriptionResult(
                            text: text,
                            averageLogProbability: nil
                        )
                    )
                )
            } catch {
                completeRealtime(.failure(error))
            }
        case "error":
            completeRealtime(
                .failure(
                    TranscriptionError.apiError(
                        event.error?.message ?? "Échec de la transcription temps réel"
                    )
                )
            )
        default:
            break
        }
    }

    private func completeRealtime(
        _ result: Result<TranscriptionResult, Error>
    ) {
        realtimeLock.lock()
        guard realtimeCompletion == nil else {
            realtimeLock.unlock()
            return
        }
        realtimeCompletion = result
        let waiter = realtimeWaiter
        realtimeWaiter = nil
        realtimeLock.unlock()
        waiter?.resume(with: result)
    }

    private func waitForRealtimeCompletion() async throws -> TranscriptionResult {
        try await withCheckedThrowingContinuation { continuation in
            realtimeLock.lock()
            if let result = realtimeCompletion {
                realtimeLock.unlock()
                continuation.resume(with: result)
            } else {
                realtimeWaiter = continuation
                realtimeLock.unlock()
            }
        }
    }

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard apiKey.hasPrefix("sk-") else { return false }

        do {
            let body = try makeValidationBody()
            defer { try? FileManager.default.removeItem(at: body.url) }
            let request = try makeRequest(apiKey: apiKey, boundary: body.boundary)
            let (_, response) = try await session.upload(for: request, fromFile: body.url)
            guard let http = response as? HTTPURLResponse else { return false }

            // Un audio silencieux minimal peut être accepté ou rejeté comme illisible.
            // Dans les deux cas l'authentification et le droit sur l'endpoint ont été testés.
            return http.statusCode != 401 && http.statusCode != 403 && http.statusCode < 500
        } catch {
            return false
        }
    }

    private func makeBodyFile(
        audioURL: URL,
        model: String,
        language: String,
        prompt: String?
    ) throws -> (url: URL, boundary: String) {
        var body = MultipartFormData()
        try body.appendFile(
            name: "file",
            filename: "audio.\(audioURL.pathExtension)",
            mimeType: Self.audioMIMEType(for: audioURL),
            url: audioURL
        )
        body.appendField(name: "model", value: model)
        body.appendField(name: "response_format", value: "json")
        body.appendField(name: "include[]", value: "logprobs")
        body.appendField(name: "temperature", value: "0")

        if !language.isEmpty {
            body.appendField(name: "language", value: language)
        }
        if let prompt {
            body.appendField(name: "prompt", value: prompt)
        }
        return (try body.writeToTemporaryFile(), body.boundary)
    }

    private func makeValidationBody() throws -> (url: URL, boundary: String) {
        var body = MultipartFormData()
        body.appendFile(
            name: "file",
            filename: "validation.wav",
            mimeType: "audio/wav",
            data: Self.silentWAV
        )
        body.appendField(name: "model", value: Constants.defaultTranscriptionModel)
        body.appendField(name: "language", value: "fr")
        return (try body.writeToTemporaryFile(), body.boundary)
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

    private static let silentWAV: Data = {
        let sampleRate: UInt32 = 16_000
        let samples = Data(repeating: 0, count: 1_600 * 2)
        var data = Data()
        func append<T>(_ value: T) {
            var littleEndian = value
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(Data("RIFF".utf8))
        append(UInt32(36 + samples.count).littleEndian)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian)
        append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian)
        append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian)
        append(UInt16(16).littleEndian)
        data.append(Data("data".utf8))
        append(UInt32(samples.count).littleEndian)
        data.append(samples)
        return data
    }()

    enum TranscriptionError: LocalizedError, Equatable {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case noSpeech
        case realtimeUnavailable
        case realtimeTimeout
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
            case .realtimeUnavailable:
                return "La transcription OpenAI temps réel n’est pas disponible"
            case .realtimeTimeout:
                return "OpenAI temps réel n’a pas répondu assez vite"
            case .apiError(let message):
                return "Erreur API : \(message)"
            case .httpError(let code):
                return "Erreur HTTP : \(code)"
            }
        }
    }
}

extension TranscriptionService: RealtimeSpeechTranscribing {}
