import Foundation
import Security

public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}

public protocol IDGenerator: Sendable {
    func make() -> UUID
}

public struct SystemIDGenerator: IDGenerator {
    public init() {}
    public func make() -> UUID { UUID() }
}

public protocol RandomSource: Sendable {
    func bytes(count: Int) throws -> Data
}

public struct SystemRandomSource: RandomSource {
    public init() {}
    public func bytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else { throw DomainError.randomUnavailable }
        return data
    }
}

/// Mọi gọi mạng trong package đi qua protocol này (test dùng StubHTTPClient).
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Session ephemeral mặc định: không cache, không cookie — tránh token lọt vào đĩa.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
