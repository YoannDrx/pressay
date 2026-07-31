import Foundation

struct CapturedAudio {
    let url: URL
    let duration: TimeInterval
    let detection: SpeechDetectionResult

    var containsSpeech: Bool { detection.containsSpeech }
}

protocol AudioCapturing: AnyObject {
    var hasPermission: Bool { get }
    var onLevelUpdate: ((Float) -> Void)? { get set }
    func startRecording() throws
    func stopRecording() -> CapturedAudio?
    func cleanupCurrentRecording()
    func cleanup(url: URL)
}

protocol SpeechTranscribing: AnyObject {
    var identifier: String { get }
    var isReady: Bool { get }
    var locality: ProviderLocality { get }
    func transcribe(audioURL: URL) async throws -> TranscriptionResult
}

extension SpeechTranscribing {
    var locality: ProviderLocality { .cloud }
}

struct TextProcessingRequest {
    let text: String
    let mode: ModeDefinition
    let context: ContextSnapshot
}

struct TextProcessingResult: Equatable {
    let text: String
    let providerIdentifier: String
}

protocol TextProcessing: AnyObject {
    var identifier: String { get }
    var modelIdentifier: String { get }
    var locality: ProviderLocality { get }
    func process(_ request: TextProcessingRequest) async throws -> TextProcessingResult
}

extension TextProcessing {
    var modelIdentifier: String { identifier }
    var locality: ProviderLocality { .cloud }
}

protocol CloudConsentRequesting: AnyObject {
    func requestConsent(
        for preflight: CloudPreflight,
        allowsRawTranscription: Bool,
        requiresExplicitChoice: Bool
    ) async -> CloudConsentDecision
}

struct ContextCaptureResult {
    let target: TextInjectionTarget?
    let context: ContextSnapshot
}

@MainActor
protocol ContextCapturing: AnyObject {
    func capture() -> ContextCaptureResult
    func captureSelectionFallback(
        from initialCapture: ContextCaptureResult
    ) async -> ContextCaptureResult
}

extension ContextCapturing {
    func captureSelectionFallback(
        from initialCapture: ContextCaptureResult
    ) async -> ContextCaptureResult {
        initialCapture
    }
}

@MainActor
protocol ModeResolving: AnyObject {
    func resolveMode(
        explicitModeID: UUID?,
        applicationBundleIdentifier: String?,
        intent: VoiceIntent
    ) -> ModeDefinition
    func deliveryPolicy(
        for applicationBundleIdentifier: String?
    ) -> ApplicationDeliveryPolicy
    func availableModes() -> [ModeDefinition]
}

extension ModeResolving {
    func deliveryPolicy(
        for applicationBundleIdentifier: String?
    ) -> ApplicationDeliveryPolicy {
        .automatic
    }
    func availableModes() -> [ModeDefinition] { [] }
}

@MainActor
protocol TextPreviewPresenting: AnyObject {
    func show(
        _ preview: TextPreview,
        onApply: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    )
    func hide()
}

@MainActor
protocol TextDelivering: AnyObject {
    var canUndoLastInsertion: Bool { get }
    var lastDeliveryStrategy: DeliveryStrategy { get }
    var lastDeliveryFailure: DeliveryFailureReason? { get }
    func inject(text: String, target: TextInjectionTarget?) async -> Bool
    func copyToPasteboard(_ text: String)
    func undoLastInsertion() -> Bool
    func prepareRecentInsertionForReplacement() -> Bool
}

extension TextDelivering {
    var lastDeliveryStrategy: DeliveryStrategy { .copied }
    var lastDeliveryFailure: DeliveryFailureReason? { nil }
    func prepareRecentInsertionForReplacement() -> Bool { false }
}

enum DeliveryFailureReason: String, Sendable {
    case emptyText
    case missingTarget
    case secureTarget
    case nonEditableTarget
    case targetApplicationUnavailable
    case targetApplicationNotFrontmost
    case accessibilityNotGranted
    case targetWindowChanged
    case focusedElementUnavailable
    case focusedElementChanged
    case selectionChanged
    case clipboardPasteFailed

