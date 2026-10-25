import Foundation

/// `application/x-www-form-urlencoded` theo WHATWG: unreserved `A-Z a-z 0-9 - . _ *` giữ
/// nguyên, space → `+`, còn lại `%XX` viết hoa.
public enum FormEncoding {
    public static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    /// Encode một giá trị đơn (dùng cho Basic auth RFC 6749 §2.3.1).
    public static func escape(_ string: String) -> String {
        var output = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", ".", "_", "*":
                output.unicodeScalars.append(scalar)
            case " ":
                output += "+"
            default:
                for byte in String(scalar).utf8 {
                    output += String(format: "%%%02X", byte)
                }
            }
        }
        return output
    }
}
