import Foundation

/// BASE64URL theo RFC 7636 Appendix B: không padding, `+` → `-`, `/` → `_`.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// Tự thêm padding đủ độ dài; chuỗi không hợp lệ → nil.
    public static func decode(_ string: String) -> Data? {
        var base64 =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        return Data(base64Encoded: base64)
    }
}
