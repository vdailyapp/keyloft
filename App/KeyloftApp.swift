import AppKit
import SwiftUI
import VaultRuntime

@main
struct KeyloftApp: App {
    @State private var container: AppContainer?
    @State private var bootstrapError: String?

    var body: some Scene {
        MenuBarExtra("Keyloft", systemImage: "key.horizontal") {
            if let container {
                MenuBarView().environment(container)
            } else {
                Text(bootstrapError ?? "Lỗi khởi tạo")
                Button("Thoát") { NSApplication.shared.terminate(nil) }
            }
        }
        Window("Keyloft", id: "main") {
            Group {
                if let container {
                    MainWindow(container: container)
                } else {
                    ContentUnavailableView(
                        "Không mở được vault",
                        systemImage: "exclamationmark.triangle",
                        description: Text(bootstrapError ?? "Lỗi không xác định")
                    )
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
        Settings {
            SettingsView()
        }
    }

    init() {
        do {
            let container = try AppContainer()
            self._container = State(initialValue: container)
            container.start()
        } catch {
            // Không crash: hiện lỗi trong menu bar + cửa sổ chính.
            self._bootstrapError = State(
                initialValue: "Vault chưa khởi tạo được: \(describe(error))")
        }
    }

    private func describe(_ error: Error) -> String {
        if let runtimeError = error as? RuntimeError {
            switch runtimeError {
            case .vaultNotInitialized:
                return "chưa có vault"
            case .keychainUnavailable(let hint):
                return "Keychain không dùng được (\(hint))"
            }
        }
        return error.localizedDescription
    }
}

struct MainWindow: View {
    let container: AppContainer
    @State private var selection: SidebarItem? = .accounts

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            // T26 đã thay Accounts; T27/T28 thay nốt các mục còn lại.
            switch selection ?? .accounts {
            case .accounts:
                NavigationStack { AccountsView() }
            case .providers, .secrets, .health, .audit:
                PlaceholderView(title: selection?.rawValue ?? "Accounts")
            }
        }
        .environment(container)
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Cài đặt chi tiết thuộc giai đoạn sau.")
        }
        .frame(width: 380, height: 160)
    }
}
