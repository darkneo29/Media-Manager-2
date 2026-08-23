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

        let salt = try randomData(count: saltLength)
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

        guard (10_000...1_000_000).contains(encryptedSecrets.iterations),
              (8...64).contains(encryptedSecrets.salt.count),
              encryptedSecrets.nonce.count == 12,
              encryptedSecrets.tag.count == 16,
              !encryptedSecrets.ciphertext.isEmpty,
              encryptedSecrets.ciphertext.count <= 1_048_576 else {
            throw BackupError.invalidBackupFile
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

    private func randomData(count: Int) throws -> Data {
        guard count > 0 else { throw BackupError.encryptionFailed }
        var data = Data(count: count)
        let status: OSStatus = data.withUnsafeMutableBytes { bytes in
            guard let address = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, address)
        }
        guard status == errSecSuccess else { throw BackupError.encryptionFailed }
        return data
    }
}
