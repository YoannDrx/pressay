import AVFoundation
import Foundation
import FoundationModels
import Speech

enum ProviderRoutingError: LocalizedError, Equatable {
    case providerNotFound(String)
    case providerUnavailable(String)
    case localProviderUnavailable
    case cloudProviderUnavailable

    var errorDescription: String? {
        switch self {
        case .providerNotFound(let identifier):
            return "Fournisseur inconnu : \(identifier)"
        case .providerUnavailable(let reason):
            return reason
        case .localProviderUnavailable:
            return "Aucun fournisseur local compatible n’est disponible"
        case .cloudProviderUnavailable:
            return "Aucun fournisseur cloud compatible n’est disponible"
        }
    }
}

final class TranscriptionRouter: TranscriptionRouting {
    private struct Registration {
        let descriptor: ProviderDescriptor
        let provider: any SpeechTranscribing
    }

    private var registrations: [String: Registration]
    private let automaticCloudProviderID: String
    private let automaticLocalProviderIDs: [String]

    init(
        registrations: [(ProviderDescriptor, any SpeechTranscribing)],
        automaticCloudProviderID: String = "openai",
        automaticLocalProviderIDs: [String] = [
            "speech-analyzer",
            "parakeet",
            "whisper-cpp"
        ]
    ) {
        self.registrations = Dictionary(
            uniqueKeysWithValues: registrations.map {
                ($0.0.id, Registration(descriptor: $0.0, provider: $0.1))
            }
        )
        self.automaticCloudProviderID = automaticCloudProviderID
        self.automaticLocalProviderIDs = automaticLocalProviderIDs
    }

    convenience init(openAI: any SpeechTranscribing) {
        self.init(
            registrations: [
                (
                    ProviderDescriptor(
                        id: openAI.identifier,
                        displayName: "OpenAI",
                        locality: .cloud,
                        supportedLocales: ["fr", "en"],
                        // Readiness is checked by the router when this
                        // provider is actually selected. Avoid touching the
                        // Keychain while Pressay builds its application graph.
                        availability: .available
                    ),
                    openAI
                )
            ],
            automaticCloudProviderID: openAI.identifier
        )
    }

    func provider(
        for mode: ModeDefinition,
        capabilities: CapabilityMatrix
    ) throws -> any SpeechTranscribing {
        if let requested = mode.transcriptionProviderID {
            let provider = try availableProvider(identifier: requested)
            guard mode.providerPolicy != .localOnly
                    || provider.locality == .local else {
                throw ProviderRoutingError.localProviderUnavailable
            }
            return provider
        }
        switch mode.providerPolicy {
        case .localOnly:
            return try automaticLocalProvider()
        case .preferLocal:
            if let local = try? automaticLocalProvider() {
                return local
            }
            return try availableProvider(identifier: automaticCloudProviderID)
        case .askBeforeCloud, .cloudAllowed:
            return try availableProvider(identifier: automaticCloudProviderID)
        }
    }

    private func automaticLocalProvider() throws -> any SpeechTranscribing {
        for identifier in automaticLocalProviderIDs {
            if let provider = try? availableProvider(identifier: identifier) {
                return provider
            }
        }
        throw ProviderRoutingError.localProviderUnavailable
    }

    private func availableProvider(
        identifier: String
    ) throws -> any SpeechTranscribing {
        guard let registration = registrations[identifier] else {
            throw ProviderRoutingError.providerNotFound(identifier)
        }
        switch registration.descriptor.availability {
        case .available:
            guard registration.provider.isReady else {
                throw ProviderRoutingError.providerUnavailable(
                    "\(registration.descriptor.displayName) n’est pas prêt"
                )
            }
            return registration.provider
        case .unavailable(let reason):
            throw ProviderRoutingError.providerUnavailable(reason)
        case .requiresDownload(let modelID):
            throw ProviderRoutingError.providerUnavailable(
                "Le modèle \(modelID) doit être téléchargé"
            )
        }
    }
}

