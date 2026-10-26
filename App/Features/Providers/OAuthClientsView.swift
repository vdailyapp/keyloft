import SwiftUI
import VaultDomain
import VaultRuntime

extension ProviderID {
    /// Link hướng dẫn tạo OAuth client của từng provider.
    var clientSetupURL: URL {
        switch self {
        case .google: URL(string: "https://console.cloud.google.com/apis/credentials")!
        case .microsoft:
            URL(
                string:
                    "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
            )!
        case .dropbox: URL(string: "https://www.dropbox.com/developers/apps")!
        }
    }
}

struct OAuthClientsView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: OAuthClientsModel?
    @State private var showForm = false
    @State private var editingClient: OAuthClientRow?

    var body: some View {
        Group {
            if let model {
                OAuthClientsContent(
                    model: model, showForm: $showForm, editingClient: $editingClient)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                self.model = OAuthClientsModel(runtime: container.runtime)
            }
            await model?.load()
        }
        .sheet(isPresented: $showForm) {
            if let model {
                OAuthClientForm(model: model, editing: editingClient)
            }
        }
    }
}

private struct OAuthClientsContent: View {
    let model: OAuthClientsModel
    @Binding var showForm: Bool
    @Binding var editingClient: OAuthClientRow?
    @State private var deletingClient: OAuthClientRow?

    var body: some View {
        List {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                let clients = model.rows.filter { $0.provider == provider }
                if !clients.isEmpty {
                    Section(provider.rawValue) {
                        ForEach(clients) { row in
                            clientRow(row)
                        }
                    }
                }
            }
        }
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "Chưa có OAuth client",
                    systemImage: "appclip",
                    description: Text("Bấm + để thêm client cho provider bạn dùng.")
                )
            }
        }
        .toolbar {
            Button {
                editingClient = nil
                showForm = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .confirmationDialog(
            "Xóa OAuth client", isPresented: .init(get: { deletingClient != nil },
                                                     set: { if !$0 { deletingClient = nil } }),
            titleVisibility: .visible
        ) {
            if let row = deletingClient {
                Button("Xóa \(row.label)", role: .destructive) {
                    Task { await model.delete(row.id) }
                }
            }
            Button("Hủy", role: .cancel) {}
        }
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.footnote)
        }
        if let message = model.deletionBlockedMessage {
            Text(message).foregroundStyle(.orange).font(.footnote)
        }
    }

    private func clientRow(_ row: OAuthClientRow) -> some View {
        HStack {
            Image(systemName: row.provider.systemImage)
            VStack(alignment: .leading) {
                Text(row.label)
                HStack(spacing: 6) {
                    Text(row.clientId)
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    if row.hasSecret {
                        Image(systemName: "checkmark.shield")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let expiry = row.secretExpiresAt {
                Text(expiry, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Sửa…") {
                editingClient = row
                showForm = true
            }
            Button("Xóa…", role: .destructive) {
                deletingClient = row
            }
        }
    }
}
