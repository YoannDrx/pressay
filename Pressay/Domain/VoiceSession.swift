import CryptoKit
import Foundation

enum SelectionFingerprint {
    static func hash(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum VoiceIntent: String, Codable, CaseIterable, Sendable {
    case dictate
    case transformSelection
    case proposeAction
    case captureInbox
    case meeting
}

enum SessionState: Equatable, Sendable {
    case idle
    case capturing
    case captured
    case transcribing
    case processing
    case awaitingPreview
    case awaitingConfirmation
    case delivering
    case completed
    case cancelled
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        default:
            return false
        }
    }
}

enum SessionTransitionPolicy {
    static func allows(from: SessionState, to: SessionState) -> Bool {
        if from.isTerminal {
            return false
        }
        if case .failed = to {
            return true
        }
        if to == .cancelled {
            return true
        }

        switch (from, to) {
        case (.idle, .capturing),
             (.capturing, .captured),
             (.captured, .transcribing),
             (.transcribing, .processing),
             (.processing, .awaitingPreview),
             (.processing, .awaitingConfirmation),
             (.processing, .delivering),
             (.processing, .completed),
             (.awaitingPreview, .delivering),
             (.awaitingConfirmation, .processing),
             (.awaitingConfirmation, .delivering),
             (.delivering, .completed):
            return true
        default:
            return false
        }
    }
}

struct TargetSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let applicationName: String?
    let windowTitle: String?
    let windowIdentifier: String?
    let elementRole: String?
    let elementSubrole: String?
    let selectedTextHash: String?
    let selectionLocation: Int?
    let selectionLength: Int?
    let canReadSelectedText: Bool
    let canWriteSelectedText: Bool
    let canWriteValue: Bool
    let isSecure: Bool
    let isEditable: Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        applicationName: String?,
        windowTitle: String?,
        windowIdentifier: String? = nil,
        elementRole: String?,
        elementSubrole: String?,
        selectedTextHash: String?,
        selectionLocation: Int? = nil,
        selectionLength: Int? = nil,
        canReadSelectedText: Bool = false,
        canWriteSelectedText: Bool = false,
        canWriteValue: Bool = false,
        isSecure: Bool,
        isEditable: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.windowIdentifier = windowIdentifier
        self.elementRole = elementRole
        self.elementSubrole = elementSubrole
        self.selectedTextHash = selectedTextHash
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.canReadSelectedText = canReadSelectedText
        self.canWriteSelectedText = canWriteSelectedText
        self.canWriteValue = canWriteValue
        self.isSecure = isSecure
        self.isEditable = isEditable
    }
}

enum ContextSource: String, Codable, CaseIterable, Sendable {
    case application
    case windowTitle
    case selection
    case surroundingText
    case project
    case clipboard
    case screen
}

struct ContextSnapshot: Equatable, Sendable {
    static let empty = ContextSnapshot()

    var applicationBundleIdentifier: String?
    var applicationName: String?
    var windowTitle: String?
    var selectedText: String?
    var textBeforeSelection: String?
    var textAfterSelection: String?
    var projectIdentifier: UUID?
    var sources: Set<ContextSource>
    var capturedAt: Date

    init(
        applicationBundleIdentifier: String? = nil,
        applicationName: String? = nil,
        windowTitle: String? = nil,
        selectedText: String? = nil,
        textBeforeSelection: String? = nil,
        textAfterSelection: String? = nil,
        projectIdentifier: UUID? = nil,
        sources: Set<ContextSource> = [],
        capturedAt: Date = Date()
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.selectedText = selectedText
        self.textBeforeSelection = textBeforeSelection
        self.textAfterSelection = textAfterSelection
        self.projectIdentifier = projectIdentifier
        self.sources = sources
        self.capturedAt = capturedAt
    }

    var cloudManifest: [String] {
        sources.map(\.rawValue).sorted()
    }

    func restricted(to allowedSources: Set<ContextSource>) -> ContextSnapshot {
        ContextSnapshot(
            applicationBundleIdentifier: allowedSources.contains(.application)
                ? applicationBundleIdentifier
                : nil,
            applicationName: allowedSources.contains(.application)
                ? applicationName
                : nil,
            windowTitle: allowedSources.contains(.windowTitle) ? windowTitle : nil,
            selectedText: allowedSources.contains(.selection) ? selectedText : nil,
            textBeforeSelection: allowedSources.contains(.surroundingText)
                ? textBeforeSelection
                : nil,
            textAfterSelection: allowedSources.contains(.surroundingText)
                ? textAfterSelection
                : nil,
            projectIdentifier: allowedSources.contains(.project) ? projectIdentifier : nil,
            sources: sources.intersection(allowedSources),
            capturedAt: capturedAt
        )
    }
}

