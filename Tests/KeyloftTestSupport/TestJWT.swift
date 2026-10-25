import Foundation
import TokenVault

/// Dựng JWT giả cho test: header mặc định `{"alg":"RS256"}`, chữ ký `"sig"`.
public enum TestJWT {
    public static func make(
        header: String = #"{"alg":"RS256"}"#,
        claims: String
    ) -> String {
        let headerJSON = Data(header.utf8)
        let claimsJSON = Data(claims.utf8)
        return [
            Base64URL.encode(headerJSON),
            Base64URL.encode(claimsJSON),
            Base64URL.encode(Data("sig".utf8)),
        ].joined(separator: ".")
    }

    public static func make(claims: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(claims)
        return make(claims: String(decoding: data, as: UTF8.self))
    }

    /// Claims dùng chung cho test: exp mặc định xa tương lai.
    public static func claims(
        iss: String,
        sub: String = "sub-1",
        aud: [String] = ["client-1"],
        exp: Double = 2_000_000_000,
        email: String? = "user@example.test",
        tid: String? = nil
    ) -> String {
        let audJSON = aud.map { "\"" + $0 + "\"" }.joined(separator: ", ")
        var pairs: [String] = [
            "\"iss\": \"" + iss + "\"",
            "\"sub\": \"" + sub + "\"",
            "\"aud\": [" + audJSON + "]",
            "\"exp\": " + String(exp),
        ]
        if let email { pairs.append("\"email\": \"" + email + "\"") }
        if let tid { pairs.append("\"tid\": \"" + tid + "\"") }
        return "{" + pairs.joined(separator: ", ") + "}"
    }
}
