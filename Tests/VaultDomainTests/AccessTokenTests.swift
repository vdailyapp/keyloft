import Foundation
import Testing

@testable import VaultDomain

@Suite("AccessToken")
struct AccessTokenTests {
    @Test("U8: description/debugDescription không lộ value")
    func redacted() {
        let token = AccessToken(
            value: "SUPER-SECRET-VALUE", scopes: ["openid"], expiresAt: Date(timeIntervalSince1970: 1))
        #expect(!("\(token)".contains("SUPER-SECRET-VALUE")))
        #expect(!String(reflecting: token).contains("SUPER-SECRET-VALUE"))
        #expect("\(token)".contains("<redacted>"))
    }

    @Test("U9: isValid biên minValidity")
    func validityBoundary() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let exact = AccessToken(value: "x", scopes: [], expiresAt: now.addingTimeInterval(60))
        let over = AccessToken(value: "x", scopes: [], expiresAt: now.addingTimeInterval(61))
        #expect(!exact.isValid(at: now, minValidity: 60))
        #expect(over.isValid(at: now, minValidity: 60))
    }
}
