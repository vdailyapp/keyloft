import SwiftUI
import VaultDomain
import VaultRuntime

/// Form tạo/sửa OAuth client. Secret đi qua SecureField và bị xóa khỏi state ngay sau
/// khi lưu (thành công lẫn thất bại) — không giữ giá trị nhạy cảm trên UI.
struct OAuthClientForm: View {
    let model: OAuthClientsModel
    let editing: OAuthClientRow?

    @Environment(\.dismiss) private var dismiss
    @State private var provider: ProviderID = .google
    @State private var label = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var redirectURI = "http://127.0.0.1/callback"
    @State private var hasExpiry = false
    @State private var secretExpiresAt = Date(timeIntervalSinceNow: 90 * 24 * 3600)
    @State private var saving = false

    private var values: OAuthClientFormValues {
        OAuthClientFormValues(
            label: label, clientID: clientID, clientSecret: clientSecret,
            redirectURI: redirectURI, secretExpiresAt: hasExpiry ? secretExpiresAt : nil)
    }

    private var problem: OAuthClientFormError? {
        validateOAuthClientForm(values, provider: provider)
    }

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Text(id.rawValue).tag(id)
                }
            }
            .disabled(editing != nil)

            TextField("Tên gợi nhớ", text: $label)
            TextField("Client ID", text: $clientID)
                .disabled(editing != nil)
            SecureField("Client secret (tùy chọn)", text: $clientSecret)
            TextField("Redirect URI", text: $redirectURI)
            if provider == .dropbox {
                Label(
                    "Dropbox đòi redirect có cổng cố định, vd http://127.0.0.1:53682/callback",
                    systemImage: "number")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("Secret có ngày hết hạn", isOn: $hasExpiry)
            if hasExpiry {
                DatePicker("Hết hạn", selection: $secretExpiresAt, displayedComponents: .date)
            }
            if provider == .microsoft {
                Label(
                    "Microsoft secret có hạn — bắt buộc khai báo ngày hết hạn.",
                    systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hướng dẫn") {
                Link(
                    "Tạo client cho \(provider.rawValue)",
                    destination: provider.clientSetupURL)
                if provider == .google {
                    Label(
                        "Chuyển app sang In production, nếu không token hết hạn sau 7 ngày.",
                        systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                }
            }

            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 460)
        .navigationTitle(editing == nil ? "Thêm OAuth client" : "Sửa OAuth client")
        .onAppear(perform: prefill)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Hủy") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    Task { await save() }
                }
                .disabled(problem != nil || saving)
            }
        }
    }

    private func prefill() {
        guard let editing else { return }
        provider = editing.provider
        label = editing.label
        clientID = editing.clientId
        redirectURI = editing.redirectURI.absoluteString
        if let expiry = editing.secretExpiresAt {
            hasExpiry = true
            secretExpiresAt = expiry
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        await model.save(provider: provider, values: values, updating: editing)
        // Xóa secret khỏi state ngay sau khi lưu, kể cả khi lưu lỗi.
        clientSecret = ""
        guard model.error == nil else { return }
        dismiss()
    }
}
