import Foundation

enum Constants {
    static let keychainService = "com.hyrak.whisper"
    static let keychainAPIKeyAccount = "openai-api-key"
    static let openAITranscriptionURL = "https://api.openai.com/v1/audio/transcriptions"
    static let openAIModel = "gpt-4o-mini-transcribe"

    static let transcriptionLanguageKey = "transcription-language"
    static let technicalVocabularyKey = "technical-vocabulary"
    static let defaultTranscriptionLanguage = "fr"
    static let defaultTechnicalVocabulary = """
    API, SDK, GitHub, TypeScript, JavaScript, React, Node.js, Python, Claude, GPT, LLM, MCP, STT, TTS, Whisper, OpenAI, Anthropic, Convex, Vercel, Next.js, SwiftUI, Xcode, iOS, macOS
    """

    // Le son de démarrage peut être capté par le micro. On ignore sa courte fenêtre,
    // puis on exige plusieurs échantillons vocaux avant d'appeler l'API.
    static let audioMeteringInterval: TimeInterval = 0.05
    static let ignoredLeadingAudioDuration: TimeInterval = 0.35
    static let minimumRecordingDuration: TimeInterval = 0.45
    static let minimumVoicedDuration: TimeInterval = 0.15
    static let speechPowerThreshold: Float = -48
}
