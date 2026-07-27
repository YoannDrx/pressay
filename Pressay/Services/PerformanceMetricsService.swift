import Foundation

enum MetricStep: String, CaseIterable {
    case capture
    case transcription
    case processing
    case insertion
    case total

    var label: String {
        switch self {
        case .capture: return "Capture"
        case .transcription: return "Transcription"
        case .processing: return "Traitement"
        case .insertion: return "Insertion"
        case .total: return "Total"
        }
    }
}

struct DiagnosticMetric: Codable, Equatable {
    let count: Int
    let totalSeconds: TimeInterval
    let averageSeconds: TimeInterval?
}

struct DiagnosticPermissions: Codable, Equatable {
    let microphone: Bool
    let accessibility: Bool
}

struct DiagnosticConfiguration: Codable, Equatable {
    let transcriptionLanguage: String
    let transcriptionModel: String
    let processingModel: String
    let activationMode: String
    let historyEnabled: Bool
    let historyRetentionDays: Int
    let metricsEnabled: Bool
    let betaUpdatesEnabled: Bool
    let customModeCount: Int
    let applicationProfileCount: Int
}

struct DiagnosticReport: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let buildNumber: String
    let operatingSystem: String
    let architecture: String
    let permissions: DiagnosticPermissions
    let configuration: DiagnosticConfiguration
    let metrics: [String: DiagnosticMetric]

    static func make(
        metricsService: PerformanceMetricsService,
        permissions: DiagnosticPermissions,
        customModeCount: Int,
        applicationProfileCount: Int,
        betaUpdatesEnabled: Bool,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        now: Date = Date()
    ) -> DiagnosticReport {
        DiagnosticReport(
            schemaVersion: 1,
            generatedAt: now,
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildNumber: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: runtimeArchitecture,
            permissions: permissions,
            configuration: DiagnosticConfiguration(
                transcriptionLanguage: defaults.string(
                    forKey: Constants.transcriptionLanguageKey
                ) ?? Constants.defaultTranscriptionLanguage,
                transcriptionModel: defaults.string(
                    forKey: Constants.transcriptionModelKey
                ) ?? Constants.defaultTranscriptionModel,
                processingModel: defaults.string(
                    forKey: Constants.processingModelKey
                ) ?? Constants.defaultProcessingModel,
                activationMode: defaults.string(
                    forKey: Constants.activationModeKey
                ) ?? ActivationMode.hold.rawValue,
                historyEnabled: boolValue(
                    forKey: Constants.historyEnabledKey,
                    defaultValue: true,
                    defaults: defaults
                ),
                historyRetentionDays: integerValue(
                    forKey: Constants.historyRetentionDaysKey,
                    defaultValue: 1,
                    defaults: defaults
                ),
                metricsEnabled: boolValue(
                    forKey: Constants.metricsEnabledKey,
                    defaultValue: false,
                    defaults: defaults
                ),
                betaUpdatesEnabled: betaUpdatesEnabled,
                customModeCount: customModeCount,
                applicationProfileCount: applicationProfileCount
            ),
            metrics: metricsService.diagnosticSnapshot()
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    private static var runtimeArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func boolValue(
        forKey key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: key) == nil
            ? defaultValue
            : defaults.bool(forKey: key)
    }

    private static func integerValue(
        forKey key: String,
        defaultValue: Int,
        defaults: UserDefaults
    ) -> Int {
        defaults.object(forKey: key) == nil
            ? defaultValue
            : defaults.integer(forKey: key)
    }
}

final class PerformanceMetricsService: ObservableObject, MetricsRecording {
    static let shared = PerformanceMetricsService()

    @Published private(set) var revision = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func record(_ step: MetricStep, duration: TimeInterval) {
        guard defaults.bool(forKey: Constants.metricsEnabledKey), duration >= 0 else { return }
        defaults.set(total(for: step) + duration, forKey: totalKey(step))
        defaults.set(count(for: step) + 1, forKey: countKey(step))
        revision += 1
    }

    func average(for step: MetricStep) -> TimeInterval? {
        let count = count(for: step)
        guard count > 0 else { return nil }
        return total(for: step) / Double(count)
    }

    func reset() {
        for step in MetricStep.allCases {
            defaults.removeObject(forKey: totalKey(step))
            defaults.removeObject(forKey: countKey(step))
        }
        revision += 1
    }

    func diagnosticSnapshot() -> [String: DiagnosticMetric] {
        Dictionary(
            uniqueKeysWithValues: MetricStep.allCases.map { step in
                let metricCount = count(for: step)
                let metricTotal = total(for: step)
                return (
                    step.rawValue,
                    DiagnosticMetric(
                        count: metricCount,
                        totalSeconds: metricTotal,
                        averageSeconds: metricCount > 0
                            ? metricTotal / Double(metricCount)
                            : nil
                    )
                )
            }
        )
    }

    private func total(for step: MetricStep) -> TimeInterval {
        defaults.double(forKey: totalKey(step))
    }

    private func count(for step: MetricStep) -> Int {
        defaults.integer(forKey: countKey(step))
    }

    private func totalKey(_ step: MetricStep) -> String {
        "metric-\(step.rawValue)-total"
    }

    private func countKey(_ step: MetricStep) -> String {
        "metric-\(step.rawValue)-count"
    }
}
