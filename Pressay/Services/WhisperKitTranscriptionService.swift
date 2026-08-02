import Foundation
import WhisperKit

@MainActor
final class WhisperKitTranscriptionService: ObservableObject, @preconcurrency SpeechTranscribing {
    static let shared = WhisperKitTranscriptionService()

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    enum LocalError: LocalizedError {
        case unsupportedPlatform
        case modelNotDownloaded
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .unsupportedPlatform:
                "WhisperKit local nécessite un Mac Apple Silicon"
            case .modelNotDownloaded:
                "Télécharge d’abord le modèle WhisperKit dans les réglages"
            case .emptyResult:
                "WhisperKit n’a produit aucun texte"
            }
        }
    }

    let identifier = TranscriptionEngine.whisperKit.rawValue
    let locality: ProviderLocality = .local
    static let modelName = "small_216MB"
    static let modelLabel = "Small optimisé · environ 216 Mo"
    static var isSupportedPlatform: Bool {
#if arch(arm64)
        true
#else
        false
#endif
    }

    @Published private(set) var modelState: ModelState

    private var whisperKit: WhisperKit?
    private let defaults: UserDefaults
    private let fileManager: FileManager

    var isReady: Bool { modelState.isReady }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        if Self.isSupportedPlatform {
            self.modelState = Self.validModelFolder(
                defaults: defaults,
                fileManager: fileManager
            ) == nil ? .notDownloaded : .ready
        } else {
            self.modelState = .failed(
                LocalError.unsupportedPlatform.localizedDescription
            )
        }
    }

    func downloadModel() async {
        guard Self.isSupportedPlatform else {
            modelState = .failed(LocalError.unsupportedPlatform.localizedDescription)
            return
        }
        switch modelState {
        case .notDownloaded, .failed:
            break
        case .downloading, .loading, .ready:
            return
        }
        modelState = .downloading(0)
        do {
            let base = try modelDownloadBase()
            let folder = try await WhisperKit.download(
                variant: Self.modelName,
                downloadBase: base,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.modelState = .downloading(progress.fractionCompleted)
                    }
                }
            )
            defaults.set(folder.path, forKey: Constants.whisperKitModelPathKey)
            modelState = .loading
            _ = try await loadModel(from: folder)
            modelState = .ready
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    func removeModel() throws {
        whisperKit = nil
        guard let folder = Self.validModelFolder(
            defaults: defaults,
            fileManager: fileManager
        ) else {
            defaults.removeObject(forKey: Constants.whisperKitModelPathKey)
            modelState = .notDownloaded
            return
        }
        let allowedRoot = try modelDownloadBase().standardizedFileURL
        let candidate = folder.standardizedFileURL
        guard candidate.path.hasPrefix(allowedRoot.path + "/") else {
            defaults.removeObject(forKey: Constants.whisperKitModelPathKey)
            modelState = .notDownloaded
            return
        }
        try fileManager.removeItem(at: candidate)
        defaults.removeObject(forKey: Constants.whisperKitModelPathKey)
        modelState = .notDownloaded
    }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard Self.isSupportedPlatform else {
            throw LocalError.unsupportedPlatform
        }
        guard let folder = Self.validModelFolder(
            defaults: defaults,
            fileManager: fileManager
        ) else {
            modelState = .notDownloaded
            throw LocalError.modelNotDownloaded
        }
        let kit = try await loadModel(from: folder)
        let configuredLanguage = defaults.string(
            forKey: Constants.transcriptionLanguageKey
        ) ?? Constants.defaultTranscriptionLanguage
        let options = DecodingOptions(
            language: configuredLanguage.isEmpty ? nil : configuredLanguage,
            withoutTimestamps: true,
            wordTimestamps: false
        )
        let results = try await kit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        let text = results.map(\.text).joined(separator: " ")
        let validated = try TranscriptionResponseValidator.validated(
            text,
            vocabulary: ""
        )
        guard !validated.isEmpty else { throw LocalError.emptyResult }
        let probabilities = results
            .flatMap(\.segments)
            .map { Double($0.avgLogprob) }
        let average = probabilities.isEmpty
            ? nil
            : probabilities.reduce(0, +) / Double(probabilities.count)
        return TranscriptionResult(
            text: validated,
            averageLogProbability: average
        )
    }

    private func loadModel(from folder: URL) async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        modelState = .loading
        do {
            let kit = try await WhisperKit(
                WhisperKitConfig(
                    model: Self.modelName,
                    modelFolder: folder.path,
                    verbose: false,
                    logLevel: .none,
                    prewarm: false,
                    load: true,
                    download: false
                )
            )
            whisperKit = kit
            modelState = .ready
            return kit
        } catch {
            modelState = .failed(error.localizedDescription)
            throw error
        }
    }

    private func modelDownloadBase() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = support
            .appendingPathComponent(Constants.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("WhisperKit", isDirectory: true)
        try fileManager.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        return base
    }

    private static func validModelFolder(
        defaults: UserDefaults,
        fileManager: FileManager
    ) -> URL? {
        guard let path = defaults.string(forKey: Constants.whisperKitModelPathKey),
              !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
