import Foundation
import VaultDomain

/// Registry provider cho toàn app (TokenVault tra cứu qua `ProviderRegistry`, không import Providers).
public actor ProviderCatalog: ProviderRegistry {
    public static let builtIn: [Provider] = [.google, .microsoft, .dropbox]

    private var providers: [ProviderID: Provider]

    public init(providers: [Provider] = ProviderCatalog.builtIn) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func provider(_ id: ProviderID) async throws -> Provider {
        guard let provider = providers[id] else {
            throw DomainError.notFound("provider:\(id.rawValue)")
        }
        return provider
    }

    /// TODO(T18, SPEC-007 §3): tải discovery cho mọi provider có `discoveryURL`,
    /// merge an toàn (issuer phải khớp), lỗi → giữ giá trị tĩnh.
    public func refreshDiscovery() async {
        return
    }
}
