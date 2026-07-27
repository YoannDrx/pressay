import Foundation

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
                        availability: openAI.isReady
                            ? .available
                            : .unavailable(reason: "Clé API non configurée")
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
