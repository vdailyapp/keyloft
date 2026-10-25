import Foundation
import Network

public enum LoopbackError: Error, Sendable, Equatable {
    case bindFailed(String)
    case timeout
    case cancelled
    case invalidRedirect
}

/// Server loopback RFC 8252 §7.3: chỉ bind 127.0.0.1, nhận đúng 1 callback hợp lệ.
///
/// Mọi đột biến state nằm trong actor; NWListener chỉ giao event qua DispatchQueue serial
/// private (ngoại lệ AGENTS.md cho phép ở file này — Network framework không có API async)
/// và bắc cầu về actor bằng Task, nên không có race giữa callback/timeout/stop:
/// continuation nằm trong slot duy nhất `callbackContinuation`, chỉ resume một lần.
public actor LoopbackServer: CallbackReceiver {
    public static let completionURL = URL(string: "app.vdaily.keyloft://oauth-complete")!

    private let configuredRedirect: URL
    private let timeout: Duration
    private let callbackPath: String

    // Ngoại lệ AGENTS.md: NWListener cần DispatchQueue để chạy handler.
    private let queue = DispatchQueue(label: "app.vdaily.keyloft.loopback")

    private var listener: NWListener?
    private var actualRedirect: URL?
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var callbackContinuation: CheckedContinuation<CallbackParameters, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var finished = false

    public init(configuredRedirect: URL, timeout: Duration = .seconds(300)) {
        self.configuredRedirect = configuredRedirect
        self.timeout = timeout
        let path = configuredRedirect.path
        self.callbackPath = (path.isEmpty || path == "/") ? "/callback" : path
    }

    // MARK: - CallbackReceiver

    public func start() async throws -> URL {
        guard configuredRedirect.scheme?.lowercased() == "http", configuredRedirect.host == "127.0.0.1" else {
            throw LoopbackError.invalidRedirect
        }
        if let actualRedirect { return actualRedirect }  // idempotent

        let port: NWEndpoint.Port =
            configuredRedirect.port.flatMap {
                $0 > 0 && $0 <= Int(UInt16.max) ? NWEndpoint.Port(rawValue: UInt16($0)) : nil
            } ?? .any
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)

        let newListener: NWListener
        do {
            newListener = try NWListener(using: params)
        } catch {
            throw LoopbackError.bindFailed("\(error)")
        }
        listener = newListener
        newListener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }

        try await withCheckedThrowingContinuation { cont in
            startContinuation = cont
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { await self.handleReady() }
                case .failed(let error):
                    Task { await self.handleBindFailed(error) }
                default:
                    break
                }
            }
            newListener.start(queue: queue)
        }
        guard let redirect = actualRedirect else {
            // Không xảy ra: handleReady luôn set trước khi resume.
            throw LoopbackError.bindFailed("listener ready nhưng không có port")
        }
        return redirect
    }

    public func waitForCallback() async throws -> CallbackParameters {
        guard actualRedirect != nil else { throw LoopbackError.bindFailed("chưa start") }
        guard !finished, callbackContinuation == nil else {
            throw LoopbackError.cancelled
        }
        let waitTimeout = timeout
        return try await withCheckedThrowingContinuation { cont in
            callbackContinuation = cont
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: waitTimeout)
                } catch {
                    return  // task bị cancel do callback/stop đến trước
                }
                await self?.handleTimeout()
            }
        }
    }

    public func stop() async {
        finished = true
        if let cont = startContinuation {
            startContinuation = nil
            cont.resume(throwing: LoopbackError.cancelled)
        }
        if let cont = callbackContinuation {
            callbackContinuation = nil
            cont.resume(throwing: LoopbackError.cancelled)
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        shutdownListener()
    }

    // MARK: - Listener events (chạy tới từ DispatchQueue của NWListener)

    private func handleReady() {
        guard let cont = startContinuation else { return }
        startContinuation = nil
        if let raw = listener?.port?.rawValue {
            actualRedirect = URL(string: "http://127.0.0.1:\(raw)\(callbackPath)")
        }
        cont.resume()
    }

    private func handleBindFailed(_ error: NWError) {
        guard let cont = startContinuation else { return }
        startContinuation = nil
        listener = nil
        cont.resume(throwing: LoopbackError.bindFailed("\(error)"))
    }

    private func accept(_ connection: NWConnection) {
        guard !finished, listener != nil else {
            connection.cancel()
            return
        }
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { await self?.drop(connection) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext(connection)
    }

    private nonisolated func receiveNext(_ connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: HTTPRequestParser.maxBytes
        ) { data, _, isComplete, error in
            Task { await self.ingest(connection, data: data, isComplete: isComplete, error: error) }
        }
    }

    private func ingest(
        _ connection: NWConnection, data: Data?, isComplete: Bool, error: NWError?
    ) {
        let key = ObjectIdentifier(connection)
        guard !finished else {
            connection.cancel()
            connections[key] = nil
            buffers[key] = nil
            return
        }
        if let data {
            buffers[key, default: Data()].append(data)
        }
        if error != nil {
            drop(connection)
            return
        }
        let buffer = buffers[key] ?? Data()

        switch HTTPRequestParser.parse(buffer) {
        case .success(let head):
            route(head, connection: connection)
        case .failure(.incomplete):
            if isComplete {
                respond(connection, status: "400 Bad Request", body: "Malformed request")
            } else {
                receiveNext(connection)
            }
        case .failure(.tooLarge), .failure(.malformed):
            respond(connection, status: "400 Bad Request", body: "Bad request")
        }
    }

    private func route(_ head: HTTPRequestParser.RequestHead, connection: NWConnection) {
        guard head.method == "GET" else {
            respond(connection, status: "405 Method Not Allowed", body: "Method not allowed")
            return
        }
        guard head.path == callbackPath else {
            respond(connection, status: "404 Not Found", body: "Not found")
            return
        }
        let parameters = CallbackParameters(
            code: head.query["code"],
            state: head.query["state"],
            iss: head.query["iss"],
            error: head.query["error"],
            errorDescription: head.query["error_description"]
        )
        respond(
            connection, status: "302 Found", location: Self.completionURL,
            body: "<html><body>Đăng nhập hoàn tất — bạn có thể đóng tab này.</body></html>")
        finish(with: parameters)
    }

    private func finish(with parameters: CallbackParameters) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        callbackContinuation?.resume(returning: parameters)
        callbackContinuation = nil
        // Chỉ đóng listener; các connection đang sống tự cancel sau khi response
        // được flush (.contentProcessed) — hủy luôn sẽ giết response 302.
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    private func handleTimeout() {
        guard !finished, let cont = callbackContinuation else { return }
        finished = true
        callbackContinuation = nil
        cont.resume(throwing: LoopbackError.timeout)
        shutdownListener()
    }

    private func drop(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = nil
        buffers[key] = nil
    }

    private func shutdownListener() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        buffers.removeAll()
    }

    // MARK: - Response

    private nonisolated func respond(
        _ connection: NWConnection, status: String, location: URL? = nil, body: String
    ) {
        var head =
            "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n"
        if let location {
            head += "Location: \(location.absoluteString)\r\n"
        }
        let payload = Data((head + "\r\n" + body).utf8)
        connection.send(
            content: payload,
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }
}
