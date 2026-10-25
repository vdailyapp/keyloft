import Testing
@testable import SecretVault

@Suite("SecretVault smoke")
struct SecretVaultSmokeTests {
    @Test("U1: target SecretVault import và build được")
    func targetBuilds() {
        #expect(SecretVault.version == "0.1.0")
    }
}