final class ProcessingRouter: ProcessingRouting {
    private struct Registration {
        let descriptor: ProviderDescriptor
        let provider: any TextProcessing
    }

    private var registrations: [String: Registration]
    private let automaticCloudProviderID: String
    private let automaticLocalProviderIDs: [String]

    init(
        registrations: [(ProviderDescriptor, any TextProcessing)],
        automaticCloudProviderID: String = "openai-responses",
        automaticLocalProviderIDs: [String] = [
            "foundation-models",
            "llama-cpp"
        ]
    ) {
        self.registrations = Dictionary(
            uniqueKeysWithValues: registrations.map {
                ($0.0.id, Registration(descriptor: $0.0, provider: $0.1))
            }
        )
        self.automaticCloudProviderID = automaticCloudProviderID
        self.automaticLocalProviderIDs = automaticLocalProviderIDs
    }

    convenience init(openAI: any TextProcessing) {
        self.init(
            registrations: [
                (
                    ProviderDescriptor(
                        id: openAI.identifier,
                        displayName: "OpenAI Responses",
                        locality: .cloud,
                        supportedLocales: ["fr", "en"],
                        availability: .available
                    ),
                    openAI
                )
            ],
            automaticCloudProviderID: openAI.identifier
        )
    }

    func provider(
        for mode: ModeDefinition,
        capabilities: CapabilityMatrix
    ) throws -> any TextProcessing {
        if let requested = mode.processingProviderID {
            let provider = try availableProvider(identifier: requested)
            guard mode.providerPolicy != .localOnly
                    || provider.locality == .local else {
                throw ProviderRoutingError.localProviderUnavailable
            }
            return provider
        }
        switch mode.providerPolicy {
        case .localOnly:
            return try automaticLocalProvider()
        case .preferLocal:
            if let local = try? automaticLocalProvider() {
                return local
            }
            return try availableProvider(identifier: automaticCloudProviderID)
        case .askBeforeCloud, .cloudAllowed:
            return try availableProvider(identifier: automaticCloudProviderID)
        }
    }

    private func automaticLocalProvider() throws -> any TextProcessing {
        for identifier in automaticLocalProviderIDs {
            if let provider = try? availableProvider(identifier: identifier) {
                return provider
            }
        }
        throw ProviderRoutingError.localProviderUnavailable
    }

    private func availableProvider(
        identifier: String
    ) throws -> any TextProcessing {
        guard let registration = registrations[identifier] else {
            throw ProviderRoutingError.providerNotFound(identifier)
        }
        switch registration.descriptor.availability {
        case .available:
            return registration.provider
        case .unavailable(let reason):
            throw ProviderRoutingError.providerUnavailable(reason)
        case .requiresDownload(let modelID):
            throw ProviderRoutingError.providerUnavailable(
                "Le modèle \(modelID) doit être téléchargé"
            )
        }
    }
}

@available(macOS 26.0, *)
final class SpeechAnalyzerTranscriptionProvider: SpeechTranscribing {
    let identifier = "speech-analyzer"
    let locality: ProviderLocality = .local

    var isReady: Bool { SpeechTranscriber.isAvailable }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard isReady else {
            throw ProviderRoutingError.providerUnavailable(
                "La transcription système n’est pas disponible sur ce Mac"
            )
        }
        let requestedLocale = Locale(
            identifier: UserDefaults.standard.string(
                forKey: Constants.transcriptionLanguageKey
            ) ?? Constants.defaultTranscriptionLanguage
        )
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw ProviderRoutingError.providerUnavailable(
                "La langue \(requestedLocale.identifier) n’est pas disponible localement"
            )
        }

        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [module]
        ) {
            try await request.downloadAndInstall()
        }

        let file = try AVAudioFile(forReading: audioURL)
        let analyzer = SpeechAnalyzer(modules: [module])
        let resultsTask = Task { () throws -> String in
            var fragments: [String] = []
            for try await result in module.results {
                try Task.checkCancellation()
                let fragment = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !fragment.isEmpty {
                    fragments.append(fragment)
                }
            }
            return fragments.joined(separator: " ")
        }

        do {
            let lastSampleTime = try await analyzer.analyzeSequence(from: file)
            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            let text = try await resultsTask.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ProviderRoutingError.providerUnavailable(
                    "La transcription locale n’a produit aucun texte"
                )
            }
            return TranscriptionResult(text: text, averageLogProbability: 0)
        } catch {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}

