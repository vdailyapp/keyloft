import Foundation
import VaultDomain

/// Registry provider cho toàn app (TokenVault tra cứu qua `ProviderRegistry`, không import
/// Providers). Giá trị tĩnh + discovery đã merge (nếu `refreshDiscovery` chạy thành công).
public actor ProviderCatalog: ProviderRegistry {
    public static let builtIn: [Provider] = [.google, .microsoft, .dropbox]

    private var providers: [ProviderID: Provider]
    private let discovery: OIDCDiscovery?

    public init(
        providers: [Provider] = ProviderCatalog.builtIn,
        discovery: OIDCDiscovery? = nil
    ) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.discovery = discovery
    }

    public func provider(_ id: ProviderID) async throws -> Provider {
        guard let provider = providers[id] else {
            throw DomainError.notFound("provider:\(id.rawValue)")
        }
        return provider
    }

    /// Tải discovery cho mọi provider có `discoveryURL`; lỗi mạng/decode → giữ giá trị tĩnh
    /// (refreshDiscovery không throw để scheduler gọi định kỳ).
    public func refreshDiscovery() async {
        guard let discovery else { return }
        for var provider in providers.values {
            guard let url = provider.discoveryURL else { continue }
            do {
                let doc = try await discovery.fetch(url)
                let merged = OIDCDiscovery.merge(provider, doc)
                providers[provider.id] = merged
                provider = merged
            } catch {
                // Giữ tĩnh — discovery chỉ là nguồn cập nhật, không phải nguồn sự thật.
                continue
            }
        }
    }
}
