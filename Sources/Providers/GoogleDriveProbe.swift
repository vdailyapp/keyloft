import Foundation
import VaultDomain

/// Google Drive `about.get?fields=user,storageQuota`.
public struct GoogleDriveProbe: APIProbe {
    private let http: any HTTPClient
    private let clock: any DateProvider

    public init(http: any HTTPClient, clock: any DateProvider) {
        self.http = http
        self.clock = clock
    }

    static let endpoint = URL(
        string: "https://www.googleapis.com/drive/v3/about?fields=user,storageQuota")!

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
            if Self.insufficientPermissions(in: data) || ProbeSupport.insufficientScopeHeader(response) {
                throw ProbeError.insufficientScope(nil)
            }
            throw ProbeError.forbidden("HTTP 403")
        }
        guard (200...299).contains(response.statusCode) else {
            throw ProbeError.malformed("HTTP \(response.statusCode)")
        }

        struct About: Decodable {
            let user: User?
            let storageQuota: StorageQuota?
            struct User: Decodable { let emailAddress: String? }
            struct StorageQuota: Decodable {
                let usage: String?
                let limit: String?
            }
        }
        let about: About
        do {
            about = try JSONDecoder().decode(About.self, from: data)
        } catch {
            throw ProbeError.malformed("about: \(error.localizedDescription)")
        }
        let quota = about.storageQuota.map {
            Quota(
                used: Int64($0.usage ?? "") ?? 0,
                total: $0.limit.flatMap { Int64($0) })
        }
        return ProbeResult(
            email: about.user?.emailAddress, quota: quota, latencyMs: latency)
    }

    private static func insufficientPermissions(in data: Data) -> Bool {
        struct Body: Decodable {
            let error: Error?
            struct Error: Decodable {
                let errors: [Item]?
                struct Item: Decodable { let reason: String? }
            }
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return false }
        return body.error?.errors?.contains { $0.reason == "insufficientPermissions" } == true
    }
}
