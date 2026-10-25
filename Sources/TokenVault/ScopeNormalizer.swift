import Foundation
import VaultDomain

/// Chuẩn hóa scope giữa "đã xin" và "được cấp": provider trả scope dạng URL dài (Google),
/// không echo lại scope mặc định (Microsoft offline_access), hoặc không trả scope nào.
public enum ScopeNormalizer {
    /// Canonical hóa theo `quirks.scopeAliases` (short → canonical), rồi cộng thêm
    /// `requested ∩ unechoedScopes` (scope provider không echo nhưng thật sự đã cấp).
    public static func canonical(_ scopes: ScopeSet, provider: Provider) -> ScopeSet {
        let mapped = scopes.values.map { provider.quirks.scopeAliases[$0] ?? $0 }
        let base = ScopeSet(mapped)
        let silent = scopes.values.filter { provider.quirks.unechoedScopes.contains($0) }
        return base.union(ScopeSet(silent))
    }

    /// Scope thực được cấp từ token response — giữ nguyên dạng provider trả về (không
    /// un-alias), cộng thêm scope không echo nhưng thuộc requested (Microsoft offline_access).
    /// `responseScope == nil` → RFC 6749 §5.1: coi như cấp đủ `requested` (đã canonical).
    public static func granted(responseScope: String?, requested: ScopeSet, provider: Provider) -> ScopeSet {
        guard let responseScope else {
            return canonical(requested, provider: provider)
        }
        let granted = ScopeSet(spaceDelimited: responseScope)
        let silent = canonical(requested, provider: provider).values.filter {
            provider.quirks.unechoedScopes.contains($0)
        }
        return granted.union(ScopeSet(silent))
    }
}
