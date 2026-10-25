import Foundation
import VaultDomain

public enum TokenVaultError: Error, Sendable, Equatable {
    case accountNotFound(AccountID)
    case noActiveCredential(AccountID)
    /// Giữ nguyên lỗi gốc để caller xét `isTransient`.
    case oauth(OAuthError)
    /// Đọc refresh token lỗi (bọc SecretVaultError, không lộ giá trị).
    case secret(String)
    case rotationPersistFailed(AccountID)
}
