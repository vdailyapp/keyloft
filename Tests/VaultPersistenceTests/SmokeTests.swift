import Testing
@testable import VaultPersistence

@Suite("VaultPersistence smoke")
struct VaultPersistenceSmokeTests {
    @Test("U1: target VaultPersistence import và build được")
    func targetBuilds() {
        #expect(VaultPersistence.version == "0.1.0")
    }
}