enum ProviderPolicy: String, Codable, CaseIterable, Sendable {
    case localOnly
    case preferLocal
    case askBeforeCloud
    case cloudAllowed
}

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)
    static let function = ShortcutModifiers(rawValue: 1 << 4)
}

enum ModifierSide: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

struct ShortcutDefinition: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: ShortcutModifiers
    var side: ModifierSide?
}

struct ModeOverrides: Codable, Equatable, Sendable {
    var shortcut: ShortcutDefinition?
    var providerPolicy: ProviderPolicy?
}

enum ProfileSource: String, Codable, CaseIterable, Sendable {
    case suggested
    case manual
    case migrated
}

struct ApplicationProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let bundleIdentifier: String
    var modeID: UUID
    let source: ProfileSource
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        modeID: UUID,
        source: ProfileSource,
        isEnabled: Bool
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.modeID = modeID
        self.source = source
        self.isEnabled = isEnabled
    }
}

enum CleaningLevel: String, Codable, CaseIterable, Sendable {
    case faithful
    case light
    case rewrite
    case generate
}

enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case plainText
    case markdown
    case code
    case structured
}

struct ModeDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var symbolName: String
    var intent: VoiceIntent
    var transcriptionLanguage: String?
    var cleaningLevel: CleaningLevel
    var prompt: String
    var examples: [String]
    var outputFormat: OutputFormat
    var providerPolicy: ProviderPolicy
    private var orderedContextSources: [ContextSource]
    var shortcut: ShortcutDefinition?
    var transcriptionProviderID: String?
    var processingProviderID: String?
    var isEnabled: Bool

    var allowedContextSources: Set<ContextSource> {
        get { Set(orderedContextSources) }
        set {
            let retained = orderedContextSources.filter(newValue.contains)
            let added = ContextSource.allCases.filter {
                newValue.contains($0) && !retained.contains($0)
            }
            orderedContextSources = retained + added
        }
    }

    var contextSources: [ContextSource] {
        orderedContextSources
    }

    @available(*, deprecated, renamed: "transcriptionLanguage")
    var language: String? {
        get { transcriptionLanguage }
        set { transcriptionLanguage = newValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        intent: VoiceIntent = .dictate,
        transcriptionLanguage: String? = nil,
        cleaningLevel: CleaningLevel = .faithful,
        prompt: String = "",
        examples: [String] = [],
        outputFormat: OutputFormat = .plainText,
        providerPolicy: ProviderPolicy = .cloudAllowed,
        allowedContextSources: Set<ContextSource> = [.application],
        shortcut: ShortcutDefinition? = nil,
        transcriptionProviderID: String? = nil,
        processingProviderID: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.intent = intent
        self.transcriptionLanguage = transcriptionLanguage
        self.cleaningLevel = cleaningLevel
        self.prompt = prompt
        self.examples = examples
        self.outputFormat = outputFormat
        self.providerPolicy = providerPolicy
        self.orderedContextSources = ContextSource.allCases.filter(
            allowedContextSources.contains
        )
        self.shortcut = shortcut
        self.transcriptionProviderID = transcriptionProviderID
        self.processingProviderID = processingProviderID
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbolName
        case intent
        case transcriptionLanguage
        case language
        case cleaningLevel
        case prompt
        case examples
        case outputFormat
        case providerPolicy
        case contextSources
        case allowedContextSources
        case shortcut
        case transcriptionProviderID
        case processingProviderID
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        intent = try container.decodeIfPresent(VoiceIntent.self, forKey: .intent)
            ?? .dictate
        transcriptionLanguage = try container.decodeIfPresent(
            String.self,
            forKey: .transcriptionLanguage
        ) ?? container.decodeIfPresent(String.self, forKey: .language)
        cleaningLevel = try container.decodeIfPresent(
            CleaningLevel.self,
            forKey: .cleaningLevel
        ) ?? .faithful
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        examples = try container.decodeIfPresent(
            [String].self,
            forKey: .examples
        ) ?? []
        outputFormat = try container.decodeIfPresent(
            OutputFormat.self,
            forKey: .outputFormat
        ) ?? .plainText
        providerPolicy = try container.decodeIfPresent(
            ProviderPolicy.self,
            forKey: .providerPolicy
        ) ?? .askBeforeCloud
        if let sources = try container.decodeIfPresent(
            [ContextSource].self,
            forKey: .contextSources
        ) {
            orderedContextSources = sources.removingDuplicates()
        } else {
            let legacySources = try container.decodeIfPresent(
                Set<ContextSource>.self,
                forKey: .allowedContextSources
            ) ?? [.application]
            orderedContextSources = ContextSource.allCases.filter(
                legacySources.contains
            )
        }
        shortcut = try container.decodeIfPresent(
            ShortcutDefinition.self,
            forKey: .shortcut
        )
        transcriptionProviderID = try container.decodeIfPresent(
            String.self,
            forKey: .transcriptionProviderID
        )
        processingProviderID = try container.decodeIfPresent(
            String.self,
            forKey: .processingProviderID
        )
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(intent, forKey: .intent)
        try container.encodeIfPresent(
            transcriptionLanguage,
            forKey: .transcriptionLanguage
        )
        try container.encode(cleaningLevel, forKey: .cleaningLevel)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(examples, forKey: .examples)
        try container.encode(outputFormat, forKey: .outputFormat)
        try container.encode(providerPolicy, forKey: .providerPolicy)
        try container.encode(orderedContextSources, forKey: .contextSources)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encodeIfPresent(
            transcriptionProviderID,
            forKey: .transcriptionProviderID
        )
        try container.encodeIfPresent(
            processingProviderID,
            forKey: .processingProviderID
        )
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

struct CloudPreflight: Sendable, Equatable {
    let sessionID: UUID
    let modeID: UUID
    let providerID: String
    let modelID: String
    let spokenText: String
    let sources: [ContextSource]
    let characterCounts: [ContextSource: Int]
    let exactPayloadPreview: [ContextSource: String]

    var consentSignature: String {
        let parts = [
            modeID.uuidString,
            providerID,
            modelID,
            sources.map(\.rawValue).joined(separator: ",")
        ]
        return SelectionFingerprint.hash(parts.joined(separator: "|")) ?? ""
    }
}

enum CloudConsentDecision: Equatable, Sendable {
    case sendOnce
    case alwaysAllowMode
    case useRawTranscription
    case cancel
}

enum DeliveryStrategy: String, Codable, Sendable {
    case accessibilityReplacement
    case paste
    case copied
}

struct DeliveryReceipt: Sendable, Equatable {
    let sessionID: UUID
    let strategy: DeliveryStrategy
    let originalText: String?
    let rawText: String
    let finalText: String
    let undoDeadline: Date?
}

enum ActionRisk: String, Codable, CaseIterable, Sendable {
    case automatic
    case preview
    case confirmationRequired
    case forbidden
}

enum ActionKind: String, Codable, CaseIterable, Sendable {
    case copyText
    case openApplication
    case openURL
    case revealFile
    case createNoteDraft
    case createReminderDraft
    case createCalendarDraft
    case writeAuthorizedFile
    case prepareShortcut
    case prepareTerminalCommand
    case createRemoteResource
}

struct ActionProposal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ActionKind
    var parameters: [String: String]
    var summary: String
    var risk: ActionRisk
    var preconditions: [String]
    var idempotencyKey: String
    var preview: String?

    init(
        id: UUID = UUID(),
        kind: ActionKind,
        parameters: [String: String] = [:],
        summary: String,
        risk: ActionRisk,
        preconditions: [String] = [],
        idempotencyKey: String = UUID().uuidString,
        preview: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.parameters = parameters
        self.summary = summary
        self.risk = risk
        self.preconditions = preconditions
        self.idempotencyKey = idempotencyKey
        self.preview = preview
    }
}

enum DeliveryStatus: String, Codable, Sendable {
    case notRequested
    case inserted
    case copied
    case proposed
    case failed
}

struct HistoryRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let createdAt: Date
    var rawText: String
    var finalText: String
    var applicationBundleIdentifier: String?
    var modeIdentifier: UUID?
    var transcriptionProvider: String
    var processingProvider: String?
    var language: String?
    var audioDuration: TimeInterval
    var contextManifest: [String]
    var deliveryStatus: DeliveryStatus
    var actionProposal: ActionProposal?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        createdAt: Date = Date(),
        rawText: String,
        finalText: String,
        applicationBundleIdentifier: String? = nil,
        modeIdentifier: UUID? = nil,
        transcriptionProvider: String,
        processingProvider: String? = nil,
        language: String? = nil,
        audioDuration: TimeInterval,
        contextManifest: [String] = [],
        deliveryStatus: DeliveryStatus,
        actionProposal: ActionProposal? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.rawText = rawText
        self.finalText = finalText
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.modeIdentifier = modeIdentifier
        self.transcriptionProvider = transcriptionProvider
        self.processingProvider = processingProvider
        self.language = language
        self.audioDuration = audioDuration
        self.contextManifest = contextManifest
        self.deliveryStatus = deliveryStatus
        self.actionProposal = actionProposal
    }
}

