import SwiftUI
import VaultDomain
import VaultRuntime

/// Mục Audit: bảng event mới nhất trước + bộ lọc account / action / thời gian.
struct AuditView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: AuditModel?

    var body: some View {
        Group {
            if let model {
                AuditContent(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                self.model = AuditModel(runtime: container.runtime)
            }
            await model?.load()
        }
    }
}

private struct AuditContent: View {
    @Bindable var model: AuditModel
    /// AuditAction không CaseIterable (VaultDomain) — danh sách lọc khai báo tường minh.
    private static let filterableActions: [AuditAction] = [
        .accountAdded, .accountRemoved, .accountStatusChanged,
        .credentialIssued, .credentialSuperseded, .credentialRevoked,
        .tokenRefreshed, .tokenRefreshFailed, .tokenIssued,
        .scopeGranted, .scopeDenied, .scopeReduced,
        .secretCreated, .secretRead, .secretRotated, .secretDeleted,
        .oauthClientCreated, .oauthClientDeleted,
    ]

    var body: some View {
        List {
            Section("Bộ lọc") {
                Picker("Hành động", selection: $model.filterAction) {
                    Text("Tất cả").tag(AuditAction?.none)
                    ForEach(Self.filterableActions, id: \.self) { action in
                        Text(action.rawValue).tag(AuditAction?.some(action))
                    }
                }
                Picker("Account", selection: $model.filterAccount) {
                    Text("Tất cả").tag(AccountID?.none)
                    ForEach(model.accounts) { account in
                        Text(account.email ?? account.externalId)
                            .tag(AccountID?.some(account.id))
                    }
                }
                Picker("Thời gian", selection: $model.filterRange) {
                    ForEach(AuditModel.TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
            }
            Section("Sự kiện") {
                ForEach(model.rows) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.action.rawValue)
                                .font(.callout.monospaced())
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(event.target)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            resultLabel(event.result)
                        }
                    }
                }
            }
        }
        .onChange(of: model.filterAction) { _, _ in
            Task { await model.load() }
        }
        .onChange(of: model.filterAccount) { _, _ in
            Task { await model.load() }
        }
        .onChange(of: model.filterRange) { _, _ in
            Task { await model.load() }
        }
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.footnote)
        }
    }

    @ViewBuilder
    private func resultLabel(_ result: AuditResult) -> some View {
        switch result {
        case .success:
            Label("ok", systemImage: "checkmark.circle")
                .foregroundStyle(.green).font(.caption)
        case .failure(let reason):
            Label(reason.isEmpty ? "lỗi" : reason, systemImage: "xmark.circle")
                .foregroundStyle(.red).font(.caption)
                .lineLimit(1)
        }
    }
}
