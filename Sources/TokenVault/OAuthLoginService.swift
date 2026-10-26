import Foundation
import SecretVault
import VaultDomain

public enum LoginTarget: Sendable, Equatable {
    case newAccount
    case existing(AccountID)
}

public struct LoginRequest: Sendable, Equatable {
    public var oauthClientId: OAuthClientID
    /// Service gọi (SPEC-009/UI) quyết định; thường `provider.defaultScopes`.
    public var scopes: ScopeSet
    public var target: LoginTarget
    public var includeGrantedScopes: Bool = false
    public var loginHint: String?

    public init(
        oauthClientId: OAuthClientID,
        scopes: ScopeSet,
        target: LoginTarget,
        includeGrantedScopes: Bool = false,
        loginHint: String? = nil
    ) {
        self.oauthClientId = oauthClientId
        self.scopes = scopes
        self.target = target
        self.includeGrantedScopes = includeGrantedScopes
        self.loginHint = loginHint
    }
}

public struct LoginOutcome: Sendable, Equatable {
    public var account: Account
    public var credential: Credential
    public var deniedScopes: ScopeSet
    public var isNewAccount: Bool
    /// Reduce Dropbox: thu hồi credential cũ ở provider THẤT BẠI — credential cũ (superseded)
    /// và secret của nó vẫn còn để thử lại; UI báo người dùng "chưa thu hồi được".
    public var narrowRevocationFailed: Bool = false

    public init(
        account: Account, credential: Credential, deniedScopes: ScopeSet, isNewAccount: Bool,
        narrowRevocationFailed: Bool = false
    ) {
        self.account = account
        self.credential = credential
        self.deniedScopes = deniedScopes
        self.isNewAccount = isNewAccount
        self.narrowRevocationFailed = narrowRevocationFailed
    }
}

public typealias CredentialIssuedObserver = @Sendable (AccountID, AccessToken) async -> Void

