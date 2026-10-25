import Testing
@testable import Providers

@Suite("Providers smoke")
struct ProvidersSmokeTests {
    @Test("U1: target Providers import và build được")
    func targetBuilds() {
        #expect(Providers.version == "0.1.0")
    }
}
