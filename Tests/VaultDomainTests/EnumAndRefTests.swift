import Foundation
import Testing

@testable import VaultDomain

@Suite("Enum & KeychainRef")
struct EnumAndRefTests {
    @Test("U10: severity đúng thứ tự needsReauth > needsConsent > unreachable > degraded > healthy")
    func severityOrder() {
        #expect(AccountStatus.needsReauth.severity > AccountStatus.needsConsent.severity)
        #expect(AccountStatus.needsConsent.severity > AccountStatus.unreachable.severity)
        #expect(AccountStatus.unreachable.severity > AccountStatus.degraded.severity)
        #expect(AccountStatus.degraded.severity > AccountStatus.healthy.severity)
        #expect(AccountStatus.healthy.severity == 0)
        #expect(AccountStatus.needsReauth.severity == 4)
    }

    @Test("U11: KeychainRef định dạng <kind>.<uuid lowercase>, service cố định")
    func keychainRefFormat() {
        let id = SecretID(
            rawValue: UUID(uuidString: "6F1C0D6A-8B44-4E4A-9C1D-2B6A0F99B211")!)
        let ref = KeychainRef(kind: .refreshToken, id: id)
        #expect(ref.account == "refreshToken.6f1c0d6a-8b44-4e4a-9c1d-2b6a0f99b211")
        #expect(KeychainRef.service == "app.vdaily.keyloft")
    }
}
