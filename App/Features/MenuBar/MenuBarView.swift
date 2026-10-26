import SwiftUI
import VaultDomain
import VaultRuntime

/// Model menu bar: tổng hợp trạng thái account + hành động nhanh.
@MainActor
@Observable
final class MenuBarModel {
    private(set) var rows: [Account] = []
    private(set) var latest: [AccountID: HealthCheckResult] = [:]
    private(set) var error: String?

    private let runtime: VaultRuntime
    private var observer: Task<Void, Never>?

    init(runtime: VaultRuntime) {
        self.runtime = runtime
    }

    var badge: MenuBarBadge {
        MenuBarBadge.from(rows.map(\.status))
    }

    func load() async {
        error = nil
        do {
            rows = try await runtime.accounts.list()
            for account in rows {
                latest[account.id] = try await runtime.healthResults.latest(for: account.id)
            }
        } catch {
            self.error = "\(error)"
        }
    }

    /// Lắng nghe kết quả check mới (không cần load lại).
    func observeUpdates() {
        observer?.cancel()
        observer = Task { [weak self] in
            guard let updates = await self?.runtime.scheduler.updates else { return }
            for await result in updates {
                await MainActor.run {
                    self?.apply(result)
                }
            }
        }
    }

    private func apply(_ result: HealthCheckResult) {
        latest[result.accountId] = result
        if let index = rows.firstIndex(where: { $0.id == result.accountId }) {
            rows[index].status = result.status
        }
    }

    /// "Check now" từ menu bar.
    func checkAll() async {
        do {
            _ = try await runtime.scheduler.run(.manual(nil))
        } catch {
            await load()  // load() xóa error — gán lỗi SAU load
            self.error = "\(error)"
            return
        }
        await load()
    }

    func stopObserving() {
        observer?.cancel()
        observer = nil
    }
}

struct MenuBarBadgeIcon: View {
    let badge: MenuBarBadge

    var body: some View {
        Image(systemName: badge.systemImage)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch badge {
        case .none: .primary
        case .yellow: .yellow
        case .gray: .secondary
        case .orange: .orange
        case .red: .red
        }
    }
}

struct MenuBarView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: MenuBarModel?

    var body: some View {
        Group {
            if let model {
                MenuBarContent(model: model, container: container)
            } else {
                ProgressView()
            }
        }
        .task {
            let model = MenuBarModel(runtime: container.runtime)
            self.model = model
            await model.load()
            model.observeUpdates()
        }
    }
}

private struct MenuBarContent: View {
    let model: MenuBarModel
    let container: AppContainer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarBadgeIcon(badge: model.badge)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let error = model.error {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
        }
        if model.rows.isEmpty {
            Text("Chưa có account")
        } else {
            ForEach(model.rows, id: \.id) { account in
                AccountRowMenu(account: account)
            }
        }
        Divider()
        Button("Check now") {
            Task { await model.checkAll() }
        }
        Button("Mở Keyloft") {
            openWindow(id: "main")
        }
        Divider()
        Button("Thoát") {
            container.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct AccountRowMenu: View {
    let account: Account

    var body: some View {
        HStack {
            Text(account.email ?? account.externalId)
            Spacer()
            MenuBarBadgeIcon(badge: MenuBarBadge.from([account.status]))
        }
    }
}
