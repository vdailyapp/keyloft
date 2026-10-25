import Testing

@testable import TokenVault

@Suite("TokenVault smoke")
struct TokenVaultSmokeTests {
    @Test("U1: target TokenVault import và build được")
    func targetBuilds() {
        #expect(TokenVault.version == "0.1.0")
    }
}
