import SwiftUI
import VaultDomain
import VaultRuntime

struct AccountDetailView: View {
    let accountId: AccountID
    @Environment(AppContainer.self) private var container
    @State private var model: AccountDetailModel?

    var body: some View {
        Group {
            if let model {
                AccountDetailContent(model: model) { account in
                    Task {
                        _ = await container.runtime.scheduler.run(.manual(account))
                        await model.load()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                self.model = AccountDetailModel(runtime: container.runtime, accountId: accountId)
            }
            await model?.load()
        }
    }
}

private struct AccountDetailContent: View {
    let model: AccountDetailModel
    let checkNow: (AccountID) -> Void
    @State private var ackWide = false

    var body: some View {
        Form {
            if let account = model.account {
                LabeledContent("Provider", value: account.providerId.rawValue)
                LabeledContent("Email", value: account.email ?? "-")
                LabeledContent("Trạng thái", value: account.status.rawValue)
                LabeledContent("ID", value: account.id.description)

                Section("Hành động") {
                    Button(primaryLabel) {
                        Task { await model.runPrimary() }
                    }
                    .disabled(model.primary == .none)

                    Button("Check now") {
                        checkNow(model.accountId)
                    }
                }

                Section("Credential") {
                    ForEach(model.credentials, id: \.id) { credential in
                        HStack {
                            Text(credential.id.description)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(credential.status.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Thu hồi / Xóa") {
                    Toggle(
                        "Thu hồi Google sẽ đăng xuất MỌI tài khoản của app này",
                        isOn: $ackWide
                    )
                    Button("Thu hồi credential") {
                        Task { await model.revokeActive() }
                    }
                    Button("Xóa account", role: .destructive) {
                        Task { await model.remove(ack: ackWide) }
                    }
                }

                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var primaryLabel: String {
        switch model.primary {
        case .none: "Không cần làm gì"
        case .reauth: "Đăng nhập lại"
        case .grantMore: "Cấp thêm quyền"
        case .retry: "Thử lại"
        case .fixClient: "Sửa OAuth client"
        case .openDetails: "Xem chi tiết"
        }
    }
}
