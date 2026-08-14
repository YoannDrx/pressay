import Foundation

struct TranscriptionResult: Equatable {
    let text: String
    let averageLogProbability: Double?
    let networkMetrics: NetworkRequestMetrics?
    let modelIdentifier: String?
    let fulfilledPurpose: RealtimeSpeechPurpose?

    init(
        text: String,
        averageLogProbability: Double?,
        networkMetrics: NetworkRequestMetrics? = nil,
        modelIdentifier: String? = nil,
        fulfilledPurpose: RealtimeSpeechPurpose? = nil
    ) {
        self.text = text
        self.averageLogProbability = averageLogProbability
        self.networkMetrics = networkMetrics
        self.modelIdentifier = modelIdentifier
        self.fulfilledPurpose = fulfilledPurpose
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
    private var realtimePurpose: RealtimeSpeechPurpose = .transcription
    private var realtimeStartedAt: Date?
    private var realtimeReadyAt: Date?
    private var realtimeFirstTextAt: Date?
    private var realtimeAccumulatedText = ""
    private var realtimeTranscriptHandler: ((String, Bool) -> Void)?

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
        // Batch transcription is deliberately always Mini. In Direct mode it
        // is the bounded safety net; in Mini mode it is the selected path.
        // This prevents an unnoticed switch to a more expensive model.
        let model = OpenAITranscriptionProfile.current(in: defaults)
            .batchFallbackModel
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
            decoded = try await ProviderFailurePolicy.performWithOneSafeRetry {
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
            modelIdentifier: model
        )
    }

