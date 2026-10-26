import Foundation
import KeyloftTestSupport
import SecretVault
import Testing
import TokenVault
import VaultDomain

@Suite("ScopeService")
struct ScopeServiceTests {
    struct Rig {
        let db: InMemoryDatabase
        let store: InMemorySecretStore
        let audit: InMemoryAuditLog
        let clock: FixedDateProvider
        let stub: StubHTTPClient
        let registry: InMemoryProviderRegistry
        let clients: InMemoryOAuthClientRepository
        let accounts: InMemoryAccountRepository
        let credentials: InMemoryCredentialRepository
        let metadata: InMemorySecretMetadataRepository
        let results: InMemoryHealthCheckRepository
        let vault: SecretVault
        let login: FakeLoginRunner
        let service: ScopeService
        let client: OAuthClient
        let account: Account
        let activeCredential: Credential

        static func make(
            providerId: ProviderID = .google,
            granted: ScopeSet = ["openid", "https://www.googleapis.com/auth/userinfo.email"],
            secondCredential: Bool = false,
            healthCount: Int = 0,
            failPurge: Bool = false
        ) async throws -> Rig {
            let db = InMemoryDatabase()
            let audit = InMemoryAuditLog(db: db)
            let clock = FixedDateProvider()
            let store = InMemorySecretStore()
            let registry = InMemoryProviderRegistry(TestData.allProviders)
            let clients = InMemoryOAuthClientRepository(db: db)
            let accounts = InMemoryAccountRepository(db: db)
            let credentials = InMemoryCredentialRepository(db: db)
            let metadata = InMemorySecretMetadataRepository(db: db)
            let results = InMemoryHealthCheckRepository(db: db)
            let ids = SequentialIDGenerator()

            let client = TestData.oauthClient(provider: providerId, hasSecret: false)
            try await clients.save(client)
            let account = TestData.account(provider: providerId, clientId: client.id)
            try await accounts.save(account)

            let secret = TestData.secret()
            try await metadata.insert(secret)
            try await store.set(
                Data("rt-old".utf8), for: secret.keychainRef, policy: .afterFirstUnlock)
            let active = TestData.credential(
                accountId: account.id, refreshTokenRef: secret.id,
                requested: granted, granted: granted)
            try await credentials.insert(active)

            var allCredentials = [active]
            if secondCredential {
                let oldSecret = TestData.secret(id: SecretID(rawValue: ids.make()))
                try await metadata.insert(oldSecret)
                try await store.set(
                    Data("rt-older".utf8), for: oldSecret.keychainRef, policy: .afterFirstUnlock)
                let older = TestData.credential(
                    id: CredentialID(rawValue: ids.make()), accountId: account.id,
                    refreshTokenRef: oldSecret.id, granted: granted,
                    issuedAt: Date(timeIntervalSince1970: 1), status: .superseded)
                try await credentials.insert(older)
                allCredentials.append(older)
            }
            for i in 0..<healthCount {
                try await results.append(
                    HealthCheckResult(
                        id: HealthCheckID(rawValue: ids.make()), accountId: account.id,
                        checkedAt: clock.now().addingTimeInterval(Double(i)),
                        status: .healthy, checks: []))
            }

            let usedStore: any SecretStore = failPurge ? PurgeFailingStore(backing: store) : store
            let vault = SecretVault(
                store: usedStore, metadata: metadata, audit: audit, clock: clock, ids: ids)
            let stub = StubHTTPClient()
            let tokens = TokenProvider(
                providers: registry, clients: clients, accounts: accounts,
                credentials: credentials, secrets: vault, audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stub), clock: clock, ids: ids)
            let login = FakeLoginRunner(
                simulate: FakeLoginRunner.standardSimulate(
                    credentials: credentials, secrets: vault, ids: ids, clock: clock))
            let service = ScopeService(
                login: login, providers: registry, clients: clients, accounts: accounts,
                credentials: credentials, secrets: vault, audit: audit,
                tokenEndpoint: TokenEndpointClient(http: stub), tokens: tokens,
                clock: clock, ids: ids)

            return Rig(
                db: db, store: store, audit: audit, clock: clock, stub: stub,
                registry: registry, clients: clients, accounts: accounts,
                credentials: credentials, metadata: metadata, results: results,
                vault: vault, login: login, service: service, client: client,
                account: account, activeCredential: active)
        }

        func happyRefresh() {
            let provider = TestData.allProviders.first { $0.id == account.providerId }!
            stub.on(
                "POST", provider.tokenURL.absoluteString,
                json: #"{"access_token":"fresh-at","token_type":"Bearer","expires_in":3600}"#)
            if let revokeURL = provider.revokeURL {
                stub.on("POST", revokeURL.absoluteString, json: "{}")
            }
        }
    }

