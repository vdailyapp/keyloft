import Foundation
import TokenVault

/// Trình duyệt giả: đọc `redirect_uri` + `state` từ URL được mở rồi GET thật (URLSession)
/// tới loopback — mô phỏng trình duyệt redirect về app.
public final class FakeBrowserSession: BrowserSession, @unchecked Sendable {
    /// NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
    public enum StateMode: Sendable, Equatable {
        case echo
        case fixed(String)
    }

    public enum Behavior: Sendable, Equatable {
        case redirect(code: String, state: StateMode, iss: String?)
        case cancel
        /// Callback về với `error=<param>`.
        case error(String)
    }

    private let lock = NSLock()
    private var behavior: Behavior
    private var opened: [URL] = []

    public init(behavior: Behavior) {
        self.behavior = behavior
    }

    public var openedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    public func update(_ newBehavior: Behavior) {
        withLock { behavior = newBehavior }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func present(_ url: URL, callbackScheme: String) async throws {
        let current = withLock {
            opened.append(url)
            return behavior
        }

        switch current {
        case .cancel:
            throw BrowserSessionError.userCancelled
        case .redirect(let code, let stateMode, let iss):
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let items = components.queryItems
            else {
                throw BrowserSessionError.failed("URL authorize không có query")
            }
            let redirectURI =
                items.first(where: { $0.name == "redirect_uri" })?.value
                ?? "http://127.0.0.1/callback"
            let state: String
            switch stateMode {
            case .echo:
                state = items.first(where: { $0.name == "state" })?.value ?? ""
            case .fixed(let value):
                state = value
            }
            try await hit(
                redirectURI: redirectURI,
                extra: [
                    ("code", code), ("state", state),
                ] + (iss.map { [("iss", $0)] } ?? []))
        case .error(let param):
            let redirectURI =
                (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "redirect_uri" })?.value)
                ?? "http://127.0.0.1/callback"
            try await hit(redirectURI: redirectURI, extra: [("error", param)])
        }
    }

    private func hit(redirectURI: String, extra: [(String, String)]) async throws {
        guard var callback = URLComponents(string: redirectURI) else {
            throw BrowserSessionError.failed("redirect_uri không hợp lệ: \(redirectURI)")
        }
        callback.queryItems = extra.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let target = callback.url else {
            throw BrowserSessionError.failed("không dựng được URL callback")
        }
        var request = URLRequest(url: target)
        request.timeoutInterval = 10
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            _ = try await session.data(for: request)
        } catch {
            // 302 về custom scheme khiến URLSession báo lỗi sau khi request đã tới
            // loopback — trình duyệt thật cũng chỉ quan tâm request đã gửi.
        }
    }
}
