import Foundation

struct SettingsBackup: Codable {
    let version: Int
    let createdAt: Date
    let radarr: RadarrSettings
    let sonarr: SonarrSettings
    let sabnzb: SabNZBSettings
    let tmdb: TMDBSettings
    let unraid: UnraidSettings?
    let encryptedSecrets: EncryptedBackupSecrets?

    struct RadarrSettings: Codable {
        let url: String
        let apiKey: String?
    }

    struct SonarrSettings: Codable {
        let url: String
        let apiKey: String?
    }

    struct SabNZBSettings: Codable {
        let url: String
        let apiKey: String?
    }

    struct TMDBSettings: Codable {
        let accessToken: String?
    }

    struct UnraidSettings: Codable {
        let url: String
        let apiKey: String?
        let showMediaStackFirst: Bool
        let temperatureUnit: String
    }

    static let currentVersion = 3

    init(
        radarrURL: String,
        sonarrURL: String,
        sabnzbURL: String,
        tmdbAccessToken: String? = nil,
        unraidURL: String = "",
        unraidShowMediaStackFirst: Bool = true,
        unraidTemperatureUnit: String = "celsius",
        radarrAPIKey: String? = nil,
        sonarrAPIKey: String? = nil,
        sabnzbAPIKey: String? = nil,
        unraidAPIKey: String? = nil,
        encryptedSecrets: EncryptedBackupSecrets? = nil
    ) {
        self.version = Self.currentVersion
        self.createdAt = Date()
        self.radarr = RadarrSettings(url: radarrURL, apiKey: radarrAPIKey)
        self.sonarr = SonarrSettings(url: sonarrURL, apiKey: sonarrAPIKey)
        self.sabnzb = SabNZBSettings(url: sabnzbURL, apiKey: sabnzbAPIKey)
        self.tmdb = TMDBSettings(accessToken: tmdbAccessToken)
        self.encryptedSecrets = encryptedSecrets
        if unraidURL.isEmpty && Self.normalizedSecret(unraidAPIKey) == nil {
            self.unraid = nil
        } else {
            self.unraid = UnraidSettings(
                url: unraidURL,
                apiKey: unraidAPIKey,
                showMediaStackFirst: unraidShowMediaStackFirst,
                temperatureUnit: unraidTemperatureUnit
            )
        }
    }

    var requiresPassphrase: Bool {
        encryptedSecrets != nil
    }

    var legacyPlaintextSecrets: StoredCredentials {
        StoredCredentials(
            radarrAPIKey: Self.normalizedSecret(radarr.apiKey),
            sonarrAPIKey: Self.normalizedSecret(sonarr.apiKey),
            sabnzbAPIKey: Self.normalizedSecret(sabnzb.apiKey),
            tmdbAccessToken: Self.normalizedSecret(tmdb.accessToken),
            unraidAPIKey: Self.normalizedSecret(unraid?.apiKey)
        )
    }

    private static func normalizedSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
