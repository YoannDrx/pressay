import Foundation

enum Constants {
    static let keychainService = "com.hyrak.whisper"
    static let keychainAPIKeyAccount = "openai-api-key"
    static let keychainHistoryKeyAccount = "history-encryption-key"
    static let openAITranscriptionURL = "https://api.openai.com/v1/audio/transcriptions"

    static let transcriptionLanguageKey = "transcription-language"
    static let transcriptionModelKey = "transcription-model"
    static let technicalVocabularyKey = "technical-vocabulary"
    static let vocabularyProfileKey = "vocabulary-profile"
    static let shortcutKey = "dictation-shortcut"
    static let activationModeKey = "dictation-activation-mode"
    static let historyEnabledKey = "history-enabled"
    static let historyRetentionDaysKey = "history-retention-days"
    static let metricsEnabledKey = "local-metrics-enabled"
    static let defaultTranscriptionLanguage = "fr"
    static let defaultTranscriptionModel = "gpt-4o-mini-transcribe"
    static let defaultTechnicalVocabulary = """
    API, SDK, GitHub, TypeScript, JavaScript, React, Node.js, Python, Claude, GPT, LLM, MCP, STT, TTS, Whisper, OpenAI, Anthropic, Convex, Vercel, Next.js, SwiftUI, Xcode, iOS, macOS
    """
    static let generalVocabulary = ""

    // Le son de démarrage peut être capté par le micro. Les premiers échantillons
    // sont ignorés, puis le seuil est calibré sur le bruit propre à la dictée.
    static let audioMeteringInterval: TimeInterval = 0.05
    static let ignoredLeadingAudioDuration: TimeInterval = 0.35
    static let minimumRecordingDuration: TimeInterval = 0.45
    static let minimumVoicedDuration: TimeInterval = 0.15
    static let minimumAdaptiveThreshold: Float = -50
    static let maximumAdaptiveThreshold: Float = -32
    static let noiseMargin: Float = 10
    static let lowConfidenceLogProbability = -0.85
}

enum TranscriptionModel: String, CaseIterable, Identifiable {
    case fast = "gpt-4o-mini-transcribe"
    case accurate = "gpt-4o-transcribe"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fast: return "Rapide"
        case .accurate: return "Précision maximale"
        }
    }
}

enum DictationShortcut: String, CaseIterable, Identifiable {
    case function
    case rightOption
    case rightCommand

    var id: String { rawValue }
    var label: String {
        switch self {
        case .function: return "Fn / Globe"
        case .rightOption: return "⌥ droite"
        case .rightCommand: return "⌘ droite"
        }
    }
}

enum ActivationMode: String, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }
    var label: String {
        switch self {
        case .hold: return "Maintenir"
        case .toggle: return "Bascule"
        }
    }
}