struct SessionTimings: Equatable, Sendable {
    var createdAt: Date
    var captureStartedAt: Date?
    var captureEndedAt: Date?
    var transcriptionStartedAt: Date?
    var transcriptionEndedAt: Date?
    var processingEndedAt: Date?
    var deliveryEndedAt: Date?

    init(createdAt: Date = Date()) {
        self.createdAt = createdAt
    }
}

struct VoiceSession: Identifiable, Equatable, Sendable {
    let id: UUID
    var intent: VoiceIntent
    var state: SessionState
    var target: TargetSnapshot?
    var context: ContextSnapshot
    var modeIdentifier: UUID?
    var audioURL: URL?
    var audioDuration: TimeInterval?
    var rawText: String?
    var finalText: String?
    var actionProposal: ActionProposal?
    var timings: SessionTimings

    init(
        id: UUID = UUID(),
        intent: VoiceIntent,
        state: SessionState = .idle,
        target: TargetSnapshot? = nil,
        context: ContextSnapshot = .empty,
        modeIdentifier: UUID? = nil,
        timings: SessionTimings = SessionTimings()
    ) {
        self.id = id
        self.intent = intent
        self.state = state
        self.target = target
        self.context = context
        self.modeIdentifier = modeIdentifier
        self.timings = timings
    }

