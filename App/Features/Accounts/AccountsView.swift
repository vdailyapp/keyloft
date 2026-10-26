import SwiftUI
import TokenVault
import VaultDomain
import VaultRuntime

struct AccountsView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: AccountsModel?
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if let model {
                AccountsContent(model: model, showAddSheet: $showAddSheet)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                let model = AccountsModel(runtime: container.runtime)
                self.model = model
            }
            await model?.load()
            model?.observeUpdates()
        }
        .sheet(isPresented: $showAddSheet) {
            if let model {
                AddAccountFlow(model: model)
            }
        }
    }
}

private struct AccountsContent: View {
    let model: AccountsModel
    @Binding var showAddSheet: Bool
    @State private var selectedAccount: AccountID?

    var body: some View {
        List(selection: $selectedAccount) {
            ForEach(model.rows) { row in
                NavigationLink(value: row.id) {
                    HStack {
                        Image(systemName: row.provider.systemImage)
                        VStack(alignment: .leading) {
                            Text(row.email ?? row.externalIdText)
                            Text(row.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        MenuBarBadgeIcon(badge: MenuBarBadge.from([row.status]))
                    }
                }
            }
        }
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "Chưa có account",
                    systemImage: "person.2",
                    description: Text("Thêm OAuth client ở Providers rồi bấm + để đăng nhập.")
                )
            }
        }
        .navigationDestination(for: AccountID.self) { id in
            AccountDetailView(accountId: id)
        }
        .toolbar {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.footnote)
        }
    }
}

extension AccountRow {
    var externalIdText: String { "…" }
}

extension ProviderID {
    var systemImage: String {
        switch self {
        case .google: "g.circle"
        case .microsoft: "m.circle"
        case .dropbox: "drop.circle"
        }
    }
}

/// Luồng thêm account: chọn provider → client → login qua ScopeService.
struct AddAccountFlow: View {
    let model: AccountsModel
    @State private var choices: [(ProviderID, [OAuthClient])] = []
    @State private var selectedClient: OAuthClient?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Thêm account").font(.headline)
            if choices.isEmpty {
                Text("Chưa có OAuth client — mở mục Providers để tạo trước.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(choices, id: \.0) { provider, clients in
                    Text(provider.rawValue).font(.subheadline).foregroundStyle(.secondary)
                    ForEach(clients, id: \.id) { client in
                        Button {
                            selectedClient = client
                        } label: {
                            HStack {
                                Text(client.label)
                                Spacer()
                                Text(client.clientId).font(.caption).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
            HStack {
                Button("Đóng") { dismiss() }
                Spacer()
                if model.adding {
                    ProgressView()
                }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
        .task {
            choices = await model.clientsForAdd
        }
        .onChange(of: selectedClient) { _, client in
            guard let client else { return }
            Task {
                await model.add(provider: client.providerId, client: client.id)
                dismiss()
            }
        }
    }
}
