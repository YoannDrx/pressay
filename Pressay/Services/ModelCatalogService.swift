import CryptoKit
import Foundation

struct ModelCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let models: [CatalogModel]
    let signature: String

    struct UnsignedPayload: Codable {
        let schemaVersion: Int
        let generatedAt: Date
        let models: [CatalogModel]
    }

    var unsignedPayload: UnsignedPayload {
        UnsignedPayload(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            models: models
        )
    }
}

struct CatalogModel: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case transcription
        case processing
    }

    let id: String
    let kind: Kind
    let engine: String
    let version: String
    let architectures: [String]
    let minimumOS: String
    let locales: [String]
    let downloadSize: Int64
    let installedSize: Int64
    let sha256: String
    let url: URL
    let licenseName: String
    let licenseURL: URL
}

enum ModelCatalogError: LocalizedError, Equatable {
    case unsupportedSchema
    case invalidSignature
    case incompatibleModel
    case insufficientDiskSpace
    case checksumMismatch
    case modelInUse
    case malformedPublicKey

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: return "Version de catalogue non prise en charge"
        case .invalidSignature: return "Signature du catalogue invalide"
        case .incompatibleModel: return "Ce modèle n’est pas compatible avec ce Mac"
        case .insufficientDiskSpace: return "Espace disque insuffisant"
        case .checksumMismatch: return "Le modèle téléchargé ne correspond pas au checksum publié"
        case .modelInUse: return "Ce modèle est utilisé par une session en cours"
        case .malformedPublicKey: return "Clé publique du catalogue invalide"
        }
    }
}

actor ModelCatalogService {
    private let publicKey: Curve25519.Signing.PublicKey
    private let modelsDirectory: URL
    private let session: URLSession
    private var modelsInUse: Set<String> = []

    init(
        publicKeyData: Data,
        modelsDirectory: URL? = nil,
        session: URLSession = .shared
    ) throws {
        do {
            self.publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
            )
        } catch {
            throw ModelCatalogError.malformedPublicKey
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.modelsDirectory = modelsDirectory
            ?? appSupport
                .appendingPathComponent(
                    Constants.applicationSupportDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent("Models", isDirectory: true)
        self.session = session
    }

    func verifiedCatalog(from data: Data) throws -> ModelCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(ModelCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else {
            throw ModelCatalogError.unsupportedSchema
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(catalog.unsignedPayload)
        guard let signature = Data(base64Encoded: catalog.signature),
              publicKey.isValidSignature(signature, for: payload) else {
            throw ModelCatalogError.invalidSignature
        }
        return catalog
    }

    func install(_ model: CatalogModel) async throws -> URL {
        guard isCompatible(model) else {
            throw ModelCatalogError.incompatibleModel
        }
        try ensureDiskSpace(requiredBytes: model.installedSize)
        let (temporaryURL, response) = try await session.download(from: model.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard try sha256(of: temporaryURL) == model.sha256.lowercased() else {
            throw ModelCatalogError.checksumMismatch
        }

        let versionDirectory = modelsDirectory
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.version, isDirectory: true)
        try FileManager.default.createDirectory(
            at: versionDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = versionDirectory.appendingPathComponent(
            model.url.lastPathComponent
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        try pruneOldVersions(of: model, keeping: 2)
        return destination
    }

    func remove(_ model: CatalogModel) throws {
        guard !modelsInUse.contains(model.id) else {
            throw ModelCatalogError.modelInUse
        }
        let directory = modelsDirectory
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.version, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func markInUse(modelID: String, inUse: Bool) {
        if inUse {
            modelsInUse.insert(modelID)
        } else {
            modelsInUse.remove(modelID)
        }
    }

    private func isCompatible(_ model: CatalogModel) -> Bool {
#if arch(arm64)
        let architecture = "arm64"
#else
        let architecture = "x86_64"
#endif
        guard model.architectures.contains(architecture) else { return false }
        let components = model.minimumOS.split(separator: ".").compactMap {
            Int($0)
        }
        let requiredMajor = components.first ?? 0
        let requiredMinor = components.dropFirst().first ?? 0
        let current = ProcessInfo.processInfo.operatingSystemVersion
        return current.majorVersion > requiredMajor
            || (
                current.majorVersion == requiredMajor
                    && current.minorVersion >= requiredMinor
            )
    }

    private func ensureDiskSpace(requiredBytes: Int64) throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try modelsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available > requiredBytes + 512 * 1_024 * 1_024 else {
            throw ModelCatalogError.insufficientDiskSpace
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func pruneOldVersions(
        of model: CatalogModel,
        keeping count: Int
    ) throws {
        let modelDirectory = modelsDirectory.appendingPathComponent(
            model.id,
            isDirectory: true
        )
        let versions = try FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).sorted {
            let left = try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let right = try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return (left ?? .distantPast) > (right ?? .distantPast)
        }
        for oldVersion in versions.dropFirst(count) {
            try FileManager.default.removeItem(at: oldVersion)
        }
    }
}
