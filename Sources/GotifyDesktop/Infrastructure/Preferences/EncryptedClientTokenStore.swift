import CryptoKit
import Foundation

/// Encrypts the token before it enters the preferences plist without creating a custom cryptographic primitive.
enum EncryptedClientTokenStore {
    private enum Configuration {
        /// This fixed application-scoped material keeps encrypted preferences readable after an unsigned App update.
        static let keyDerivationContext = "com.gotify.desktop.preferences-token.v1"
    }

    private static let key = SymmetricKey(
        data: SHA256.hash(data: Data(Configuration.keyDerivationContext.utf8))
    )

    /// AES-GCM supplies a random nonce and authentication tag in `combined`, which is safe to persist as Base64.
    static func encrypt(_ token: String) throws -> String {
        let sealedBox = try AES.GCM.seal(Data(token.utf8), using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.missingCombinedRepresentation
        }
        return combined.base64EncodedString()
    }

    /// Corrupted or legacy plaintext preferences are rejected rather than treated as a token.
    static func decrypt(_ encryptedToken: String) -> String? {
        guard !encryptedToken.isEmpty,
              let combined = Data(base64Encoded: encryptedToken),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealedBox, using: key)
        else {
            return nil
        }
        return String(data: plaintext, encoding: .utf8)
    }

    private enum EncryptionError: Error {
        case missingCombinedRepresentation
    }
}