    var userMessage: String {
        switch self {
        case .emptyText:
            "aucun texte à insérer"
        case .missingTarget:
            "aucun champ cible n’a été capturé"
        case .secureTarget:
            "le champ cible est protégé"
        case .nonEditableTarget:
            "le champ cible n’est pas éditable"
        case .targetApplicationUnavailable:
            "l’application cible a été fermée"
        case .targetApplicationNotFrontmost:
            "l’application cible n’a pas pu être réactivée"
        case .accessibilityNotGranted:
            "l’autorisation Accessibilité n’est pas reconnue"
        case .targetWindowChanged:
            "la fenêtre cible a changé"
        case .focusedElementUnavailable:
            "le champ cible n’est plus exposé à l’accessibilité"
        case .focusedElementChanged:
            "le champ actif ne correspond plus au champ initial"
        case .selectionChanged:
            "la sélection ou le curseur a changé"
        case .clipboardPasteFailed:
            "macOS a refusé le collage"
        }
    }
}

@MainActor
protocol ReplayBuffer: AnyObject {
    func retain(_ audio: Data, for sessionID: UUID)
    func audio(for sessionID: UUID) -> Data?
    func remove(sessionID: UUID)
    func removeAll()
}

protocol ActionProposing: AnyObject {
    func propose(
        instruction: String,
        context: ContextSnapshot
    ) async throws -> ActionProposal
}

struct ActionExecutionResult: Equatable {
    let proposalID: UUID
    let summary: String
    let didExecute: Bool
}

protocol ActionExecuting: AnyObject {
    func execute(_ proposal: ActionProposal) async throws -> ActionExecutionResult
}

@MainActor
protocol HistoryRepository: AnyObject {
    func append(_ record: HistoryRecord)
}

@MainActor
protocol VoiceInboxRepository: AnyObject {
    func append(_ record: HistoryRecord)
}

struct ModelDescriptor: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let version: String
    let checksum: String
    let downloadSize: Int64
}

enum ProviderLocality: String, Codable, Sendable {
    case local
    case cloud
}

enum ProviderAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case requiresDownload(modelID: String)
}

struct ProviderDescriptor: Equatable, Sendable {
    let id: String
    let displayName: String
    let locality: ProviderLocality
    let supportedLocales: Set<String>
    let availability: ProviderAvailability
}

struct TranscriptionRequest: Sendable {
    let audioURL: URL
    let locale: Locale?
    let vocabulary: [String]
}

protocol TranscriptionRouting: AnyObject {
    func provider(
        for mode: ModeDefinition,
        capabilities: CapabilityMatrix
    ) throws -> any SpeechTranscribing
}

protocol ProcessingRouting: AnyObject {
    func provider(
        for mode: ModeDefinition,
        capabilities: CapabilityMatrix
    ) throws -> any TextProcessing
}

protocol ModelRepository: AnyObject {
    func installedModels() -> [ModelDescriptor]
    func install(_ model: ModelDescriptor) async throws
    func remove(_ model: ModelDescriptor) throws
}

protocol SoundFeedback: AnyObject {
    func playStartSound()
    func playStopSound()
    func playErrorSound()
}

protocol MetricsRecording: AnyObject {
    func record(_ step: MetricStep, duration: TimeInterval)
}

@MainActor
protocol HUDPresenting: AnyObject {
    var onCancel: (() -> Void)? { get set }
    var onUndo: (() -> Void)? { get set }
    var isUndoAvailable: Bool { get set }
    func updateAudioLevel(_ level: Float)
    func show(_ state: HUDState, detail: String?, autoHide: Bool)
    func hide()
    func configureResultActions(
        canRetranscribe: Bool,
        canCompareRawAndFinal: Bool,
        canCorrect: Bool,
        onCopy: @escaping () -> Void,
        onRetranscribe: @escaping () -> Void,
        onCompareRawAndFinal: @escaping () -> Void,
        onCorrect: @escaping () -> Void
    )
    func configureModeSelection(
        currentModeID: UUID,
        options: [HUDModeOption],
        onSelect: @escaping (UUID) -> Void
    )
}

extension HUDPresenting {
    func configureResultActions(
        canRetranscribe: Bool,
        canCompareRawAndFinal: Bool,
        canCorrect: Bool,
        onCopy: @escaping () -> Void,
        onRetranscribe: @escaping () -> Void,
        onCompareRawAndFinal: @escaping () -> Void,
        onCorrect: @escaping () -> Void
    ) {}
    func configureModeSelection(
        currentModeID: UUID,
        options: [HUDModeOption],
        onSelect: @escaping (UUID) -> Void
    ) {}
}
