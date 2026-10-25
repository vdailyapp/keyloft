import Foundation
import VaultDomain

public enum SelectorError: Error, Equatable {
    case notFound(String)
    case ambiguous([Account])
}

/// Chọn account theo: UUID đầy đủ, tiền tố UUID ≥ 4 ký tự, email (không phân biệt hoa
/// thường), hoặc `provider:email`.
public enum AccountSelector {
    public static func resolve(_ query: String, in accounts: [Account]) -> Result<Account, SelectorError> {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .failure(.notFound(query))
        }

        // UUID đầy đủ.
        if let uuid = UUID(uuidString: trimmed),
            let exact = accounts.first(where: { $0.id.rawValue == uuid })
        {
            return .success(exact)
        }

        // Tiền tố UUID (≥ 4 ký tự hex).
        if trimmed.count >= 4, trimmed.allSatisfy({ $0.isHexDigit }),
            trimmed.range(of: "^[0-9a-fA-F-]+$", options: .regularExpression) != nil
        {
            let prefix = trimmed.lowercased()
            let matches = accounts.filter {
                $0.id.rawValue.uuidString.lowercased().hasPrefix(prefix)
            }
            switch matches.count {
            case 1: return .success(matches[0])
            case 0: return .failure(.notFound(query))
            default: return .failure(.ambiguous(matches))
            }
        }

        // provider:email hoặc email.
        if let colon = trimmed.firstIndex(of: ":") {
            let providerPart = String(trimmed[..<colon])
            let emailPart = String(trimmed[trimmed.index(after: colon)...]).lowercased()
            if let provider = ProviderID(rawValue: providerPart.lowercased()) {
                let matches = accounts.filter {
                    $0.providerId == provider && $0.email?.lowercased() == emailPart
                }
                switch matches.count {
                case 1: return .success(matches[0])
                case 0: return .failure(.notFound(query))
                default: return .failure(.ambiguous(matches))
                }
            }
        }

        let email = trimmed.lowercased()
        let matches = accounts.filter { $0.email?.lowercased() == email }
        switch matches.count {
        case 1: return .success(matches[0])
        case 0: return .failure(.notFound(query))
        default: return .failure(.ambiguous(matches))
        }
    }
}
