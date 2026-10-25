import Foundation
import KeyloftTestSupport
import Testing
import TokenVault

/// URLSession không tự theo 302 sang custom scheme (để assert được Location).
final class NoRedirectSession: @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ Tests/.
    private let delegate = NoRedirectDelegate()
    lazy var session: URLSession = URLSession(
        configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

    final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}

let http = NoRedirectSession()

func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    let (data, response) = try await http.session.data(for: request)
    return (data, response as! HTTPURLResponse)
}

@Suite("HTTPRequestParser")
struct HTTPRequestParserTests {
    @Test("Parser: parse request line + query, percent-decode")
    func parses() {
        let request = Data(
            ("GET /callback?code=c%2B1&state=s%20t&error_description=h%C3%A0 HTTP/1.1\r\n"
                + "Host: 127.0.0.1\r\nUser-Agent: test\r\n\r\n").utf8)
        let head = try! HTTPRequestParser.parse(request).get()
        #expect(head.method == "GET")
        #expect(head.path == "/callback")
        #expect(head.query["code"] == "c+1")
        #expect(head.query["state"] == "s t")
        #expect(head.query["error_description"] == "hà")
    }

    @Test("Parser: thiếu \\r\\n\\r\\n → incomplete; quá 8 KB → tooLarge; request line hỏng → malformed")
    func errors() {
        #expect(
            HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nH".utf8)).isFailure(.incomplete)
                == Optional(true))
        #expect(
            HTTPRequestParser.parse(Data(repeating: 65, count: HTTPRequestParser.maxBytes + 1))
                .isFailure(.tooLarge) == Optional(true))
        #expect(
            HTTPRequestParser.parse(Data("GARBAGE\r\n\r\n".utf8)).isFailure(.malformed)
                == Optional(true))
    }
}

extension Result {
    fileprivate func isFailure(_ error: Failure?) -> Bool where Failure: Equatable {
        if case .failure(let e) = self { return e == error }
        return false
    }
}

@Suite("Loopback")
struct LoopbackServerTests {
    @Test("U12: cổng ngẫu nhiên khi redirect không có port")
    func randomPort() async throws {
        let server = LoopbackServer(configuredRedirect: URL(string: "http://127.0.0.1/callback")!)
        let redirect = try await server.start()
        #expect(redirect.scheme == "http")
        #expect(redirect.host == "127.0.0.1")
        #expect(redirect.path == "/callback")
        #expect((redirect.port ?? 0) > 0)
        await server.stop()
    }

    @Test("U12: redirect sai (không phải http/127.0.0.1) → invalidRedirect")
    func invalidRedirect() async throws {
        let server = LoopbackServer(configuredRedirect: URL(string: "https://127.0.0.1/callback")!)
        await #expect(throws: LoopbackError.invalidRedirect) { _ = try await server.start() }
    }

    @Test("U13: callback hợp lệ → params đúng, 302 Location completionURL")
    func validCallback() async throws {
        let server = LoopbackServer(configuredRedirect: URL(string: "http://127.0.0.1/callback")!)
        let redirect = try await server.start()
        let waiter = Task { try await server.waitForCallback() }

        let (_, response) = try await get(
            URL(string: "\(redirect.absoluteString)?code=c&state=s&iss=i")!)
        #expect(response.statusCode == 302)
        #expect(
            response.value(forHTTPHeaderField: "Location")
                == LoopbackServer.completionURL.absoluteString)

