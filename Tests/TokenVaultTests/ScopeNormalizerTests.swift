import Foundation
import KeyloftTestSupport
import Testing
import TokenVault
import VaultDomain

@Suite("ScopeNormalizer")
struct ScopeNormalizerTests {
    @Test("U10: Google alias — granted chứa cả dạng dài, denied rỗng")
    func googleAlias() {
        let requested: ScopeSet = ["openid", "email"]
        let granted = ScopeNormalizer.granted(
            responseScope: "openid https://www.googleapis.com/auth/userinfo.email",
            requested: requested,
            provider: TestData.googleProvider)
        #expect(granted == ScopeNormalizer.canonical(requested, provider: TestData.googleProvider))
        #expect(
            ScopeNormalizer.canonical(requested, provider: TestData.googleProvider)
                .missing(in: granted).isEmpty)
    }

    @Test("U11: Microsoft unechoed offline_access + response nil → cấp đủ")
    func microsoftUnechoedAndNil() {
        let provider = TestData.microsoftProvider
        let requested: ScopeSet = ["openid", "offline_access", "Files.Read"]
        let granted = ScopeNormalizer.granted(
            responseScope: "Files.Read openid", requested: requested, provider: provider)
        #expect(granted.contains("offline_access"))

        let nilResponse = ScopeNormalizer.granted(
            responseScope: nil, requested: requested, provider: provider)
        #expect(nilResponse == ScopeNormalizer.canonical(requested, provider: provider))
    }
}