@available(macOS 26.0, *)
final class FoundationModelsProcessor: TextProcessing {
    let identifier = "foundation-models"
    let modelIdentifier = "apple-system-language-model"
    let locality: ProviderLocality = .local

    static var availability: ProviderAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "Ce Mac n’est pas compatible avec Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence doit être activé")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Le modèle Apple Intelligence n’est pas encore prêt")
        @unknown default:
            return .unavailable(reason: "Le modèle Apple Intelligence est indisponible")
        }
    }

    func process(_ request: TextProcessingRequest) async throws -> TextProcessingResult {
        guard Self.availability == .available else {
            if case .unavailable(let reason) = Self.availability {
                throw ProviderRoutingError.providerUnavailable(reason)
            }
            throw ProviderRoutingError.localProviderUnavailable
        }

        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        let session = LanguageModelSession(
            model: model,
            instructions: OpenAITextProcessingService.instructions(
                for: request.mode
            )
        )
        let response = try await session.respond(
            to: OpenAITextProcessingService.input(
                text: request.text,
                mode: request.mode,
                context: request.context.restricted(
                    to: request.mode.allowedContextSources
                )
            )
        )
        let text = response.content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else {
            throw ProviderRoutingError.providerUnavailable(
                "Le modèle local n’a produit aucun texte"
            )
        }
        return TextProcessingResult(
            text: text,
            providerIdentifier: identifier
        )
    }
}

enum SystemProviderRegistry {
    static func transcriptionRegistrations(
        openAI: any SpeechTranscribing
    ) -> [(ProviderDescriptor, any SpeechTranscribing)] {
        var registrations: [(ProviderDescriptor, any SpeechTranscribing)] = [
            (
                ProviderDescriptor(
                    id: openAI.identifier,
                    displayName: "OpenAI",
                    locality: .cloud,
                    supportedLocales: ["fr", "en"],
                    // Keep startup non-blocking; the provider's `isReady`
                    // value is evaluated at the time of use.
                    availability: .available
                ),
                openAI
            )
        ]
        if #available(macOS 26.0, *) {
            let provider = SpeechAnalyzerTranscriptionProvider()
            registrations.append(
                (
                    ProviderDescriptor(
                        id: provider.identifier,
                        displayName: "Transcription Apple",
                        locality: .local,
                        supportedLocales: ["fr", "en"],
                        availability: provider.isReady
                            ? .available
                            : .unavailable(
                                reason: "La transcription système est indisponible"
                            )
                    ),
                    provider
                )
            )
        }
        return registrations
    }

    static func processingRegistrations(
        openAI: any TextProcessing
    ) -> [(ProviderDescriptor, any TextProcessing)] {
        var registrations: [(ProviderDescriptor, any TextProcessing)] = [
            (
                ProviderDescriptor(
                    id: openAI.identifier,
                    displayName: "OpenAI Responses",
                    locality: .cloud,
                    supportedLocales: ["fr", "en"],
                    availability: .available
                ),
                openAI
            )
        ]
        if #available(macOS 26.0, *) {
            let provider = FoundationModelsProcessor()
            registrations.append(
                (
                    ProviderDescriptor(
                        id: provider.identifier,
                        displayName: "Apple Intelligence",
                        locality: .local,
                        supportedLocales: ["fr", "en"],
                        availability: FoundationModelsProcessor.availability
                    ),
                    provider
                )
            )
        }
        return registrations
    }
}
