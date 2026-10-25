import Foundation
import KeyloftTestSupport
import Providers
import Testing
import TokenVault
import VaultDomain

@testable import HealthCheck

@Suite("HealthOutcome")
struct HealthOutcomeTests {
    @Test("U1: bảng map LayerFailure → AccountStatus (table-driven)")
    func statusTable() {
        let cases: [(LayerFailure?, [String], AccountStatus)] = [
            (nil, [], .healthy),
            (nil, ["quota>90%"], .degraded),
            (.noRefreshToken, [], .needsReauth),
            (.refreshInvalidGrant, [], .needsReauth),
            (.refreshInvalidClient, [], .degraded),
            (.refreshOther("x"), [], .degraded),
            (.refreshTransient("network"), [], .unreachable),
            (.apiTransient("rateLimited"), [], .unreachable),
            (.apiInsufficientScope("drive"), [], .needsConsent),
            (.missingScopes(["drive"]), [], .needsConsent),
            (.apiRejected("unauthorized"), [], .degraded),
        ]
        for (failure, warnings, expected) in cases {
            #expect(status(for: failure, warnings: warnings) == expected)
        }
    }

    @Test("Map TokenVaultError → LayerFailure đúng bảng TECH")
    func tokenErrorMapping() {
        #expect(layerFailure(for: .noActiveCredential(AccountID(rawValue: UUID()))) == .noRefreshToken)
        #expect(
            layerFailure(for: .oauth(.invalidGrant(nil))) == LayerFailure.refreshInvalidGrant)
        #expect(
            layerFailure(for: .rotationPersistFailed(AccountID(rawValue: UUID())))
                == LayerFailure.refreshInvalidGrant)
        #expect(
            layerFailure(for: .oauth(.invalidClient(nil))) == LayerFailure.refreshInvalidClient)
        #expect(
            layerFailure(for: .oauth(.server(status: 503))) == .refreshTransient("server(503)"))
        #expect(
            layerFailure(for: .oauth(.network(.timedOut))) == .refreshTransient("network(-1001)"))
        // Keychain chưa đọc được → transient, KHÔNG needsReauth.
        #expect(layerFailure(for: .secret("interactionNotAllowed")) == .refreshTransient("secretUnavailable"))
        #expect(
            layerFailure(for: .oauth(.stateMismatch)) == .refreshOther("stateMismatch"))
    }

    @Test("Map ProbeError → LayerFailure")
    func probeErrorMapping() {
        #expect(
            layerFailure(for: ProbeError.insufficientScope("drive"))
                == .apiInsufficientScope("drive"))
        #expect(layerFailure(for: ProbeError.rateLimited) == .apiTransient("rateLimited"))
        #expect(
            layerFailure(for: ProbeError.server(502)) == .apiTransient("server(502)"))
        #expect(layerFailure(for: ProbeError.unauthorized) == .apiRejected("unauthorized"))
        #expect(
            layerFailure(for: ProbeError.malformed("bad")) == .apiRejected("malformed"))
    }

    @Test("Property: 1000 lượt lỗi transient (seed cố định) → luôn unreachable")
    func transientProperty() throws {
        let random = SeededRandomSource(seed: 88)
        let bytes = try random.bytes(count: 1000)
        for byte in bytes {
            let failure: LayerFailure
            if byte % 2 == 0 {
                // Tầng 2 (refresh) transient.
                let oauth: OAuthError =
                    byte % 4 == 0 ? .server(status: 503) : .network(.timedOut)
                failure = layerFailure(for: .oauth(oauth))
            } else {
                // Tầng 3 (probe) transient.
                let probe: ProbeError = byte % 3 == 0 ? .rateLimited : .network(.notConnectedToInternet)
                failure = layerFailure(for: probe)
            }
            #expect(status(for: failure, warnings: []) == .unreachable)
        }
    }
}
