import Foundation

enum DistributionChannel: String, CaseIterable, Sendable {
    case direct
    case appStore

    static var current: DistributionChannel {
#if APP_STORE
        .appStore
#else
        .direct
#endif
    }

    var displayName: String {
        switch self {
        case .direct:
            "Pressay"
        case .appStore:
            "Pressay Companion"
        }
    }

    var supportsAccessibility: Bool { self == .direct }
    var supportsUniversalInsertion: Bool { self == .direct }
    var supportsSelectionTransformation: Bool { self == .direct }
    var supportsGlobalShortcuts: Bool { self == .direct }
    var supportsApplicationProfiles: Bool { self == .direct }
    var usesSparkle: Bool { self == .direct }

    var deliveryDescription: String {
        switch self {
        case .direct:
            "Le résultat est inséré dans le champ capturé au début de la dictée."
        case .appStore:
            "Le résultat est copié dans le presse-papiers ; la Voice Inbox peut le conserver si vous l’activez."
        }
    }
}
