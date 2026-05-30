import CommonCrypto
import CryptoKit
import Foundation

struct EncryptedBackupSecrets: Codable, Equatable {
    let salt: Data
    let nonce: Data
    let ciphertext: Data
    let tag: Data
    let iterations: Int
}

final class BackupEncryptionService {
    static let shared = BackupEncryptionService()

    private let saltLength = 16
    private let keyLength = 32
    private let iterations = 100_000

    func encrypt(_ secrets: StoredCredentials, passphrase: String) throws -> EncryptedBackupSecrets {
        let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassphrase.isEmpty else {
            throw BackupError.passphraseRequired
        }

        let salt = randomData(count: saltLength)
        let key = try deriveKey(passphrase: normalizedPassphrase, salt: salt, iterations: iterations, keyLength: keyLength)
        let plaintext = try JSONEncoder().encode(secrets)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        return EncryptedBackupSecrets(
            salt: salt,
            nonce: Data(sealedBox.nonce),
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag,
            iterations: iterations
        )
    }

    func decrypt(_ encryptedSecrets: EncryptedBackupSecrets, passphrase: String) throws -> StoredCredentials {
        let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassphrase.isEmpty else {
            throw BackupError.passphraseRequired
        }

        let key = try deriveKey(
            passphrase: normalizedPassphrase,
            salt: encryptedSecrets.salt,
            iterations: encryptedSecrets.iterations,
            keyLength: keyLength
        )
        let nonce = try AES.GCM.Nonce(data: encryptedSecrets.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedSecrets.ciphertext,
            tag: encryptedSecrets.tag
        )

        do {
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return try JSONDecoder().decode(StoredCredentials.self, from: decryptedData)
        } catch {
            throw BackupError.invalidPassphrase
        }
    }

    private func deriveKey(
        passphrase: String,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) throws -> SymmetricKey {
        var derivedKeyData = Data(count: keyLength)
        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passphrase.withCString { passphraseBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphraseBytes,
                        strlen(passphraseBytes),
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw BackupError.encryptionFailed
        }

        return SymmetricKey(data: derivedKeyData)
    }

    private func randomData(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        return data
    }
}
