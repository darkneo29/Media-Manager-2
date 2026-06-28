import Foundation
import UniformTypeIdentifiers

enum BackupError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case invalidBackupFile
    case unsupportedVersion(Int)
    case passphraseRequired
    case invalidPassphrase
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to create backup file"
        case .decodingFailed:
            return "Failed to read backup file"
        case .invalidBackupFile:
            return "The selected file is not a valid backup"
        case .unsupportedVersion(let version):
            return "Backup version \(version) is not supported"
        case .passphraseRequired:
            return "A backup passphrase is required for this operation"
        case .invalidPassphrase:
            return "The backup passphrase is incorrect"
        case .encryptionFailed:
            return "Failed to encrypt or decrypt the backup"
        }
    }
}

class BackupService {
    static let shared = BackupService()
    private let defaults: UserDefaults
    private let credentialStore: CredentialStore
    private let encryptionService: BackupEncryptionService

    init(
        defaults: UserDefaults = .standard,
        credentialStore: CredentialStore = .shared,
        encryptionService: BackupEncryptionService = .shared
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.encryptionService = encryptionService
    }

    static let fileExtension = "mediabackup"
    static let utType = UTType(exportedAs: "com.mediamanager.backup", conformingTo: .json)

    func hasSecretsConfigured() -> Bool {
        credentialStore.snapshot().hasSecrets
    }

    func createBackup(passphrase: String? = nil) throws -> SettingsBackup {
        let secrets = credentialStore.snapshot()
        let encryptedSecrets: EncryptedBackupSecrets?

        if secrets.hasSecrets {
            guard let passphrase, !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.passphraseRequired
            }
            encryptedSecrets = try encryptionService.encrypt(secrets, passphrase: passphrase)
        } else {
            encryptedSecrets = nil
        }

        return SettingsBackup(
            radarrURL: defaults.string(forKey: "radarrURL") ?? "",
            sonarrURL: defaults.string(forKey: "sonarrURL") ?? "",
            sabnzbURL: defaults.string(forKey: "sabnzbURL") ?? "",
            tmdbAccessToken: nil,
            unraidURL: defaults.string(forKey: "unraidURL") ?? "",
            unraidShowMediaStackFirst: defaults.object(forKey: "unraidShowMediaStackFirst") as? Bool ?? true,
            unraidTemperatureUnit: defaults.string(forKey: "unraidTemperatureUnit") ?? "celsius",
            encryptedSecrets: encryptedSecrets
        )
    }

    func encodeBackup(_ backup: SettingsBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(backup)
        } catch {
            throw BackupError.encodingFailed
        }
    }

    func decodeBackup(from data: Data) throws -> SettingsBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let backup = try decoder.decode(SettingsBackup.self, from: data)

            if backup.version > SettingsBackup.currentVersion {
                throw BackupError.unsupportedVersion(backup.version)
            }

            return backup
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.decodingFailed
        }
    }

    func restoreBackup(_ backup: SettingsBackup, passphrase: String? = nil) throws {
        let secrets: StoredCredentials

        if let encryptedSecrets = backup.encryptedSecrets {
            guard let passphrase else {
                throw BackupError.passphraseRequired
            }
            secrets = try encryptionService.decrypt(encryptedSecrets, passphrase: passphrase)
        } else {
            secrets = backup.legacyPlaintextSecrets
        }

        defaults.set(ConfigurationManager.normalizedServerURL(backup.radarr.url), forKey: "radarrURL")
        defaults.set(ConfigurationManager.normalizedServerURL(backup.sonarr.url), forKey: "sonarrURL")
        defaults.set(ConfigurationManager.normalizedServerURL(backup.sabnzb.url), forKey: "sabnzbURL")

        if let unraid = backup.unraid {
            defaults.set(ConfigurationManager.normalizedServerURL(unraid.url), forKey: "unraidURL")
            defaults.set(unraid.showMediaStackFirst, forKey: "unraidShowMediaStackFirst")
            defaults.set(unraid.temperatureUnit, forKey: "unraidTemperatureUnit")
        } else {
            defaults.set("", forKey: "unraidURL")
            defaults.set(true, forKey: "unraidShowMediaStackFirst")
            defaults.set("celsius", forKey: "unraidTemperatureUnit")
        }

        try credentialStore.set(secrets.radarrAPIKey ?? "", for: .radarrAPIKey)
        try credentialStore.set(secrets.sonarrAPIKey ?? "", for: .sonarrAPIKey)
        try credentialStore.set(secrets.sabnzbAPIKey ?? "", for: .sabnzbAPIKey)
        try credentialStore.set(secrets.tmdbAccessToken ?? "", for: .tmdbAccessToken)
        try credentialStore.set(secrets.unraidAPIKey ?? "", for: .unraidAPIKey)

        Task { @MainActor in
            ConfigurationManager.shared.refreshConfiguration(invalidateCaches: true)
        }
    }

    func backupRequiresPassphrase(_ backup: SettingsBackup) -> Bool {
        backup.requiresPassphrase
    }

    func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = formatter.string(from: Date())
        return "MediaManager_Backup_\(dateString).\(Self.fileExtension)"
    }
}
