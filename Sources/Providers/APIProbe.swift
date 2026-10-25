import Foundation
import VaultDomain

public struct Quota: Sendable, Equatable {
    public var used: Int64
    public var total: Int64?

    public init(used: Int64, total: Int64?) {
        self.used = used
        self.total = total
    }
}

public struct ProbeResult: Sendable, Equatable {
    public var email: String?
    public var quota: Quota?
    public var latencyMs: Int

    public init(email: String?, quota: Quota?, latencyMs: Int) {
        self.email = email
        self.quota = quota
        self.latencyMs = latencyMs
    }
}

public enum ProbeError: Error, Sendable, Equatable {
    case unauthorized
    case insufficientScope(String?)
    case forbidden(String?)
    case rateLimited
    case server(Int)
    case network(URLError.Code)
    case malformed(String)

    /// Lỗi tạm thời — retry được, không đổi trạng thái account.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .server, .network: true
        default: false
        }
    }
}

public protocol APIProbe: Sendable {
    func probe(accessToken: String) async throws -> ProbeResult
}

public enum ProbeFactory {
    public static func probe(
        for provider: ProviderID, http: any HTTPClient, clock: any DateProvider
    ) -> any APIProbe {
        switch provider {
        case .google: GoogleDriveProbe(http: http, clock: clock)
        case .microsoft: MicrosoftGraphProbe(http: http, clock: clock)
        case .dropbox: DropboxProbe(http: http, clock: clock)
        }
    }
}

/// Phần xử lý lỗi HTTP chung cho các probe.
enum ProbeSupport {
    /// 2xx → nil (body dùng được). Lỗi chung: 429, 5xx, mạng, JSON hỏng. 4xx trả về
    /// ProbeError? do probe tự quyết (nil = để probe xử lý theo provider).
    static func commonError(status: Int, data: Data) -> ProbeError? {
        switch status {
        case 200...299:
            return nil
        case 429:
            return .rateLimited
        case let code where code >= 500:
            return .server(code)
        default:
            return nil
        }
    }

    static func networkError(_ error: Error) -> ProbeError {
        if let urlError = error as? URLError {
            return .network(urlError.code)
        }
        return .malformed("\(error)")
    }

    static func insufficientScopeHeader(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "WWW-Authenticate")?.contains("insufficient_scope") == true
    }
}