    @Test("U1: plan Google — missing drive, scopes [drive openid email], includeGranted, loginHint")
    func planGoogle() async throws {
        let rig = try await Rig.make()
        let plan = try await rig.service.planGrantMore(rig.account.id)
        guard case .browser(let request) = plan else {
            Issue.record("kỳ vọng .browser, được \(plan)")
            return
        }
        #expect(request.scopes == ["drive", "openid", "email"])
        #expect(request.includeGrantedScopes)
        #expect(request.loginHint == rig.account.email)
        #expect(request.target == .existing(rig.account.id))
    }

    @Test("U2: execute Google không revoke; credential cũ superseded")
    func executeNoRevoke() async throws {
        let rig = try await Rig.make()
        rig.happyRefresh()

        let outcome = try await rig.service.execute(
            LoginRequest(
                oauthClientId: rig.client.id, scopes: ["openid", "email"], target: .existing(rig.account.id)))
        #expect(outcome.credential.status == .active)
        let old = try await rig.credentials.get(rig.activeCredential.id)
        #expect(old?.status == .superseded)
        #expect(rig.stub.requests.allSatisfy { !$0.url!.absoluteString.contains("/revoke") })
    }

    @Test("U3: plan Microsoft / Dropbox / đủ scope")
    func planVariants() async throws {
        let msGranted: ScopeSet = ["openid", "email", "offline_access", "Files.Read"]
        let ms = try await Rig.make(providerId: .microsoft, granted: msGranted)
        let msPlan = try await ms.service.planGrantMore(ms.account.id)
        // MS defaultScopes có Files.ReadWrite — thiếu → reauthorize với granted ∪ missing.
        guard case .browser(let msRequest) = msPlan else {
            Issue.record("kỳ vọng .browser cho MS")
            return
        }
        #expect(!msRequest.includeGrantedScopes)
        #expect(msRequest.scopes == msGranted.union(TestData.microsoftProvider.defaultScopes))

        let dbx = try await Rig.make(
            providerId: .dropbox,
            granted: ["account_info.read", "openid", "email"])
        let dbxPlan = try await dbx.service.planGrantMore(dbx.account.id)
        guard case .consoleThenRelogin(let url, let missing, let then) = dbxPlan else {
            Issue.record("kỳ vọng .consoleThenRelogin cho Dropbox")
            return
        }
        #expect(url == ScopeService.dropboxConsoleURL)
        #expect(missing == ["files.metadata.read"])
        #expect(then.target == .existing(dbx.account.id))

        let aliases = TestData.googleProvider.quirks.scopeAliases
        let fullGranted = ScopeSet(
            TestData.googleProvider.defaultScopes.values.map { aliases[$0] ?? $0 })
        let full = try await Rig.make(granted: fullGranted)
        let nonePlan = try await full.service.planGrantMore(full.account.id)
        #expect(nonePlan == .nothingMissing)
    }

    @Test("U4: reduce luôn còn credential active; cuối cùng active là credential mới")
    func reduceKeepsActive() async throws {
        let rig = try await Rig.make()
        rig.happyRefresh()
        // Hook sau login: bất biến luôn có active.
        let credentials = rig.credentials
        let account = rig.account
        let checker = ActiveChecker(credentials: credentials, account: account.id)
        rig.login.hook = { _ in await checker.assertActive() }

        let target = ScopeNormalizer.canonical(
            ["openid", "email"], provider: TestData.googleProvider)
        let outcome = try await rig.service.reduce(rig.account.id, to: target)
        #expect(outcome.credential.status == .active)
        #expect(try await rig.credentials.active(for: rig.account.id)?.id == outcome.credential.id)
        #expect(await checker.violations == 0)
    }

