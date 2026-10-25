import Testing
@testable import VaultDomain

@Suite("VaultDomain smoke")
struct VaultDomainSmokeTests {
    @Test("U1: target VaultDomain import và build được")
    func targetBuilds() {
        #expect(VaultDomain.version == "0.1.0")
    }
}
