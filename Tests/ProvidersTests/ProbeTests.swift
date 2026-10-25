import Foundation
import KeyloftTestSupport
import Providers
import Testing
import VaultDomain

@Suite("API probes")
struct ProbeTests {
    static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test("U10: Google about OK — email/quota đúng, Bearer + URL")
    func googleAbout() async throws {
        let stub = StubHTTPClient()
        stub.on("GET", "https://www.googleapis.com", json: try Self.fixture("google-about"))
        let probe = GoogleDriveProbe(http: stub, clock: FixedDateProvider())

        let result = try await probe.probe(accessToken: "AT-1")
        #expect(result.email == "user@example.com")
        #expect(result.quota == Quota(used: 123_456_789, total: 1_000_000_000))
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer AT-1")
        #expect(
            request.url?.absoluteString
                == "https://www.googleapis.com/drive/v3/about?fields=user,storageQuota")
    }

    @Test("U11: Google thiếu limit → total nil")
    func googleNoLimit() async throws {
        let stub = StubHTTPClient()
        stub.on("GET", "https://www.googleapis.com", json: try Self.fixture("google-about-nolimit"))
        let probe = GoogleDriveProbe(http: stub, clock: FixedDateProvider())
        let result = try await probe.probe(accessToken: "AT")
        #expect(result.quota?.used == 123_456_789)
        #expect(result.quota?.total == nil)
    }

    @Test("U12: Google 403 insufficientPermissions → insufficientScope")
    func google403() async throws {
        let stub = StubHTTPClient()
        stub.on(
            "GET", "https://www.googleapis.com", status: 403,
            json: try Self.fixture("google-403-insufficient"))
        let probe = GoogleDriveProbe(http: stub, clock: FixedDateProvider())
        await #expect(throws: ProbeError.insufficientScope(nil)) {
            _ = try await probe.probe(accessToken: "AT")
        }
    }

    @Test("U13: Microsoft drive OK — quota đúng")
    func microsoftDrive() async throws {
        let stub = StubHTTPClient()
        stub.on("GET", "https://graph.microsoft.com", json: try Self.fixture("microsoft-drive"))
        let probe = MicrosoftGraphProbe(http: stub, clock: FixedDateProvider())

        let result = try await probe.probe(accessToken: "AT")
        #expect(result.quota == Quota(used: 1000, total: 2000))
        #expect(result.email == "user@example.com")
    }

    @Test("U14: Microsoft 403 + WWW-Authenticate insufficient_scope → insufficientScope")
    func microsoft403() async throws {
        let stub = StubHTTPClient()
        stub.on(
            "GET", "https://graph.microsoft.com", status: 403,
            json: try Self.fixture("microsoft-403"),
            headers: ["WWW-Authenticate": #"Bearer error="insufficient_scope""#])
        let probe = MicrosoftGraphProbe(http: stub, clock: FixedDateProvider())
        await #expect(throws: ProbeError.insufficientScope(nil)) {
            _ = try await probe.probe(accessToken: "AT")
        }
    }

    @Test("U15: Dropbox space usage individual + team; POST không body, không Content-Type")
    func dropboxUsage() async throws {
        let stub = StubHTTPClient()
        stub.on("POST", "https://api.dropboxapi.com", json: try Self.fixture("dropbox-space-usage"))
        let probe = DropboxProbe(http: stub, clock: FixedDateProvider())

        let individual = try await probe.probe(accessToken: "AT")
        #expect(individual.quota == Quota(used: 150, total: 2_147_483_648))

        let teamStub = StubHTTPClient()
        teamStub.on("POST", "https://api.dropboxapi.com", json: try Self.fixture("dropbox-space-usage-team"))
        let team = try await DropboxProbe(http: teamStub, clock: FixedDateProvider())
            .probe(accessToken: "AT")
        #expect(team.quota == Quota(used: 150, total: 1_099_511_627_776))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody?.count == 0 || request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
    }

    @Test("U16: Dropbox 401 missing_scope → insufficientScope(required)")
    func dropboxMissingScope() async throws {
        let stub = StubHTTPClient()
        stub.on(
            "POST", "https://api.dropboxapi.com", status: 401,
            json: try Self.fixture("dropbox-401"))
        let probe = DropboxProbe(http: stub, clock: FixedDateProvider())
        await #expect(throws: ProbeError.insufficientScope("files.metadata.read")) {
            _ = try await probe.probe(accessToken: "AT")
        }
    }

    @Test("U17: 401 thường cả 3 provider → unauthorized")
    func plain401() async throws {
        let stub = StubHTTPClient()
        stub.on("GET", "https://www.googleapis.com", status: 401, json: "{}")
        stub.on("GET", "https://graph.microsoft.com", status: 401, json: "{}")
        stub.on(
            "POST", "https://api.dropboxapi.com", status: 401,
            json: #"{"error": {".tag": "other"}}"#)
        let clock = FixedDateProvider()

        for provider in ProviderID.allCases {
            let probe = ProbeFactory.probe(for: provider, http: stub, clock: clock)
            await #expect(throws: ProbeError.unauthorized) {
                _ = try await probe.probe(accessToken: "AT")
            }
        }
    }

    @Test("U18: 429/503/URLError → rateLimited/server/network, isTransient")
    func transientErrors() async throws {
        let clock = FixedDateProvider()

        let stub429 = StubHTTPClient()
        stub429.on("GET", "https://www.googleapis.com", status: 429, json: "{}")
        await #expect(throws: ProbeError.rateLimited) {
            _ = try await ProbeFactory.probe(for: .google, http: stub429, clock: clock)
                .probe(accessToken: "AT")
        }

        let stub503 = StubHTTPClient()
        stub503.on("GET", "https://www.googleapis.com", status: 503, json: "{}")
        await #expect(throws: ProbeError.server(503)) {
            _ = try await ProbeFactory.probe(for: .google, http: stub503, clock: clock)
                .probe(accessToken: "AT")
        }

        let stubNet = StubHTTPClient()
        stubNet.onError("GET", "https://www.googleapis.com", URLError(.timedOut))
        do {
            _ = try await ProbeFactory.probe(for: .google, http: stubNet, clock: clock)
                .probe(accessToken: "AT")
            Issue.record("phải throw network")
        } catch let error as ProbeError {
            #expect(error == .network(.timedOut))
            #expect(error.isTransient)
        }
        #expect(ProbeError.rateLimited.isTransient)
        #expect(ProbeError.server(503).isTransient)
        #expect(!ProbeError.unauthorized.isTransient)
    }

    @Test("U19: latencyMs theo clock (stub advance 700ms trong handler)")
    func latency() async throws {
        let clock = FixedDateProvider()
        let stub = StubHTTPClient()
        stub.add(
            StubHTTPClient.Route(method: "GET", urlPrefix: "https://www.googleapis.com") { _ in
                clock.advance(by: 0.7)
                return (200, ["Content-Type": "application/json"], Data(#"{"user":{}}"#.utf8))
            })
        let probe = GoogleDriveProbe(http: stub, clock: clock)
        let result = try await probe.probe(accessToken: "AT")
        #expect(result.latencyMs == 700)
    }
}
