import SwiftUI
import VaultDomain
import VaultRuntime

/// Mục Health: chọn account → lịch sử check (mới nhất trước), mở ra 5 tầng.
struct HealthHistoryView: View {
    @Environment(AppContainer.self) private var container
    @State private var accounts: [Account] = []
    @State private var error: String?
    @State private var selected: AccountID?

    var body: some View {
        List(selection: $selected) {
            ForEach(accounts) { account in
                NavigationLink(value: account.id) {
                    HStack {
                        Image(systemName: account.providerId.systemImage)
                        VStack(alignment: .leading) {
                            Text(account.email ?? account.externalId)
                            Text(account.status.rawValue)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if accounts.isEmpty {
                ContentUnavailableView(
                    "Chưa có account", systemImage: "person.2",
                    description: Text("Thêm account ở mục Accounts để xem health."))
            }
        }
        .navigationDestination(for: AccountID.self) { id in
            HealthHistoryDetail(accountId: id)
        }
        if let error {
            Text(error).foregroundStyle(.red).font(.footnote)
        }
    }
}

private struct HealthHistoryDetail: View {
    let accountId: AccountID
    @Environment(AppContainer.self) private var container
    @State private var model: HealthHistoryModel?

    var body: some View {
        Group {
            if let model {
                HealthHistoryContent(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                self.model = HealthHistoryModel(runtime: container.runtime, accountId: accountId)
            }
            await model?.load()
        }
    }
}

private struct HealthHistoryContent: View {
    let model: HealthHistoryModel

    var body: some View {
        List {
            ForEach(model.rows) { result in
                DisclosureGroup {
                    ForEach(Array(result.checks.enumerated()), id: \.offset) { _, item in
                        layerRow(item)
                    }
                } label: {
                    HStack {
                        MenuBarBadgeIcon(badge: MenuBarBadge.from([result.status]))
                        VStack(alignment: .leading) {
                            Text(result.status.rawValue)
                            Text(result.checkedAt, style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(result.checkedAt, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "Chưa có kết quả check", systemImage: "heart.text.square",
                    description: Text("Bấm Check now để chạy kiểm tra ngay."))
            }
        }
        .toolbar {
            Button("Check now") {
                Task { await model.checkNow() }
            }
        }
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.footnote)
        }
    }

    /// 5 tầng theo thứ tự checker chạy (tokenPresent → refresh → apiCall → scopes → earlyWarning).
    private func layerRow(_ item: HealthCheckItem) -> some View {
        HStack {
            Image(systemName: item.ok ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(item.ok ? Color.green : Color.red)
            Text(item.name.rawValue)
            Spacer()
            ForEach(Array(item.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let latency = item.latencyMs {
                Text("\(latency) ms")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = item.error {
                Text(error)
                    .font(.caption).foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }
}
