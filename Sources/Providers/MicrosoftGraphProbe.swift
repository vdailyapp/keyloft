import Foundation
import VaultDomain

/// Microsoft Graph `GET /me/drive`.
public struct MicrosoftGraphProbe: APIProbe {
    private let http: any HTTPClient
    private let clock: any DateProvider

    public init(http: any HTTPClient, clock: any DateProvider) {
        self.http = http
        self.clock = clock
    }

    static let endpoint = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!

    public func probe(accessToken: String) async throws -> ProbeResult {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
        guard response.statusCode != 401 else { throw ProbeError.unauthorized }
        guard response.statusCode != 403 else {
            if ProbeSupport.insufficientScopeHeader(response) || Self.accessDenied(in: data) {
                throw ProbeError.insufficientScope(nil)
            }
            throw ProbeError.forbidden("HTTP 403")
        }
        guard (200...299).contains(response.statusCode) else {
            throw ProbeError.malformed("HTTP \(response.statusCode)")
        }

        struct Drive: Decodable {
            let quota: Quota?
            let owner: Owner?
            struct Quota: Decodable {
                let used: Int64?
                let total: Int64?
            }
            struct Owner: Decodable {
                let user: User?
                struct User: Decodable { let email: String? }
            }
        }
        let drive: Drive
        do {
            drive = try JSONDecoder().decode(Drive.self, from: data)
        } catch {
            throw ProbeError.malformed("drive: \(error.localizedDescription)")
        }
        let quota = drive.quota.map { Quota(used: $0.used ?? 0, total: $0.total) }
        return ProbeResult(
            email: drive.owner?.user?.email, quota: quota, latencyMs: latency)
    }

    private static func accessDenied(in data: Data) -> Bool {
        struct Body: Decodable {
            let error: Error?
            struct Error: Decodable { let code: String? }
        }
        // try?: body lỗi JSON tùy chọn — hỏng nghĩa là không phải accessDenied.
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return false }
        return body.error?.code == "accessDenied"
    }
}
