import Foundation
import VaultDomain

/// Dropbox RPC `POST /2/users/get_space_usage` — KHÔNG set Content-Type với body rỗng
/// (Dropbox từ chối `application/json` + body rỗng).
public struct DropboxProbe: APIProbe {
    private let http: any HTTPClient
    private let clock: any DateProvider

    public init(http: any HTTPClient, clock: any DateProvider) {
        self.http = http
        self.clock = clock
    }

    static let endpoint = URL(string: "https://api.dropboxapi.com/2/users/get_space_usage")!

    public func probe(accessToken: String) async throws -> ProbeResult {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data()
        request.timeoutInterval = 20

        let start = clock.now()
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.send(request)
        } catch {
            throw ProbeSupport.networkError(error)
        }
        let latency = Int(clock.now().timeIntervalSince(start) * 1000)

        if let error = ProbeSupport.commonError(status: response.statusCode, data: data) {
            throw error
        }
        if response.statusCode == 401 {
            if let required = Self.missingScope(in: data) {
                throw ProbeError.insufficientScope(required)
            }
            throw ProbeError.unauthorized
        }
        guard (200...299).contains(response.statusCode) else {
            throw ProbeError.malformed("HTTP \(response.statusCode)")
        }

        struct SpaceUsage: Decodable {
            let used: Int64?
            let allocation: Allocation?
            struct Allocation: Decodable {
                let tag: String?
                let allocated: Int64?
                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                    case allocated
                }
            }
        }
        let usage: SpaceUsage
        do {
            usage = try JSONDecoder().decode(SpaceUsage.self, from: data)
        } catch {
            throw ProbeError.malformed("space usage: \(error.localizedDescription)")
        }
        return ProbeResult(
            email: nil,
            quota: Quota(used: usage.used ?? 0, total: usage.allocation?.allocated),
            latencyMs: latency)
    }

    private static func missingScope(in data: Data) -> String? {
        struct Body: Decodable {
            let error: Error?
            struct Error: Decodable {
                let tag: String?
                let requiredScope: String?
                enum CodingKeys: String, CodingKey {
                    case tag = ".tag"
                    case requiredScope = "required_scope"
                }
            }
        }
        guard
            let body = try? JSONDecoder().decode(Body.self, from: data),
            body.error?.tag == "missing_scope"
        else { return nil }
        return body.error?.requiredScope
    }
}
