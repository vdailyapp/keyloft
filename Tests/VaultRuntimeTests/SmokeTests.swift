import Testing

@testable import VaultRuntime

@Suite("VaultRuntime smoke")
struct VaultRuntimeSmokeTests {
    @Test("U1: target VaultRuntime import và build được")
    func targetBuilds() {
        #expect(VaultRuntime.version == "0.1.0")
    }
}
