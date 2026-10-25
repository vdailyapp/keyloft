import Foundation
import GRDB
import HealthCheck
import Providers
import SecretVault
import TokenVault
import VaultDomain
import VaultPersistence

/// Các mảnh ghép của runtime. `secretStore` là factory nhận `KeychainAuthContextProvider`
/// (chính là VaultLock do init dựng) vì Keychain cần lock, còn lock cần authenticator —
/// không thể dựng trước ngoài deps.
public struct RuntimeDependencies: Sendable {
    public var database: VaultDatabase
    public var secretStore: @Sendable (any KeychainAuthContextProvider) -> any SecretStore
    public var http: any HTTPClient
    public var browser: any BrowserSession
    public var authenticator: any UserPresenceAuthenticator
    public var clock: any DateProvider
    public var ids: any IDGenerator
    public var random: any RandomSource
    public var sleeper: any Sleeper
    public var receivers: CallbackReceiverFactory

    public init(
        database: VaultDatabase,
        secretStore: @escaping @Sendable (any KeychainAuthContextProvider) -> any SecretStore,
        http: any HTTPClient,
        browser: any BrowserSession,
        authenticator: any UserPresenceAuthenticator,
        clock: any DateProvider = SystemDateProvider(),
        ids: any IDGenerator = SystemIDGenerator(),
        random: any RandomSource = SystemRandomSource(),
        sleeper: any Sleeper = TaskSleeper(),
        receivers: @escaping CallbackReceiverFactory = { LoopbackServer(configuredRedirect: $0) }
    ) {
        self.database = database
        self.secretStore = secretStore
        self.http = http
        self.browser = browser
        self.authenticator = authenticator
        self.clock = clock
        self.ids = ids
        self.random = random
        self.sleeper = sleeper
        self.receivers = receivers
    }

    /// Deps dùng SQLite in-memory + store bất kỳ — cho test tích hợp (I1–I3).
    public static func inMemory(
        http: any HTTPClient,
        browser: any BrowserSession,
        clock: any DateProvider,
        ids: any IDGenerator,
        random: any RandomSource,
        store: any SecretStore
    ) -> RuntimeDependencies {
        RuntimeDependencies(
            database: try! VaultDatabase.inMemory(),
            secretStore: { _ in store },
            http: http,
            browser: browser,
            authenticator: NoopAuthenticator(),
            clock: clock,
            ids: ids,
            random: random)
    }
}

/// Authenticator không dùng tới trong test (VaultLock chỉ cần một instance hợp lệ).
struct NoopAuthenticator: UserPresenceAuthenticator {
    func authenticate(reason: String) async throws -> AuthenticatedContext {
        throw SecretStoreError.authFailed
    }
}

/// Composition root duy nhất: nơi duy nhất biết GRDB và KeychainSecretStore tồn tại.
/// Thứ tự dựng: repos → catalog(+discovery) → lock → store → SecretVault → token endpoint →
/// TokenProvider → Login (onCredentialIssued seed token) → ScopeService → HealthChecker →
/// HealthScheduler.
public final class VaultRuntime: Sendable {
    public static let version = "0.1.0"

    public let accounts: any AccountRepository
    public let clients: any OAuthClientRepository
    public let credentials: any CredentialRepository
    public let healthResults: any HealthCheckRepository
    public let audit: any AuditLog
    public let providers: ProviderCatalog
    public let secrets: SecretVault
    public let lock: VaultLock
    public let tokens: TokenProvider
    public let login: OAuthLoginService
    public let scopes: ScopeService
    public let health: HealthChecker
    public let scheduler: HealthScheduler
    public let clock: any DateProvider

    public init(_ deps: RuntimeDependencies, policy: HealthPolicy = HealthPolicy()) {
        let accounts = GRDBAccountRepository(db: deps.database)
        let clients = GRDBOAuthClientRepository(db: deps.database)
        let credentials = GRDBCredentialRepository(db: deps.database)
        let secretMetadata = GRDBSecretMetadataRepository(db: deps.database)
        let healthResults = GRDBHealthCheckRepository(db: deps.database)
        let audit = GRDBAuditLog(db: deps.database)

        let providers = ProviderCatalog(discovery: OIDCDiscovery(http: deps.http))

        let lock = VaultLock(authenticator: deps.authenticator, clock: deps.clock)
        let store = deps.secretStore(lock)
        let secrets = SecretVault(
            store: store, metadata: secretMetadata, audit: audit,
            clock: deps.clock, ids: deps.ids)

        let tokenEndpoint = TokenEndpointClient(http: deps.http)
        let tokens = TokenProvider(
            providers: providers, clients: clients, accounts: accounts,
            credentials: credentials, secrets: secrets, audit: audit,
            tokenEndpoint: tokenEndpoint, clock: deps.clock, ids: deps.ids)
        let login = OAuthLoginService(
            providers: providers, clients: clients, accounts: accounts,
            credentials: credentials, secrets: secrets, audit: audit,
            tokenEndpoint: tokenEndpoint, browser: deps.browser, receivers: deps.receivers,
            random: deps.random, clock: deps.clock, ids: deps.ids,
            onCredentialIssued: { account, token in
                await tokens.seed(token, for: account)
            })
        let scopes = ScopeService(
            login: login, providers: providers, clients: clients, accounts: accounts,
            credentials: credentials, secrets: secrets, audit: audit,
            tokenEndpoint: tokenEndpoint, tokens: tokens, clock: deps.clock, ids: deps.ids)
        let health = HealthChecker(
            accounts: accounts, credentials: credentials, clients: clients,
            secretExists: { id in try await secrets.exists(id) },
            tokens: tokens, providers: providers,
            probes: { provider in
                ProbeFactory.probe(for: provider, http: deps.http, clock: deps.clock)
            },
            results: healthResults, audit: audit, clock: deps.clock, ids: deps.ids,
            policy: policy)
        let scheduler = HealthScheduler(
            checker: health, accounts: accounts, results: healthResults,
            clock: deps.clock, sleeper: deps.sleeper, policy: policy)

        self.accounts = accounts
        self.clients = clients
        self.credentials = credentials
        self.healthResults = healthResults
        self.audit = audit
        self.providers = providers
        self.secrets = secrets
        self.lock = lock
        self.tokens = tokens
        self.login = login
        self.scopes = scopes
        self.health = health
        self.scheduler = scheduler
        self.clock = deps.clock
    }

    /// Production: mở DB file (CLI đòi DB đã tồn tại), KeychainSecretStore theo config,
    /// URLSession ephemeral. Keychain `missingEntitlement` được CLI/App bắt ở thao tác
    /// đầu tiên và bọc thành `RuntimeError.keychainUnavailable` (không dò được lúc init
    /// vì SecItem chỉ lỗi khi thực sự dùng).
    public static func live(
        context: RuntimeContext, browser: any BrowserSession
    ) throws -> VaultRuntime {
        let config = try RuntimeConfiguration.default(for: context)
        if context == .cli, !FileManager.default.fileExists(atPath: config.databaseURL.path) {
            throw RuntimeError.vaultNotInitialized
        }
        let deps = RuntimeDependencies(
            database: try VaultDatabase.open(at: config.databaseURL),
            secretStore: { provider in
                KeychainSecretStore(
                    configuration: config.keychain, contextProvider: provider)
            },
            http: URLSessionHTTPClient(),
            browser: browser,
            authenticator: LocalAuthenticationAuthenticator())
        return VaultRuntime(deps, policy: config.healthPolicy)
    }
}
