import Foundation

enum ProviderRoutingError: LocalizedError, Equatable {
    case providerNotFound(String)
    case providerUnavailable(String)
    case localProviderUnavailable
    case cloudProviderUnavailable

    var errorDescription: String? {
        switch self {
        case .providerNotFound(let identifier):
            "Fournisseur inconnu : \(identifier)"
        case .providerUnavailable(let reason):
            reason
        case .localProviderUnavailable:
            "Le modèle WhisperKit local n’est pas prêt"
        case .cloudProviderUnavailable:
            "OpenAI n’est pas configuré"
        }
    }
}

final class TranscriptionRouter: TranscriptionRouting {
    private struct Registration {
        let descriptor: ProviderDescriptor
        let provider: any SpeechTranscribing
    }

    private let registrations: [String: Registration]
    private let openAIProviderID: String
    private let localProviderID: String
    private let defaults: UserDefaults

    init(
        registrations: [(ProviderDescriptor, any SpeechTranscribing)],
        automaticCloudProviderID: String = TranscriptionEngine.openAI.rawValue,
        automaticLocalProviderIDs: [String] = [TranscriptionEngine.whisperKit.rawValue],
        defaults: UserDefaults = .standard
    ) {
        self.registrations = Dictionary(
            uniqueKeysWithValues: registrations.map {
                ($0.0.id, Registration(descriptor: $0.0, provider: $0.1))
            }
        )
        self.openAIProviderID = automaticCloudProviderID
        self.localProviderID = automaticLocalProviderIDs.first
            ?? TranscriptionEngine.whisperKit.rawValue
        self.defaults = defaults
    }

    convenience init(
        openAI: any SpeechTranscribing,
        whisperKit: any SpeechTranscribing
    ) {
        self.init(
            registrations: SystemProviderRegistry.transcriptionRegistrations(
                openAI: openAI,
                whisperKit: whisperKit
            ),
            automaticCloudProviderID: openAI.identifier,
            automaticLocalProviderIDs: [whisperKit.identifier]
        )
    }

    func provider(
        for mode: ModeDefinition,
        capabilities: CapabilityMatrix
    ) throws -> any SpeechTranscribing {
        if mode.providerPolicy == .localOnly {
            return try availableProvider(identifier: localProviderID)
        }

        let engine = TranscriptionEngine(
            rawValue: defaults.string(forKey: Constants.transcriptionEngineKey) ?? ""
        ) ?? .openAI
        switch engine {
        case .openAI:
            return try availableProvider(identifier: openAIProviderID)
        case .whisperKit:
            return try availableProvider(identifier: localProviderID)
        }
    }

    private func availableProvider(
        identifier: String
    ) throws -> any SpeechTranscribing {
        guard let registration = registrations[identifier] else {
            throw ProviderRoutingError.providerNotFound(identifier)
        }
        switch registration.descriptor.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ProviderRoutingError.providerUnavailable(reason)
        case .requiresDownload:
            throw ProviderRoutingError.localProviderUnavailable
        }
        guard registration.provider.isReady else {
            throw registration.provider.locality == .local
                ? ProviderRoutingError.localProviderUnavailable
                : ProviderRoutingError.cloudProviderUnavailable
        }
        return registration.provider
    }
}

final class ProcessingRouter: ProcessingRouting {
    private struct Registration {
        let descriptor: ProviderDescriptor
        let provider: any TextProcessing
    }

    private let registrations: [String: Registration]
    private let openAIProviderID: String

    init(
        registrations: [(ProviderDescriptor, any TextProcessing)],
        automaticCloudProviderID: String = "openai-responses",
        automaticLocalProviderIDs: [String] = []
    ) {
        self.registrations = Dictionary(
            uniqueKeysWithValues: registrations.map {
                ($0.0.id, Registration(descriptor: $0.0, provider: $0.1))
            }
        )
        self.openAIProviderID = automaticCloudProviderID
    }

    convenience init(openAI: any TextProcessing) {
        self.init(
            registrations: SystemProviderRegistry.processingRegistrations(
                openAI: openAI
            ),
            automaticCloudProviderID: openAI.identifier
        )
    }

    func provider(
        for mode: ModeDefinition,
        capabilities: CapabilityMatrix
    ) throws -> any TextProcessing {
        guard mode.providerPolicy != .localOnly else {
            throw ProviderRoutingError.localProviderUnavailable
        }
        guard let registration = registrations[openAIProviderID] else {
            throw ProviderRoutingError.cloudProviderUnavailable
        }
        switch registration.descriptor.availability {
        case .available:
            break
        case .unavailable, .requiresDownload:
            throw ProviderRoutingError.cloudProviderUnavailable
        }
        return registration.provider
    }
}

enum SystemProviderRegistry {
    static func transcriptionRegistrations(
        openAI: any SpeechTranscribing,
        whisperKit: any SpeechTranscribing
    ) -> [(ProviderDescriptor, any SpeechTranscribing)] {
        [
            (
                ProviderDescriptor(
                    id: openAI.identifier,
                    displayName: "OpenAI",
                    locality: .cloud,
                    supportedLocales: ["fr", "en"],
                    availability: .available
                ),
                openAI
            ),
            (
                ProviderDescriptor(
                    id: whisperKit.identifier,
                    displayName: "WhisperKit local",
                    locality: .local,
                    supportedLocales: ["fr", "en"],
                    availability: .available
                ),
                whisperKit
            )
        ]
    }

    static func processingRegistrations(
        openAI: any TextProcessing
    ) -> [(ProviderDescriptor, any TextProcessing)] {
        [
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
    }
}