    func startRealtimeTranscription(
        purpose: RealtimeSpeechPurpose
    ) async throws {
        let apiKeyProvider = self.apiKeyProvider
        let apiKey = try await Task.detached(priority: .userInitiated) {
            guard let apiKey = apiKeyProvider() else {
                throw TranscriptionError.noAPIKey
            }
            return apiKey
        }.value
        let endpoint = switch purpose {
        case .transcription:
            "wss://api.openai.com/v1/realtime?intent=transcription"
        case .translation:
            "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate"
        }
        guard let url = URL(string: endpoint) else {
            throw TranscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        let (audioStream, continuation) = AsyncStream<Data>.makeStream()

        let pendingAudio = installRealtimeState(
            socket: socket,
            continuation: continuation,
            purpose: purpose
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
            try await socket.send(
                .string(try realtimeSessionUpdate(for: purpose))
            )
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
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
                        .string(
                            try Self.audioAppendEvent(
                                for: chunk,
                                purpose: purpose
                            )
                        )
                    )
                }
            } catch {
                self?.completeRealtime(.failure(error))
                throw error
            }
        }
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

    func setRealtimeTranscriptHandler(
        _ handler: ((String, Bool) -> Void)?
    ) {
        realtimeLock.lock()
        realtimeTranscriptHandler = handler
        realtimeLock.unlock()
    }

    func finishRealtimeTranscription() async throws -> TranscriptionResult {
        let (continuation, sender, socket) = realtimeFinishState()

        guard let socket else { throw TranscriptionError.realtimeUnavailable }
        defer { cancelRealtimeTranscription() }
        continuation?.finish()
        try await sender?.value
        let finishEvent = realtimeLock.withLock {
            switch realtimePurpose {
            case .transcription:
                "{\"type\":\"input_audio_buffer.commit\"}"
            case .translation:
                "{\"type\":\"session.close\"}"
            }
        }
        try await socket.send(.string(finishEvent))

        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
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
        realtimePurpose = .transcription
        realtimeStartedAt = nil
        realtimeReadyAt = nil
        realtimeFirstTextAt = nil
        realtimeAccumulatedText = ""
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
        continuation: AsyncStream<Data>.Continuation,
        purpose: RealtimeSpeechPurpose
    ) -> [Data] {
        realtimeLock.lock()
        defer { realtimeLock.unlock() }
        realtimeSocket = socket
        realtimeAudioContinuation = continuation
        realtimeCompletion = nil
        realtimeWaiter = nil
        realtimeReadyCompletion = nil
        realtimeReadyWaiter = nil
        realtimePurpose = purpose
        realtimeStartedAt = Date()
        realtimeReadyAt = nil
        realtimeFirstTextAt = nil
        realtimeAccumulatedText = ""
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

    func realtimeSessionUpdate(
        for purpose: RealtimeSpeechPurpose = .transcription
    ) throws -> String {
        if case .translation(let targetLanguage) = purpose {
            let event: [String: Any] = [
                "type": "session.update",
                "session": [
                    "audio": [
                        "output": ["language": targetLanguage]
                    ]
                ]
            ]
            return String(
                decoding: try JSONSerialization.data(withJSONObject: event),
                as: UTF8.self
            )
        }
        let language = defaults.string(forKey: Constants.transcriptionLanguageKey)
            ?? Constants.defaultTranscriptionLanguage
        let vocabulary = Self.selectedVocabulary(preferences: defaults)
        let keywords = Self.sanitizedKeywords(from: vocabulary)
        var transcription: [String: Any] = [
            "model": "gpt-live-transcribe",
            "delay": "minimal"
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
        // Translation sessions use their own input-buffer event namespace.
        // The caller selects the concrete type when serializing a chunk.
        try audioAppendEvent(for: data, purpose: .transcription)
    }

    private static func audioAppendEvent(
        for data: Data,
        purpose: RealtimeSpeechPurpose
    ) throws -> String {
        let event: [String: Any] = [
            "type": purpose.isTranslation
                ? "session.input_audio_buffer.append"
                : "input_audio_buffer.append",
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
            appendRealtimeDelta(event.delta, isTranslation: false)
        case "conversation.item.input_audio_transcription.completed":
            do {
                let vocabulary = Self.selectedVocabulary(preferences: defaults)
                let text = try TranscriptionResponseValidator.validated(
                    event.transcript ?? "",
                    vocabulary: vocabulary
                )
                publishRealtimeText(text, isTranslation: false)
                completeRealtime(
                    .success(
                        TranscriptionResult(
                            text: text,
                            averageLogProbability: nil,
                            networkMetrics: realtimeMetrics(finalizedAt: Date()),
                            modelIdentifier: "gpt-live-transcribe",
                            fulfilledPurpose: .transcription
                        )
                    )
                )
            } catch {
                completeRealtime(.failure(error))
            }
        case "session.output_transcript.delta":
            appendRealtimeDelta(event.delta, isTranslation: true)
        case "session.closed":
            do {
                let (text, purpose) = realtimeLock.withLock {
                    (realtimeAccumulatedText, realtimePurpose)
                }
                guard purpose.isTranslation else { return }
                let cleanText = try TranscriptionResponseValidator.validated(
                    text,
                    vocabulary: ""
                )
                publishRealtimeText(cleanText, isTranslation: true)
                completeRealtime(
                    .success(
                        TranscriptionResult(
                            text: cleanText,
                            averageLogProbability: nil,
                            networkMetrics: realtimeMetrics(finalizedAt: Date()),
                            modelIdentifier: purpose.modelIdentifier,
                            fulfilledPurpose: purpose
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

    private func appendRealtimeDelta(
        _ delta: String?,
        isTranslation: Bool
    ) {
        guard let delta, !delta.isEmpty else { return }
        realtimeLock.lock()
        if realtimeFirstTextAt == nil { realtimeFirstTextAt = Date() }
        realtimeAccumulatedText += delta
        let text = realtimeAccumulatedText
        let handler = realtimeTranscriptHandler
        realtimeLock.unlock()
        handler?(text, isTranslation)
    }

    private func publishRealtimeText(
        _ text: String,
        isTranslation: Bool
    ) {
        realtimeLock.lock()
        realtimeAccumulatedText = text
        let handler = realtimeTranscriptHandler
        realtimeLock.unlock()
        handler?(text, isTranslation)
    }

    private func realtimeMetrics(finalizedAt: Date) -> NetworkRequestMetrics? {
        let (startedAt, readyAt, firstTextAt) = realtimeLock.withLock {
            (realtimeStartedAt, realtimeReadyAt, realtimeFirstTextAt)
        }
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

    private static func makeBody(
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
        if TranscriptionRequestPolicy.supportsLogProbabilities(
            model: model
        ) {
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
        let forbidden = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-'’._+#"))
            .inverted
        var seen = Set<String>()
        var result: [String] = []
        for rawValue in vocabulary.components(
            separatedBy: CharacterSet(charactersIn: ",\n\r")
        ) {
            let scalars = rawValue.unicodeScalars.filter {
                !forbidden.contains($0)
            }
            let clean = String(String.UnicodeScalarView(scalars))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(64)
            guard !clean.isEmpty else { continue }
            let value = String(clean)
            let key = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { continue }
            result.append(value)
            if result.count == 50 { break }
        }
        return result
    }

    private static func transcriptionPrompt(
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