        let params = try await waiter.value
        #expect(params == CallbackParameters(code: "c", state: "s", iss: "i"))
        await server.stop()
    }

    @Test("U14: path lạ nhận 404 nhưng vẫn chờ; callback kế tiếp hoàn tất")
    func unknownPathThenCallback() async throws {
        let server = LoopbackServer(configuredRedirect: URL(string: "http://127.0.0.1/callback")!)
        let redirect = try await server.start()
        let base = URL(string: redirect.absoluteString.replacingOccurrences(of: "/callback", with: ""))!
        let waiter = Task { try await server.waitForCallback() }

        let (_, notFound) = try await get(URL(string: "\(base)/favicon.ico")!)
        #expect(notFound.statusCode == 404)

        let (_, ok) = try await get(URL(string: "\(redirect)?code=x&state=y")!)
        #expect(ok.statusCode == 302)
        let params = try await waiter.value
        #expect(params.code == "x")
        await server.stop()
    }

    @Test("U15: POST → 405; request > 8 KB → 400; server vẫn chờ callback hợp lệ")
    func methodAndSizeGuards() async throws {
        let server = LoopbackServer(
            configuredRedirect: URL(string: "http://127.0.0.1/callback")!,
            timeout: .seconds(10))
        let redirect = try await server.start()
        let waiter = Task { try await server.waitForCallback() }

        var post = URLRequest(url: redirect)
        post.httpMethod = "POST"
        post.httpBody = Data("x=1".utf8)
        let (_, methodResponse) = try await http.session.data(for: post)
        #expect((methodResponse as! HTTPURLResponse).statusCode == 405)

        var big = URLRequest(url: URL(string: "\(redirect)?q=1")!)
        big.setValue(
            String(repeating: "a", count: HTTPRequestParser.maxBytes), forHTTPHeaderField: "X-Big")
        let (_, bigResponse) = try await http.session.data(for: big)
        #expect((bigResponse as! HTTPURLResponse).statusCode == 400)

        // Vẫn chờ được: callback hợp lệ ngay sau đó vẫn hoàn tất.
        let (_, ok) = try await get(URL(string: "\(redirect)?code=late&state=s")!)
        #expect(ok.statusCode == 302)
        let params = try await waiter.value
        #expect(params.code == "late")
        await server.stop()
    }

    @Test("U16: timeout → .timeout; stop khi đang chờ → .cancelled; port được giải phóng")
    func timeoutStopAndPortRelease() async throws {
        let shortTimeout = LoopbackServer(
            configuredRedirect: URL(string: "http://127.0.0.1/callback")!,
            timeout: .milliseconds(200))
        _ = try await shortTimeout.start()
        await #expect(throws: LoopbackError.timeout) {
            _ = try await shortTimeout.waitForCallback()
        }

        let stopped = LoopbackServer(
            configuredRedirect: URL(string: "http://127.0.0.1/callback")!, timeout: .seconds(30))
        _ = try await stopped.start()
        let waiter = Task { try await stopped.waitForCallback() }
        await stopped.stop()
        await #expect(throws: LoopbackError.cancelled) { try await waiter.value }

        // Port cố định: bind → stop → bind lại được.
        let fixed = URL(string: "http://127.0.0.1:45678/callback")!
        let first = LoopbackServer(configuredRedirect: fixed, timeout: .seconds(10))
        _ = try await first.start()
        await first.stop()
        let second = LoopbackServer(configuredRedirect: fixed, timeout: .seconds(10))
        let rebound = try await second.start()
        #expect(rebound.port == 45678)
        await second.stop()
    }

    @Test("I1: LoopbackServer thật + FakeBrowserSession redirect; listener đóng sau callback")
    func integrationFakeBrowser() async throws {
        let server = LoopbackServer(configuredRedirect: URL(string: "http://127.0.0.1/callback")!)
        let redirect = try await server.start()
        let browser = FakeBrowserSession(
            behavior: .redirect(code: "c9", state: .echo, iss: "https://accounts.google.com"))
        let waiter = Task { try await server.waitForCallback() }

        // URL authorize giả có redirect_uri trỏ về loopback thật.
        var authorize = URLComponents(url: URL(string: "https://example.test/auth")!, resolvingAgainstBaseURL: false)!
        authorize.queryItems = [
            URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "state", value: "st-1"),
        ]
        try await browser.present(authorize.url!, callbackScheme: "app.vdaily.keyloft")
        #expect(browser.openedURLs.count == 1)

        let params = try await waiter.value
        #expect(params == CallbackParameters(code: "c9", state: "st-1", iss: "https://accounts.google.com"))

        // Listener đã đóng: connect lại bị từ chối.
        await #expect(throws: URLError.self) {
            _ = try await get(redirect)
        }
    }
}
