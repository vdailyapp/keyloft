import Foundation
import Observation
import TokenVault
import VaultDomain
import VaultRuntime

struct OAuthClientRow: Identifiable, Equatable {
    let id: OAuthClientID
    let provider: ProviderID
    let label: String
    let clientId: String
    let redirectURI: URL
    let hasSecret: Bool
    let secretExpiresAt: Date?
}

/// Giá trị form tạo/sửa OAuth client. `clientSecret` chỉ sống ở đây tới khi lưu xong —
/// view phải xóa ngay sau khi gọi save, model không giữ lại.
struct OAuthClientFormValues: Equatable {
    var label: String = ""
    var clientID: String = ""
    var clientSecret: String = ""
    var redirectURI: String = "http://127.0.0.1/callback"
    var secretExpiresAt: Date? = nil
}

enum OAuthClientFormError: Error, Equatable {
    case missingClientID
    case invalidRedirectURI
    /// Dropbox đòi redirect có cổng cố định (app không đoán được port người dùng đăng ký).
    case dropboxRedirectNeedsPort
    /// Microsoft secret có hạn — bắt buộc khai báo ngày hết hạn.
    case microsoftNeedsSecretExpiry
}

/// Validate form OAuth client (hàm thuần): redirect chỉ nhận loopback http://127.0.0.1,
/// Dropbox phải có port, Microsoft phải có ngày hết hạn secret.
func validateOAuthClientForm(
    _ values: OAuthClientFormValues, provider: ProviderID
) -> OAuthClientFormError? {
    guard !values.clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
        return .missingClientID
    }
    guard
        let url = URL(string: values.redirectURI.trimmingCharacters(in: .whitespaces)),
        url.scheme == "http", url.host == "127.0.0.1", url.path == "/callback"
    else { return .invalidRedirectURI }
    if provider == .dropbox, url.port == nil { return .dropboxRedirectNeedsPort }
    if provider == .microsoft, values.secretExpiresAt == nil {
        return .microsoftNeedsSecretExpiry
    }
    return nil
}

/// CRUD OAuth client cho mục Providers. Secret người nhập lưu qua SecretVault
/// (kind `.clientSecret`), DB chỉ giữ `clientSecretRef`.
@MainActor
@Observable
final class OAuthClientsModel {
    private(set) var rows: [OAuthClientRow] = []
    private(set) var error: String?
    /// Chặn xóa khi còn account phụ thuộc: "Còn N account dùng client này".
    private(set) var deletionBlockedMessage: String?

    private let runtime: VaultRuntime
    /// VaultRuntime không expose `ids` — model dùng generator riêng (UUID v4 toàn cục).
    private let ids: any IDGenerator = SystemIDGenerator()

    init(runtime: VaultRuntime) {
        self.runtime = runtime
    }

    func load() async {
        error = nil
        do {
            rows = try await runtime.clients.list(provider: nil).map(Self.row)
        } catch {
            self.error = "\(error)"
        }
    }

    /// Tạo mới (`updating == nil`) hoặc sửa row có sẵn. Secret non-empty → tạo Secret mới
    /// (kind `.clientSecret`) và thay `clientSecretRef`; giá trị không được giữ lại ở model.
    func save(
        provider: ProviderID, values: OAuthClientFormValues, updating row: OAuthClientRow? = nil
    ) async {
        error = nil
        if let problem = validateOAuthClientForm(values, provider: provider) {
            self.error = "\(problem)"
            return
        }
        guard
            let redirect = URL(string: values.redirectURI.trimmingCharacters(in: .whitespaces))
        else {
            self.error = "Redirect URI không phân tích được"
            return
        }
        do {
            let existing: OAuthClient? =
                if let row { try await runtime.clients.get(row.id) } else { nil }
            let trimmedID = values.clientID.trimmingCharacters(in: .whitespaces)
            let trimmedLabel = values.label.trimmingCharacters(in: .whitespaces)

            var secretRef = existing?.clientSecretRef
            if !values.clientSecret.isEmpty {
                let secret = try await runtime.secrets.create(
                    kind: .clientSecret,
                    label: "Client secret \(provider.rawValue) \(trimmedLabel.isEmpty ? trimmedID : trimmedLabel)",
                    value: Data(values.clientSecret.utf8),
                    actor: .user)
                secretRef = secret.id
            }

            if let existing {
                var updated = existing
                updated.label = trimmedLabel.isEmpty ? trimmedID : trimmedLabel
                updated.redirectURI = redirect
                updated.secretExpiresAt = values.secretExpiresAt
                if let secretRef { updated.clientSecretRef = secretRef }
                try await runtime.clients.save(updated)
                // Secret cũ bị thay thế → xóa giá trị khỏi Keychain (metadata giữ để audit).
                if let oldRef = existing.clientSecretRef, let secretRef, oldRef != secretRef {
                    try await runtime.secrets.delete(oldRef, actor: .user)
                }
            } else {
                let client = OAuthClient(
                    id: OAuthClientID(rawValue: ids.make()),
                    providerId: provider,
                    clientId: trimmedID,
                    clientSecretRef: secretRef,
                    redirectURI: redirect,
                    secretExpiresAt: values.secretExpiresAt,
                    label: trimmedLabel.isEmpty ? trimmedID : trimmedLabel,
                    createdAt: runtime.clock.now())
                try await runtime.clients.save(client)
            }
        } catch {
            self.error = "\(error)"
            return
        }
        await load()
    }

    /// Xóa client; còn account phụ thuộc → chặn với thông báo số account.
    func delete(_ clientId: OAuthClientID) async {
        deletionBlockedMessage = nil
        do {
            let dependents = try await runtime.accounts.list()
                .filter { $0.oauthClientId == clientId }.count
            guard dependents == 0 else {
                deletionBlockedMessage = "Còn \(dependents) account dùng client này"
                return
            }
            try await runtime.clients.delete(clientId)
        } catch {
            self.error = "\(error)"
            return
        }
        await load()
    }

    private static func row(_ client: OAuthClient) -> OAuthClientRow {
        OAuthClientRow(
            id: client.id,
            provider: client.providerId,
            label: client.label,
            clientId: client.clientId,
            redirectURI: client.redirectURI,
            hasSecret: client.clientSecretRef != nil,
            secretExpiresAt: client.secretExpiresAt)
    }
}