    @Test("U5: reduce scope lạ → notSubset, 0 request login")
    func reduceNotSubset() async throws {
        let rig = try await Rig.make()
        await #expect(throws: ScopeServiceError.notSubset(extra: ["calendar.events"])) {
            _ = try await rig.service.reduce(rig.account.id, to: ["openid", "calendar.events"])
        }
        #expect(rig.login.requests.isEmpty)
    }

    @Test("U6: revoke Google thiếu ack → throw, 0 request")
    func revokeNeedsAck() async throws {
        let rig = try await Rig.make()
        await #expect(throws: ScopeServiceError.grantWideRevocationNotAcknowledged) {
            _ = try await rig.service.revoke(rig.activeCredential.id, acknowledgeGrantWideRevocation: false)
        }
        #expect(rig.stub.requests.isEmpty)
    }

    @Test("U7: revoke Google có ack — 1 request hint refresh_token, cả 2 revoked, needsReauth")
    func revokeGoogleAck() async throws {
        let rig = try await Rig.make(secondCredential: true)
        rig.happyRefresh()
        try await rig.service.revoke(rig.activeCredential.id, acknowledgeGrantWideRevocation: true)

        let revokeRequests = rig.stub.requests.filter { $0.url!.absoluteString.contains("/revoke") }
        #expect(revokeRequests.count == 1)
        let body = String(decoding: revokeRequests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("token=rt-old"))
        #expect(body.contains("token_type_hint=refresh_token"))

        for credential in try await rig.credentials.list(for: rig.account.id) {
            #expect(credential.status == .revoked)
        }
        let account = try await rig.accounts.get(rig.account.id)
        #expect(account?.status == .needsReauth)
    }

    @Test("U8: revoke Dropbox — refresh rồi revoke Bearer access token")
    func revokeDropbox() async throws {
        let rig = try await Rig.make(providerId: .dropbox)
        rig.happyRefresh()

        let outcome = try await rig.service.revoke(rig.activeCredential.id, acknowledgeGrantWideRevocation: false)
        #expect(outcome == .revokedRemotely)

        let revoke = rig.stub.requests.filter { $0.url!.absoluteString.contains("/revoke") }
        #expect(revoke.count == 1)
        #expect(revoke[0].value(forHTTPHeaderField: "Authorization") == "Bearer fresh-at")
        #expect(try await rig.credentials.get(rig.activeCredential.id)?.status == .revoked)
    }

    @Test("U9: remove Dropbox — 2 revoke, sạch DB + Keychain, audit account.removed")
    func removeDropbox() async throws {
        let rig = try await Rig.make(providerId: .dropbox, secondCredential: true, healthCount: 3)
        rig.happyRefresh()

        let report = try await rig.service.removeAccount(rig.account.id, acknowledgeGrantWideRevocation: false)
        #expect(report.leftoverSecrets.isEmpty)
        #expect(report.revocations.count == 2)
        #expect(report.revocations.values.allSatisfy { $0 == .revokedRemotely })

        #expect(try await rig.accounts.get(rig.account.id) == nil)
        #expect(try await rig.credentials.list(for: rig.account.id).isEmpty)
        #expect(try await rig.results.list(for: rig.account.id, limit: 10).isEmpty)
        #expect(await rig.store.storedRefs.isEmpty)
        #expect(try await rig.audit.query(AuditQuery(actions: [.accountRemoved])).count == 1)
    }

    @Test("U10: remove khi revoke lỗi mạng → vẫn xóa cục bộ, localOnly(network)")
    func removeNetworkFail() async throws {
        let rig = try await Rig.make()
        rig.stub.onError("POST", "https://example.test/google/revoke", URLError(.timedOut))

        let report = try await rig.service.removeAccount(rig.account.id, acknowledgeGrantWideRevocation: true)
        #expect(report.revocations[rig.activeCredential.id] == .localOnly(reason: "network"))
        #expect(try await rig.accounts.get(rig.account.id) == nil)
        #expect(await rig.store.storedRefs.isEmpty)
    }

    @Test("U11: remove Microsoft — 0 request mạng, localOnly, sạch cục bộ")
    func removeMicrosoft() async throws {
        let rig = try await Rig.make(providerId: .microsoft)
        let report = try await rig.service.removeAccount(rig.account.id, acknowledgeGrantWideRevocation: false)
        #expect(rig.stub.requests.isEmpty)
        #expect(report.revocations[rig.activeCredential.id] == .localOnly(reason: "provider không hỗ trợ thu hồi"))
        #expect(try await rig.accounts.get(rig.account.id) == nil)
        #expect(await rig.store.storedRefs.isEmpty)
    }

    @Test("U12: execute refresh lỗi → không dọn secret cũ, không throw")
    func executeRefreshFailsKeepsSecret() async throws {
        let rig = try await Rig.make()
        let provider = TestData.allProviders.first { $0.id == rig.account.providerId }!
        rig.stub.on("POST", provider.tokenURL.absoluteString, status: 503, json: "{}")

        _ = try await rig.service.execute(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid"], target: .existing(rig.account.id)))
        let oldRef = KeychainRef(kind: .refreshToken, id: rig.activeCredential.refreshTokenRef)
        #expect(try await rig.store.contains(oldRef))
    }

    @Test("U13: execute refresh ok → purge secret superseded, giữ hàng credential")
    func executePurgesOldSecret() async throws {
        let rig = try await Rig.make()
        rig.happyRefresh()

        _ = try await rig.service.execute(
            LoginRequest(oauthClientId: rig.client.id, scopes: ["openid", "email"], target: .existing(rig.account.id)))
        let oldRef = KeychainRef(kind: .refreshToken, id: rig.activeCredential.refreshTokenRef)
        #expect(try await rig.store.contains(oldRef) == false)
        #expect(try await rig.credentials.get(rig.activeCredential.id)?.status == .superseded)
        #expect(try await rig.metadata.get(rig.activeCredential.refreshTokenRef) != nil)
    }

    @Test("U15: reduce Dropbox revoke lỗi mạng → credential cũ không revoked, secret còn, audit .failure")
    func reduceDropboxRevokeFails() async throws {
        let granted: ScopeSet = ["account_info.read", "openid", "email"]
        let rig = try await Rig.make(providerId: .dropbox, granted: granted)
        let provider = TestData.dropboxProvider
        let revokeURL = try #require(provider.revokeURL)
        // Refresh OK (revoke Dropbox cần access token), nhưng POST /revoke lỗi mạng.
        rig.stub.on(
            "POST", provider.tokenURL.absoluteString,
            json: #"{"access_token":"fresh-at","token_type":"Bearer","expires_in":3600}"#)
        rig.stub.onError("POST", revokeURL.absoluteString, URLError(.timedOut))

        let outcome = try await rig.service.reduce(
            rig.account.id, to: ["account_info.read", "openid"])

        #expect(outcome.narrowRevocationFailed)
        // Credential cũ giữ nguyên status superseded (không markRevoked) — RT cũ vẫn
        // sống ở Dropbox, phải thử thu hồi lại được.
        let old = try await rig.credentials.get(rig.activeCredential.id)
        #expect(old?.status == .superseded)
        // Secret cũ không bị purge (còn trong store) để retry.
        let oldRef = KeychainRef(kind: .refreshToken, id: rig.activeCredential.refreshTokenRef)
        #expect(try await rig.store.contains(oldRef))
        #expect(try await rig.metadata.get(rig.activeCredential.refreshTokenRef) != nil)
        // Audit ghi nhận thu hồi thất bại.
        let events = try await rig.audit.query(AuditQuery(actions: [.credentialRevoked]))
        #expect(events.count == 1)
        guard case .failure = events.first?.result else {
            Issue.record("kỳ vọng audit .failure, được \(String(describing: events.first?.result))")
            return
        }
        // Login vẫn thành công: credential mới active.
        #expect(try await rig.credentials.active(for: rig.account.id) != nil)
    }

    @Test("U16: finalizeRevocation purge lỗi → revoke throw, secret không bị xóa lặng lẽ")
    func revokePurgeFails() async throws {
        let rig = try await Rig.make(failPurge: true)
        rig.happyRefresh()

        await #expect(throws: SecretVaultError.self) {
            _ = try await rig.service.revoke(
                rig.activeCredential.id, acknowledgeGrantWideRevocation: true)
        }
        let oldRef = KeychainRef(kind: .refreshToken, id: rig.activeCredential.refreshTokenRef)
        #expect(try await rig.store.contains(oldRef))
    }
}

/// Store giả chỉ làm `delete` lỗi — purgeValue phải throw thay vì nuốt (T30).
final class PurgeFailingStore: SecretStore, @unchecked Sendable {
    // NSLock + @unchecked Sendable — ngoại lệ cho phép, chỉ trong Tests/.
    let backing: InMemorySecretStore

    init(backing: InMemorySecretStore) {
        self.backing = backing
    }

    func set(_ data: Data, for ref: KeychainRef, policy: SecretAccessPolicy) async throws {
        try await backing.set(data, for: ref, policy: policy)
    }

    func get(_ ref: KeychainRef, reason: String) async throws -> Data {
        try await backing.get(ref, reason: reason)
    }

    func delete(_ ref: KeychainRef) async throws {
        throw SecretStoreError.osStatus(-1)
    }

    func contains(_ ref: KeychainRef) async throws -> Bool {
        try await backing.contains(ref)
    }
}

actor ActiveChecker {
    let credentials: any CredentialRepository
    let account: AccountID
    private(set) var violations = 0

    init(credentials: any CredentialRepository, account: AccountID) {
        self.credentials = credentials
        self.account = account
    }

    func assertActive() async {
        if (try? await credentials.active(for: account)) == nil {
            violations += 1
        }
    }
}