/// Điều phối đăng nhập OAuth: PKCE + loopback + browser + token endpoint + lưu account/
/// credential/secret + audit. Mọi dependency tiêm vào để test không cần mạng/keychain thật.
///
/// Chạy đua browser × loopback bằng callbackTask unstructured thay vì task group: nếu
/// browser throw (người dùng hủy) khi task group còn task đang treo trên continuation của
/// `waitForCallback`, group sẽ chờ mãi — continuation không tự resume khi bị cancel.
/// Với unstructured task, `receiver.stop()` (chạy trên mọi đường thoát) resume continuation
/// nên không có task nào treo lại.
public actor OAuthLoginService {
    private let providers: any ProviderRegistry
    private let clients: any OAuthClientRepository
    private let accounts: any AccountRepository
    private let credentials: any CredentialRepository
    private let secrets: SecretVault
    private let audit: any AuditLog
    private let tokenEndpoint: TokenEndpointClient
    private let browser: any BrowserSession
    private let receivers: CallbackReceiverFactory
    private let random: any RandomSource
    private let clock: any DateProvider
    private let ids: any IDGenerator
    private let onCredentialIssued: CredentialIssuedObserver?

    public init(
        providers: any ProviderRegistry,
        clients: any OAuthClientRepository,
        accounts: any AccountRepository,
        credentials: any CredentialRepository,
        secrets: SecretVault,
        audit: any AuditLog,
        tokenEndpoint: TokenEndpointClient,
        browser: any BrowserSession,
        receivers: @escaping CallbackReceiverFactory,
        random: any RandomSource,
        clock: any DateProvider,
        ids: any IDGenerator,
        onCredentialIssued: CredentialIssuedObserver? = nil
    ) {
        self.providers = providers
        self.clients = clients
        self.accounts = accounts
        self.credentials = credentials
        self.secrets = secrets
        self.audit = audit
        self.tokenEndpoint = tokenEndpoint
        self.browser = browser
        self.receivers = receivers
        self.random = random
        self.clock = clock
        self.ids = ids
        self.onCredentialIssued = onCredentialIssued
    }

    public func login(_ request: LoginRequest) async throws -> LoginOutcome {
        guard let client = try await clients.get(request.oauthClientId) else {
            throw DomainError.notFound("oauth_client:\(request.oauthClientId)")
        }
        let provider = try await providers.provider(client.providerId)

        let pkce = try PKCEPair.generate(using: random)
        let state = try OAuthState.generate(using: random)
        let receiver = receivers(client.redirectURI)
        let redirect = try await receiver.start()
        // defer không await được: stop() phải chạy trên MỌI đường thoát (thành công/lỗi/hủy).
        do {
            let outcome = try await runFlow(
                request: request, client: client, provider: provider, receiver: receiver,
                redirect: redirect, pkce: pkce, state: state)
            await receiver.stop()
            return outcome
        } catch {
            await receiver.stop()
            throw error
        }
    }

    private func runFlow(
        request: LoginRequest,
        client: OAuthClient,
        provider: Provider,
        receiver: any CallbackReceiver,
        redirect: URL,
        pkce: PKCEPair,
        state: String
    ) async throws -> LoginOutcome {
        let authorizeURL = try AuthorizationRequest(
            provider: provider,
            clientId: client.clientId,
            redirectURI: redirect,
            scopes: request.scopes,
            state: state,
            pkce: pkce,
            loginHint: request.loginHint,
            includeGrantedScopes: request.includeGrantedScopes
        ).url()

        // B: chờ callback (unstructured — browser hủy không giết nó).
        let callbackTask = Task { try await receiver.waitForCallback() }
        // A: mở trình duyệt; trả về bình thường KHÔNG kết thúc luồng (callback có thể tới sau).
        do {
            try await browser.present(authorizeURL, callbackScheme: "app.vdaily.keyloft")
        } catch let error as BrowserSessionError {
            callbackTask.cancel()
            throw Self.mapBrowserError(error)
        }
        let parameters: CallbackParameters
        do {
            parameters = try await callbackTask.value
        } catch let error as LoopbackError {
            throw Self.mapLoopbackError(error)
        }

        if let error = parameters.error {
            throw error == "access_denied"
                ? OAuthError.accessDenied(parameters.errorDescription)
                : OAuthError.other(code: error, description: parameters.errorDescription)
        }

        // State sai → KHÔNG gọi token endpoint (chống CSRF).
        guard constantTimeEquals(parameters.state ?? "", state) else {
            try await appendAudit(
                action: .credentialIssued, target: "account:unknown",
                scopes: nil, result: .failure(reason: "state mismatch"), actor: .user)
            throw OAuthError.stateMismatch
        }

        // RFC 9207: iss có → phải khớp; thiếu mà provider bắt buộc → lỗi.
        if let iss = parameters.iss {
            guard Self.issuerMatches(provider: provider, iss: iss) else {
                throw OAuthError.issuerMismatch(expected: provider.issuer, actual: iss)
            }
        } else if provider.quirks.authorizationResponseIssSupported {
            throw OAuthError.issuerMismatch(expected: provider.issuer, actual: nil)
        }

        guard let code = parameters.code else {
            throw OAuthError.missingCode
        }

        let clientSecret: String?
        if let secretRef = client.clientSecretRef {
            let data = try await secrets.read(secretRef, reason: "Đăng nhập OAuth", actor: .app)
            clientSecret = String(decoding: data, as: UTF8.self)
        } else {
            clientSecret = nil
        }

        let tokens = try await tokenEndpoint.exchangeCode(
            code,
            verifier: pkce.verifier,
            redirectURI: redirect,
            tokenURL: provider.tokenURL,
            client: ClientCredentials(
                clientId: client.clientId,
                clientSecret: clientSecret,
                method: provider.quirks.tokenEndpointAuth))

        guard let refreshToken = tokens.refreshToken else {
            throw OAuthError.missingRefreshToken
        }
        guard let idToken = tokens.idToken else {
            throw OAuthError.missingIDToken
        }
        let claims = try IDTokenClaims.decode(idToken)
        try claims.validate(provider: provider, clientId: client.clientId, now: clock.now())

        let granted = ScopeNormalizer.granted(
            responseScope: tokens.scope, requested: request.scopes, provider: provider)
        let denied = ScopeNormalizer.canonical(request.scopes, provider: provider)
            .missing(in: granted)

        // Account: đích cũ phải cùng sub; đích mới tìm theo sub rồi mới tạo.
        var account: Account
        var isNewAccount = false
        switch request.target {
        case .existing(let id):
            guard var existing = try await accounts.get(id) else {
                throw DomainError.notFound("account:\(id)")
            }
            guard existing.externalId == claims.sub else {
                throw OAuthError.accountMismatch(
                    expectedExternalId: existing.externalId, actualEmail: claims.bestEmail)
            }
            existing.email = claims.bestEmail
            existing.displayName = claims.name
            account = existing
        case .newAccount:
            if var found = try await accounts.find(
                provider: client.providerId, oauthClient: client.id, externalId: claims.sub)
            {
                found.email = claims.bestEmail
                found.displayName = claims.name
                account = found
            } else {
                isNewAccount = true
                account = Account(
                    id: AccountID(rawValue: ids.make()),
                    providerId: client.providerId,
                    oauthClientId: client.id,
                    externalId: claims.sub,
                    email: claims.bestEmail,
                    displayName: claims.name,
                    status: .healthy,
                    statusChangedAt: clock.now(),
                    createdAt: clock.now())
            }
        }

        // Ghi secret; từ đây lỗi → bồi hoàn xóa secret rồi rethrow.
        let secret = try await secrets.create(
            kind: .refreshToken,
            label: "\(provider.displayName) \(claims.bestEmail ?? claims.sub)",
            value: Data(refreshToken.utf8),
            actor: .user)
        do {
            account.status = denied.isEmpty ? .healthy : .needsConsent
            account.statusChangedAt = clock.now()
            try await accounts.save(account)

            let previous = try await credentials.active(for: account.id)
            let newCredential = Credential(
                id: CredentialID(rawValue: ids.make()),
                accountId: account.id,
                refreshTokenRef: secret.id,
                requestedScopes: ScopeNormalizer.canonical(request.scopes, provider: provider),
                grantedScopes: granted,
                issuedAt: clock.now(),
                status: .active)
            try await credentials.insert(newCredential)
            if let previous {
                try await credentials.markSuperseded(previous.id, by: newCredential.id)
                try await appendAudit(
                    action: .credentialSuperseded,
                    target: "credential:\(previous.id)",
                    scopes: nil, result: .success, actor: .user)
            }

            if isNewAccount {
                try await appendAudit(
                    action: .accountAdded, target: "account:\(account.id)",
                    scopes: nil, result: .success, actor: .user)
            }
            try await appendAudit(
                action: .credentialIssued, target: "account:\(account.id)",
                scopes: granted, result: .success, actor: .user)
            try await appendAudit(
                action: .scopeGranted, target: "account:\(account.id)",
                scopes: granted, result: .success, actor: .user)
            if !denied.isEmpty {
                try await appendAudit(
                    action: .scopeDenied, target: "account:\(account.id)",
                    scopes: denied, result: .success, actor: .user)
            }

            if let onCredentialIssued {
                await onCredentialIssued(
                    account.id,
                    AccessToken(
                        value: tokens.accessToken,
                        scopes: granted,
                        expiresAt: clock.now().addingTimeInterval(
                            TimeInterval(tokens.expiresIn ?? 3600))))
            }
            return LoginOutcome(
                account: account, credential: newCredential,
                deniedScopes: denied, isNewAccount: isNewAccount)
        } catch {
            // Bồi hoàn: không để lại secret mồ côi trong Keychain (thứ tự insert fail →
            // xóa secret; lỗi dọn không che lỗi gốc).
            // try?: bồi hoàn khi login đã lỗi — xóa secret lỗi không được che mất lỗi gốc.
            try? await secrets.delete(secret.id, actor: .user)
            throw error
        }
    }

    // MARK: - Map lỗi

    static func mapBrowserError(_ error: BrowserSessionError) -> OAuthError {
        switch error {
        case .userCancelled: .userCancelled
        case .failed(let reason): .malformedResponse(reason)
        }
    }

    static func mapLoopbackError(_ error: LoopbackError) -> OAuthError {
        switch error {
        case .timeout: .timeout
        case .cancelled: .userCancelled
        case .bindFailed(let reason): .malformedResponse("bind: \(reason)")
        case .invalidRedirect: .malformedResponse("redirect không hợp lệ")
        }
    }

    /// iss của authorization response (RFC 9207): provider dạng template (Microsoft)
    /// thay `{tenantid}` bằng pattern "không có dấu /" vì bước này chưa có tid.
    static func issuerMatches(provider: Provider, iss: String) -> Bool {
        if provider.quirks.issuerIsTenantTemplated {
            let pattern =
                "^"
                + NSRegularExpression.escapedPattern(for: provider.issuer)
                .replacingOccurrences(of: "\\{tenantid\\}", with: "[^/]+")
                + "$"
            return iss.range(of: pattern, options: .regularExpression) != nil
        }
        return iss == provider.issuer
    }

    private func appendAudit(
        action: AuditAction,
        target: String,
        scopes: ScopeSet?,
        result: AuditResult,
        actor: AuditActor
    ) async throws {
        try await audit.append(
            AuditEvent(
                id: AuditEventID(rawValue: ids.make()),
                actor: actor,
                action: action,
                target: target,
                scopes: scopes,
                result: result,
                timestamp: clock.now()))
    }
}
