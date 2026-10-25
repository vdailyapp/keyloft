import Testing

@testable import HealthCheck

@Suite("HealthCheck smoke")
struct HealthCheckSmokeTests {
    @Test("U1: target HealthCheck import và build được")
    func targetBuilds() {
        #expect(HealthCheck.version == "0.1.0")
    }
}
