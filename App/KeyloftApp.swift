import AppKit
import SwiftUI
import VaultRuntime

@main
struct KeyloftApp: App {
    @State private var container: AppContainer?
    @State private var bootstrapError: String?

    var body: some Scene {
        MenuBarExtra("Keyloft", systemImage: "key.horizontal") {
            MenuBarContent(container: container, bootstrapError: bootstrapError)
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

struct MenuBarContent: View {
    let container: AppContainer?
    let bootstrapError: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let container {
            // Nội dung menu bar thật (badge, danh sách account, Check now) lắp ở T26.
            Text("Keyloft đang chạy")
            Divider()
            Button("Mở Keyloft") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Thoát") {
                container.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } else {
            Text(bootstrapError ?? "Lỗi khởi tạo")
            Button("Thoát") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

struct MainWindow: View {
    let container: AppContainer
    @State private var selection: SidebarItem? = .accounts
    @State private var showDebugSheet = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            // T25: mọi mục dùng placeholder; T26–T28 thay từng mục.
            (selection ?? .accounts).view
        }
        .overlay(alignment: .bottomTrailing) {
            #if DEBUG
            Button("Debug: thêm Google") { showDebugSheet = true }
                .padding()
            .sheet(isPresented: $showDebugSheet) {
                DebugAddAccountSheet(container: container)
            }
            #endif
        }
        .environment(container)
    }
}

#if DEBUG
/// Nút debug T25: thêm account Google bằng client ID nhập tay (luồng login thật).
struct DebugAddAccountSheet: View {
    let container: AppContainer
    @State private var clientId = ""
    @State private var result: String?
    @State private var running = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thêm account Google (debug)").font(.headline)
            TextField("Client ID (.apps.googleusercontent.com)", text: $clientId)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 380)
            if let result {
                Text(result).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button("Đóng") { dismiss() }
                Spacer()
                Button("Đăng nhập") {
                    running = true
                    Task {
                        result = await container.debugAddGoogleAccount(clientId: clientId)
                        running = false
                    }
                }
                .disabled(running || clientId.isEmpty)
            }
        }
        .padding()
    }
}
#endif

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Cài đặt chi tiết thuộc giai đoạn sau.")
        }
        .frame(width: 380, height: 160)
    }
}
