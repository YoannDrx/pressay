import Foundation

struct TranscriptionResult: Equatable {
    let text: String
    let averageLogProbability: Double?
    let networkMetrics: NetworkRequestMetrics?
    let modelIdentifier: String?
    let profile: OpenAITranscriptionProfile?

    init(
        text: String,
        averageLogProbability: Double?,
        networkMetrics: NetworkRequestMetrics? = nil,
        modelIdentifier: String? = nil,
        profile: OpenAITranscriptionProfile? = nil
    ) {
        self.text = text
        self.averageLogProbability = averageLogProbability
        self.networkMetrics = networkMetrics
        self.modelIdentifier = modelIdentifier
        self.profile = profile
    }

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
    private static let pressayApplicationExpression = try! NSRegularExpression(
        pattern: "(?i)(\\b(?:application(?:\\s+de\\s+dictée)?|outil(?:\\s+de\\s+dictée)?|logiciel(?:\\s+de\\s+dictée)?|dictée)\\s+)(?:press[ée]|presay|présé)\\b"
    )

    static func validated(
        _ text: String,
        vocabulary: String,
        prompt: String? = nil
    ) throws -> String {
        let rawCleanText = removeKnownHallucinatedEnding(
            from: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let cleanText = restoreProtectedProductNames(
            in: rawCleanText,
            vocabulary: vocabulary
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

    private static func restoreProtectedProductNames(
        in text: String,
        vocabulary: String
    ) -> String {
        guard normalized(vocabulary).split(separator: " ").contains("pressay")
        else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return pressayApplicationExpression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1Pressay"
        )
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

enum InstantDictationTextNormalizer {
    static func normalized(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class TranscriptionService: SpeechTranscribing {
    static let shared = TranscriptionService()

    private let session: URLSession
    private let apiKeyProvider: () -> String?
    private let defaults: UserDefaults
    private let realtimeLock = NSLock()
    private var realtimeSocket: URLSessionWebSocketTask?
    private var realtimeAudioContinuation: AsyncStream<Data>.Continuation?
    private var realtimeSenderTask: Task<Void, Error>?
    private var realtimeReceiverTask: Task<Void, Never>?
    private var realtimeCompletion: Result<TranscriptionResult, Error>?
    private var realtimeWaiter: CheckedContinuation<TranscriptionResult, Error>?
    private var realtimeReadyCompletion: Result<Void, Error>?
    private var realtimeReadyWaiter: CheckedContinuation<Void, Error>?
    private var realtimePendingAudio: [Data] = []
    private var realtimeStartedAt: Date?
    private var realtimeReadyAt: Date?
    private var realtimeFirstTextAt: Date?
    private var realtimeDeltaText = ""
    private var realtimeTranscriptHandler: ((String) -> Void)?

    var identifier: String { "openai" }
    var isReady: Bool { apiKeyProvider() != nil }
    var realtimeEnabled: Bool {
        OpenAITranscriptionProfile.current(in: defaults).usesRealtime
    }

    init(
        session: URLSession? = nil,
        apiKeyProvider: @escaping () -> String? = {
            KeychainHelper.shared.getAPIKey()
        },
        defaults: UserDefaults = .standard
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        self.apiKeyProvider = apiKeyProvider
        self.defaults = defaults
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

    private struct PreparedTranscriptionRequest {
        let request: URLRequest
        let vocabulary: String
        let prompt: String?
    }

    private struct RealtimeServerEvent: Decodable {
        struct RealtimeError: Decodable {
            let message: String
        }

        let type: String
        let transcript: String?
        let delta: String?
        let error: RealtimeError?
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        // This method is normally entered from SessionCoordinator's MainActor.
        // Keychain access and multipart assembly are synchronous, so doing them
        // inline can freeze the HUD and prevent the timeout task from firing.
        let apiKeyProvider = self.apiKeyProvider
        let apiKey = try await Task.detached(priority: .userInitiated) {
            guard let apiKey = apiKeyProvider() else {
                throw TranscriptionError.noAPIKey
            }
            return apiKey
        }.value
        let language = defaults.string(forKey: Constants.transcriptionLanguageKey)
            ?? Constants.defaultTranscriptionLanguage
        let vocabulary = Self.selectedVocabulary(preferences: defaults)
        let profile = OpenAITranscriptionProfile.current(in: defaults)
        let model = profile.batchModel
        let prepared = try await Task.detached(priority: .userInitiated) {
            try Self.prepareRequest(
                audioURL: audioURL,
                apiKey: apiKey,
                language: language,
                vocabulary: vocabulary,
                model: model
            )
        }.value
        try Task.checkCancellation()

        let decoded: TranscriptionResponse
        var requestMetrics: [NetworkRequestMetrics] = []
        do {
            decoded = try await ProviderFailurePolicy.performWithSafeRetries(
                maxRetries: 2,
                allowAmbiguousNetworkErrors: true
            ) {
                let collector = NetworkTaskMetricsCollector()
                let startedAt = Date()
                let data: Data
                let response: URLResponse
                do {
                    (data, response) = try await self.session.data(
                        for: prepared.request,
                        delegate: collector
                    )
                } catch {
                    requestMetrics.append(
                        collector.snapshot(
                            fallbackTotal: Date().timeIntervalSince(startedAt)
                        )
                    )
                    throw error
                }
                requestMetrics.append(
                    collector.snapshot(
                        fallbackTotal: Date().timeIntervalSince(startedAt)
                    )
                )
                try Task.checkCancellation()
                return try self.decodeResponse(data: data, response: response)
            }
        } catch {
            if Task.isCancelled
                || error is CancellationError
                || (error as? URLError)?.code == .cancelled {
                throw error
            }
            let underlying: Error
            if let networkError = ProviderNetworkError(error) {
                underlying = networkError
            } else {
                underlying = error
            }
            throw ProviderRequestFailure(
                underlying: underlying,
                networkMetrics: .combined(requestMetrics)
            )
        }
        let cleanText = try TranscriptionResponseValidator.validated(
            decoded.text,
            vocabulary: prepared.vocabulary,
            prompt: prepared.prompt
        )
        let probabilities = decoded.logprobs?.map(\.logprob) ?? []
        let averageLogProbability = probabilities.isEmpty
            ? nil
            : probabilities.reduce(0, +) / Double(probabilities.count)
        return TranscriptionResult(
            text: cleanText,
            averageLogProbability: averageLogProbability,
            networkMetrics: .combined(requestMetrics),
            modelIdentifier: model,
            profile: profile
        )
    }

    func startRealtimeTranscription() async throws {
        let apiKeyProvider = self.apiKeyProvider
        let apiKey = try await Task.detached(priority: .userInitiated) {
            guard let apiKey = apiKeyProvider() else {
                throw TranscriptionError.noAPIKey
            }
            return apiKey
        }.value
        guard let url = URL(
            string: "wss://api.openai.com/v1/realtime?intent=transcription"
        ) else { throw TranscriptionError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        let (audioStream, continuation) = AsyncStream<Data>.makeStream()

        let pendingAudio = installRealtimeState(
            socket: socket,
            continuation: continuation
        )
        pendingAudio.forEach { continuation.yield($0) }

        socket.resume()
        realtimeReceiverTask = Task { [weak self, socket] in
            while !Task.isCancelled {
                do {
                    self?.handleRealtime(try await socket.receive())
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.completeRealtimeReady(.failure(error))
                    self?.completeRealtime(.failure(error))
                    return
                }
            }
        }

        do {
            try await socket.send(.string(try realtimeSessionUpdate()))
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.completeRealtimeReady(
                    .failure(TranscriptionError.realtimeTimeout)
                )
            }
            defer { timeout.cancel() }
            try await waitForRealtimeReady()
        } catch {
            cancelRealtimeTranscription()
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

    func setRealtimeTranscriptHandler(_ handler: ((String) -> Void)?) {
        realtimeLock.lock()
        realtimeTranscriptHandler = handler
        realtimeLock.unlock()
    }

    func appendRealtimeAudio(_ data: Data) {
        realtimeLock.lock()
        let continuation = realtimeAudioContinuation
        if continuation == nil {
            realtimePendingAudio.append(data)
        }
        realtimeLock.unlock()
        continuation?.yield(data)
    }

    func finishRealtimeTranscription() async throws -> TranscriptionResult {
        let (continuation, sender, socket) = realtimeFinishState()

        guard let socket else { throw TranscriptionError.realtimeUnavailable }
        defer { cancelRealtimeTranscription() }
        continuation?.finish()
        try await sender?.value
        try await socket.send(
            .string("{\"type\":\"input_audio_buffer.commit\"}")
        )

        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
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
        let readyWaiter = realtimeReadyWaiter
        realtimeSocket = nil
        realtimeAudioContinuation = nil
        realtimeSenderTask = nil
        realtimeReceiverTask = nil
        realtimeCompletion = nil
        realtimeWaiter = nil
        realtimeReadyCompletion = nil
        realtimeReadyWaiter = nil
        realtimePendingAudio.removeAll(keepingCapacity: true)
        realtimeStartedAt = nil
        realtimeReadyAt = nil
        realtimeFirstTextAt = nil
        realtimeDeltaText = ""
        realtimeTranscriptHandler = nil
        realtimeLock.unlock()

        continuation?.finish()
        sender?.cancel()
        receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        waiter?.resume(throwing: CancellationError())
        readyWaiter?.resume(throwing: CancellationError())
    }

    private func installRealtimeState(
        socket: URLSessionWebSocketTask,
        continuation: AsyncStream<Data>.Continuation
    ) -> [Data] {
        realtimeLock.lock()
        defer { realtimeLock.unlock() }
        realtimeSocket = socket
        realtimeAudioContinuation = continuation
        realtimeCompletion = nil
        realtimeWaiter = nil
        realtimeReadyCompletion = nil
        realtimeReadyWaiter = nil
        realtimeStartedAt = Date()
        realtimeReadyAt = nil
        realtimeFirstTextAt = nil
        realtimeDeltaText = ""
        let pending = realtimePendingAudio
        realtimePendingAudio.removeAll(keepingCapacity: true)
        return pending
    }

    private func realtimeFinishState() -> (
        AsyncStream<Data>.Continuation?,
        Task<Void, Error>?,
        URLSessionWebSocketTask?
    ) {
        realtimeLock.lock()
        defer { realtimeLock.unlock() }
        let state = (
            realtimeAudioContinuation,
            realtimeSenderTask,
            realtimeSocket
        )
        realtimeAudioContinuation = nil
        return state
    }

    func realtimeSessionUpdate() throws -> String {
        let language = defaults.string(forKey: Constants.transcriptionLanguageKey)
            ?? Constants.defaultTranscriptionLanguage
        let vocabulary = Self.selectedVocabulary(preferences: defaults)
        let keywords = Self.sanitizedKeywords(from: vocabulary)
        var transcription: [String: Any] = [
            "model": "gpt-live-transcribe",
            "delay": "low"
        ]
        if !language.isEmpty { transcription["languages"] = [language] }
        if !keywords.isEmpty { transcription["keywords"] = keywords }
        if let prompt = Self.transcriptionPrompt(
            vocabulary: vocabulary,
            language: language,
            model: "gpt-live-transcribe"
        ) {
            transcription["prompt"] = prompt
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
        return String(
            decoding: try JSONSerialization.data(withJSONObject: event),
            as: UTF8.self
        )
    }

    private static func audioAppendEvent(for data: Data) throws -> String {
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        return String(
            decoding: try JSONSerialization.data(withJSONObject: event),
            as: UTF8.self
        )
    }

    private func handleRealtime(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: return
        }
        guard let event = try? JSONDecoder().decode(
            RealtimeServerEvent.self,
            from: data
        ) else { return }
        switch event.type {
        case "session.updated":
            realtimeLock.lock()
            realtimeReadyAt = Date()
            realtimeLock.unlock()
            completeRealtimeReady(.success(()))
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = event.delta, !delta.isEmpty else { break }
            realtimeLock.lock()
            if realtimeFirstTextAt == nil { realtimeFirstTextAt = Date() }
            realtimeDeltaText += delta
            let partialText = realtimeDeltaText
            let handler = realtimeTranscriptHandler
            realtimeLock.unlock()
            handler?(partialText)
        case "conversation.item.input_audio_transcription.completed":
            do {
                let vocabulary = Self.selectedVocabulary(preferences: defaults)
                let text = try TranscriptionResponseValidator.validated(
                    event.transcript ?? "",
                    vocabulary: vocabulary
                )
                realtimeLock.lock()
                let handler = realtimeTranscriptHandler
                realtimeLock.unlock()
                handler?(text)
                completeRealtime(
                    .success(
                        TranscriptionResult(
                            text: text,
                            averageLogProbability: nil,
                            networkMetrics: realtimeMetrics(finalizedAt: Date()),
                            modelIdentifier: "gpt-live-transcribe",
                            profile: .liveQuality
                        )
                    )
                )
            } catch {
                completeRealtime(.failure(error))
            }
        case "error":
            let error = TranscriptionError.apiError(
                event.error?.message
                    ?? "Échec de la transcription temps réel"
            )
            completeRealtimeReady(.failure(error))
            completeRealtime(.failure(error))
        default:
            break
        }
    }

    private func realtimeMetrics(finalizedAt: Date) -> NetworkRequestMetrics? {
        realtimeLock.lock()
        let startedAt = realtimeStartedAt
        let readyAt = realtimeReadyAt
        let firstTextAt = realtimeFirstTextAt
        realtimeLock.unlock()
        guard let startedAt else { return nil }
        return NetworkRequestMetrics(
            dnsSeconds: nil,
            connectionSeconds: readyAt.map {
                max(0, $0.timeIntervalSince(startedAt))
            },
            tlsSeconds: nil,
            requestSeconds: nil,
            timeToFirstByteSeconds: firstTextAt.map {
                max(0, $0.timeIntervalSince(startedAt))
            },
            responseSeconds: nil,
            totalSeconds: max(0, finalizedAt.timeIntervalSince(startedAt)),
            attempts: 1,
            reusedConnection: false
        )
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

    private func completeRealtimeReady(_ result: Result<Void, Error>) {
        realtimeLock.lock()
        guard realtimeReadyCompletion == nil else {
            realtimeLock.unlock()
            return
        }
        realtimeReadyCompletion = result
        let waiter = realtimeReadyWaiter
        realtimeReadyWaiter = nil
        realtimeLock.unlock()
        waiter?.resume(with: result)
    }

    private func waitForRealtimeReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            realtimeLock.lock()
            if let result = realtimeReadyCompletion {
                realtimeLock.unlock()
                continuation.resume(with: result)
            } else {
                realtimeReadyWaiter = continuation
                realtimeLock.unlock()
            }
        }
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

    private static func prepareRequest(
        audioURL: URL,
        apiKey: String,
        language: String,
        vocabulary: String,
        model: String
    ) throws -> PreparedTranscriptionRequest {
        let prompt = transcriptionPrompt(
            vocabulary: vocabulary,
            language: language,
            model: model
        )
        let body = try makeBody(
            audioURL: audioURL,
            model: model,
            language: language,
            keywords: sanitizedKeywords(from: vocabulary),
            prompt: prompt
        )

        var request = try makeRequest(
            apiKey: apiKey,
            boundary: body.boundary
        )
        request.httpBody = body.data
        return PreparedTranscriptionRequest(
            request: request,
            vocabulary: vocabulary,
            prompt: prompt
        )
    }

    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard apiKey.hasPrefix("sk-") else { return false }

        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    static func makeBody(
        audioURL: URL,
        model: String,
        language: String,
        keywords: [String],
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
        if TranscriptionRequestPolicy.supportsLogProbabilities(
            model: model
        ) {
            data.appendMultipartField(
                boundary: boundary,
                name: "include[]",
                value: "logprobs"
            )
        }
        if !language.isEmpty,
           TranscriptionRequestPolicy.usesPluralLanguages(model: model) {
            data.appendMultipartField(
                boundary: boundary,
                name: "languages[]",
                value: language
            )
        } else if !language.isEmpty {
            data.appendMultipartField(
                boundary: boundary,
                name: "language",
                value: language
            )
        }
        if TranscriptionRequestPolicy.supportsKeywords(model: model) {
            for keyword in keywords {
                data.appendMultipartField(
                    boundary: boundary,
                    name: "keywords[]",
                    value: keyword
                )
            }
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

    private static func makeRequest(apiKey: String, boundary: String) throws -> URLRequest {
        guard let url = URL(string: Constants.openAITranscriptionURL) else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func decodeResponse(data: Data, response: URLResponse) throws -> TranscriptionResponse {
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let retryAfter = Self.retryAfter(from: http)
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw TranscriptionError.httpFailure(
                    status: http.statusCode,
                    message: error.error.message,
                    retryAfter: retryAfter
                )
            }
            throw TranscriptionError.httpFailure(
                status: http.statusCode,
                message: nil,
                retryAfter: retryAfter
            )
        }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value) { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private static func selectedVocabulary(preferences: UserDefaults) -> String {
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

    static func sanitizedKeywords(from vocabulary: String) -> [String] {
        var seen = Set<String>()
        return vocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .map {
                $0.replacingOccurrences(of: "<", with: "")
                    .replacingOccurrences(of: ">", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .compactMap { value -> String? in
                let bounded = String(value.prefix(80))
                let key = bounded.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                guard seen.insert(key).inserted else { return nil }
                return bounded
            }
            .prefix(64)
            .map { $0 }
    }

    private static func transcriptionPrompt(
        vocabulary: String,
        language: String,
        model: String
    ) -> String? {
        if model == "whisper-1" {
            return vocabulary.isEmpty ? nil : vocabulary
        }
        let safeVocabulary = sanitizedKeywords(from: vocabulary).joined(separator: ", ")
        let vocabularyGuidance = safeVocabulary.isEmpty
            ? ""
            : language == "en"
                ? " The recording may discuss the Pressay dictation application. Expected literal spellings for proper names and technical terms include: \(safeVocabulary). Pressay is the product name pronounced like the French word ‘pressé’."
                : " L’enregistrement peut parler de l’application de dictée Pressay. Orthographes littérales attendues pour les noms propres et termes techniques : \(safeVocabulary). Pressay est le nom du produit, prononcé comme « pressé »."
        if language == "en" {
            return "Natural personal dictation in English.\(vocabularyGuidance)"
        }
        if language.isEmpty {
            return "Natural personal dictation, usually in French or English.\(vocabularyGuidance)"
        }
        return "Dictée personnelle naturelle en français.\(vocabularyGuidance)"
    }

    enum TranscriptionError: LocalizedError, Equatable {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case noSpeech
        case apiError(String)
        case httpError(Int)
        case httpFailure(
            status: Int,
            message: String?,
            retryAfter: TimeInterval?
        )
        case realtimeUnavailable
        case realtimeTimeout

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
            case .httpFailure(let status, let message, _):
                if status == 401 || status == 403 {
                    return "Clé OpenAI invalide — vérifie-la dans les réglages"
                }
                if status == 429 {
                    if message?.localizedCaseInsensitiveContains("quota") == true
                        || message?.localizedCaseInsensitiveContains("insufficient") == true {
                        return "Quota OpenAI atteint — vérifie ton compte"
                    }
                    return "OpenAI limite temporairement les requêtes — réessaie dans un instant"
                }
                if (500...599).contains(status) {
                    return "OpenAI est temporairement indisponible — réessaie dans un instant"
                }
                if let message, !message.isEmpty {
                    return "OpenAI (HTTP \(status)) : \(message)"
                }
                return "OpenAI a répondu avec l’erreur HTTP \(status)"
            case .realtimeUnavailable:
                return "La transcription temps réel n’est pas disponible"
            case .realtimeTimeout:
                return "La transcription temps réel n’a pas finalisé à temps"
            }
        }
    }
}

extension TranscriptionService: RealtimeSpeechTranscribing {}

enum TranscriptionRequestPolicy {
    static func supportsLogProbabilities(model: String) -> Bool {
        model.hasPrefix("gpt-4o-")
            && model.contains("transcribe")
            && !model.contains("diarize")
    }

    static func usesPluralLanguages(model: String) -> Bool {
        model == "gpt-transcribe"
    }

    static func supportsKeywords(model: String) -> Bool {
        model == "gpt-transcribe"
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
