import Foundation

enum MetricStep: String, CaseIterable {
    case capture
    case transcription
    case insertion
    case total

    var label: String {
        switch self {
        case .capture: return "Capture"
        case .transcription: return "API"
        case .insertion: return "Insertion"
        case .total: return "Total"
        }
    }
}

final class PerformanceMetricsService: ObservableObject {
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
