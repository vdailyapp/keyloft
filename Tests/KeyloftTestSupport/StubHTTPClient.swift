import Foundation
import VaultDomain

/// HTTP client giả: đăng ký route theo method + url prefix; ghi lại mọi request để assert.
/// Không khớp route nào → throw `URLError(.unsupportedURL)` cho test fail rõ ràng.
/// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
public final class StubHTTPClient: HTTPClient, @unchecked Sendable {

    public struct Route: Sendable {
        public let method: String
        public let urlPrefix: String
        public let delay: Duration?
        public let handler: @Sendable (URLRequest) throws -> (Int, [String: String], Data)

        public init(
            method: String,
            urlPrefix: String,
            delay: Duration? = nil,
            handler: @escaping @Sendable (URLRequest) throws -> (Int, [String: String], Data)
        ) {
            self.method = method
            self.urlPrefix = urlPrefix
            self.delay = delay
            self.handler = handler
        }
    }

    private let lock = NSLock()
    private var routes: [Route]
    private var recorded: [URLRequest] = []

    public init(routes: [Route] = []) {
        self.routes = routes
    }

    /// Route trả JSON: `on("POST", "https://x/token", status: 200, json: "...", headers: [...])`.
    public func on(
        _ method: String,
        _ urlPrefix: String,
        status: Int = 200,
        json: String,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        add(
            Route(method: method, urlPrefix: urlPrefix) { _ in
                (status, headers, Data(json.utf8))
            })
    }

    /// Route JSON có delay — dùng test cache/single-flight (SPEC-006 U4).
    public func on(
        _ method: String,
        _ urlPrefix: String,
        status: Int = 200,
        json: String,
        headers: [String: String] = ["Content-Type": "application/json"],
        delay: Duration
    ) {
        add(
            Route(method: method, urlPrefix: urlPrefix, delay: delay) { _ in
                (status, headers, Data(json.utf8))
            })
    }

    /// Route trả lỗi transport (timeout, mất mạng...).
    public func onError(_ method: String, _ urlPrefix: String, _ error: URLError) {
        add(Route(method: method, urlPrefix: urlPrefix) { _ in throw error })
    }

    public func add(_ route: Route) {
        withLock { routes.append(route) }
    }

    public var requests: [URLRequest] {
        withLock { recorded }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (route, requestUrl) = withLock {
            recorded.append(request)
            let match = routes.first {
                $0.method.uppercased() == request.httpMethod?.uppercased()
                    && request.url?.absoluteString.hasPrefix($0.urlPrefix) == true
            }
            return (match, request.url)
        }

        guard let route, let requestUrl else {
            throw URLError(.unsupportedURL)
        }
        if let delay = route.delay {
            try await Task.sleep(for: delay)
        }
        let (status, headers, data) = try route.handler(request)
        guard
            let response = HTTPURLResponse(
                url: requestUrl, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}
