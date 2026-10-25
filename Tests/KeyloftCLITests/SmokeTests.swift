import Testing

@testable import KeyloftCLI

@Suite("KeyloftCLI smoke")
struct KeyloftCLISmokeTests {
    @Test("U1: CLI target build được, version 0.1.0")
    func cliBuilds() {
        #expect(Keyloft.configuration.version == "0.1.0")
    }
}