    @discardableResult
    mutating func transition(to newState: SessionState) -> Bool {
        guard SessionTransitionPolicy.allows(from: state, to: newState) else {
            return false
        }
        state = newState
        return true
    }
}

struct TextPreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let originalText: String
    var proposedText: String
    let modeName: String
    let providerIdentifier: String
    let contextManifest: [String]
    let isReadOnly: Bool

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        originalText: String,
        proposedText: String,
        modeName: String,
        providerIdentifier: String,
        contextManifest: [String],
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.originalText = originalText
        self.proposedText = proposedText
        self.modeName = modeName
        self.providerIdentifier = providerIdentifier
        self.contextManifest = contextManifest
        self.isReadOnly = isReadOnly
    }
}

struct CapabilityMatrix: Equatable, Sendable {
    let operatingSystem: OperatingSystemVersion
    let isAppleSilicon: Bool
    let supportsSystemSpeechAnalyzer: Bool
    let supportsFoundationModels: Bool
    let installedTranscriptionProviders: Set<String>
    let installedProcessingProviders: Set<String>
    let grantedPermissions: Set<String>

    static var current: CapabilityMatrix {
#if arch(arm64)
        let isAppleSilicon = true
#else
        let isAppleSilicon = false
#endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return CapabilityMatrix(
            operatingSystem: version,
            isAppleSilicon: isAppleSilicon,
            supportsSystemSpeechAnalyzer: version.majorVersion >= 26,
            supportsFoundationModels: version.majorVersion >= 26 && isAppleSilicon,
            installedTranscriptionProviders: ["openai"],
            installedProcessingProviders: ["openai-responses"],
            grantedPermissions: []
        )
    }

    static func == (lhs: CapabilityMatrix, rhs: CapabilityMatrix) -> Bool {
        lhs.operatingSystem.majorVersion == rhs.operatingSystem.majorVersion
            && lhs.operatingSystem.minorVersion == rhs.operatingSystem.minorVersion
            && lhs.operatingSystem.patchVersion == rhs.operatingSystem.patchVersion
            && lhs.isAppleSilicon == rhs.isAppleSilicon
            && lhs.supportsSystemSpeechAnalyzer == rhs.supportsSystemSpeechAnalyzer
            && lhs.supportsFoundationModels == rhs.supportsFoundationModels
            && lhs.installedTranscriptionProviders == rhs.installedTranscriptionProviders
            && lhs.installedProcessingProviders == rhs.installedProcessingProviders
            && lhs.grantedPermissions == rhs.grantedPermissions
    }
}
