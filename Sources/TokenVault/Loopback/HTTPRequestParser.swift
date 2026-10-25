import Foundation

/// Parse phần đầu request HTTP (thuần, không I/O) cho LoopbackServer.
/// Giới hạn 8 KB để chặn request khổng lồ chiếm bộ nhớ.
public enum HTTPRequestParser {
    public static let maxBytes = 8192

    public struct RequestHead: Equatable, Sendable {
        public let method: String
        public let path: String
        public let query: [String: String]

        public init(method: String, path: String, query: [String: String]) {
            self.method = method
            self.path = path
            self.query = query
        }
    }

    public enum ParseError: Error, Equatable, Sendable {
        /// Vượt quá `maxBytes`.
        case tooLarge
        /// Request line / header hỏng dạng.
        case malformed
        /// Chưa thấy `\r\n\r\n` — tiếp tục đọc.
        case incomplete
    }

    public static func parse(_ data: Data) -> Result<RequestHead, ParseError> {
        if data.count > maxBytes { return .failure(.tooLarge) }
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return .failure(.incomplete)
        }
        let headData = data.subdata(in: data.startIndex..<headEnd.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else {
            return .failure(.malformed)
        }
        var lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure(.malformed)
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0].allSatisfy({ $0.isUppercaseLetter }),
            parts[2].hasPrefix("HTTP/")
        else {
            return .failure(.malformed)
        }
        // Header phải dạng key:value (kiểm tra nhẹ để bắt garbage).
        lines.removeFirst()
        for line in lines where !line.isEmpty {
            if !line.contains(":") { return .failure(.malformed) }
        }

        let target = String(parts[1])
        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces[0])
        var query: [String: String] = [:]
        if pieces.count > 1 {
            for pair in pieces[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                guard !key.isEmpty else { continue }
                let value = kv.count > 1 ? String(kv[1]).removingPercentEncoding ?? String(kv[1]) : ""
                // Giá trị đầu tiên thắng (giống hành vi phổ biến của OAuth server).
                if query[key] == nil { query[key] = value }
            }
        }
        return .success(RequestHead(method: String(parts[0]), path: path, query: query))
    }
}

extension Character {
    fileprivate var isUppercaseLetter: Bool {
        asciiValue.map { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) } ?? false
    }
}
