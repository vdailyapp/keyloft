import CryptoKit
import Foundation
import VaultDomain

/// Cặp PKCE (RFC 7636): verifier + challenge S256.
public struct PKCEPair: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let method = "S256"

    /// 32 byte ngẫu nhiên → verifier 43 ký tự.
    public static func generate(using random: any RandomSource) throws -> PKCEPair {
        let data = try random.bytes(count: 32)
        return try PKCEPair(verifier: Base64URL.encode(data))
    }

    /// Validate độ dài 43–128 và chỉ ký tự unreserved `[A-Za-z0-9-._~]` (RFC 7636 §4.1),
    /// rồi tính challenge — dùng cho test vector RFC.
    public init(verifier: String) throws {
        guard (43...128).contains(verifier.count) else {
            throw OAuthCryptoError.invalidVerifier("độ dài phải 43–128, được \(verifier.count)")
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard verifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw OAuthCryptoError.invalidVerifier("chứa ký tự không thuộc unreserved")
        }
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Base64URL.encode(Data(digest))
    }
}

public enum OAuthState {
    /// 32 byte ngẫu nhiên → 43 ký tự base64url (không padding).
    public static func generate(using random: any RandomSource) throws -> String {
        Base64URL.encode(try random.bytes(count: 32))
    }
}

public enum OAuthCryptoError: Error, Sendable, Equatable {
    case invalidVerifier(String)
}

/// So sánh hằng thời gian: được phép đoán sai độ dài sớm, nhưng vòng lặp so byte
/// không được dừng sớm (chống timing leak khi so `state`).
public func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let left = Array(a.utf8)
    let right = Array(b.utf8)
    var equal = left.count == right.count
    let length = max(left.count, right.count)
    for i in 0..<length {
        let l = i < left.count ? left[i] : 0
        let r = i < right.count ? right[i] : 0
        if l != r { equal = false }
    }
    return equal
}
