import SwiftUI
import SecretVault
import VaultDomain
import VaultRuntime

struct SecretsView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: SecretsModel?
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if let model {
                if model.needsUnlock {
                    UnlockGate(model: model)
                } else {
                    SecretsContent(model: model, showAddSheet: $showAddSheet)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                self.model = SecretsModel(runtime: container.runtime)
            }
            await model?.load()
            model?.observeLockState()
        }
        .onDisappear {
            model?.stopObserving()
        }
        .sheet(isPresented: $showAddSheet) {
            if let model {
                AddSecretForm(model: model)
            }
        }
    }
}

/// Cổng khóa: chỉ vào danh sách secret sau Touch ID.
private struct UnlockGate: View {
    let model: SecretsModel

    var body: some View {
        ContentUnavailableView {
            Label("Vault đang khóa", systemImage: "lock")
        } description: {
            Text("Secrets chỉ mở sau khi xác thực Touch ID.")
        } actions: {
            Button("Mở khóa bằng Touch ID") {
                Task { await model.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        if let error = model.error {
            Text(error).foregroundStyle(.red).font(.footnote)
        }
    }
}

private struct SecretsContent: View {
    let model: SecretsModel
    @Binding var showAddSheet: Bool

    var body: some View {
        List {
            ForEach(model.rows) { secret in
                secretRow(secret)
            }
        }
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "Chưa có secret", systemImage: "key.horizontal",
                    description: Text("Thêm API key/password bằng nút +."))
            }
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

    @ViewBuilder
    private func secretRow(_ secret: Secret) -> some View {
        HStack {
            Image(systemName: secret.kind.systemImage)
            VStack(alignment: .leading) {
                Text(secret.label)
                Text(secret.kind.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(secret.createdAt, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
                if let rotated = secret.rotatedAt {
                    Text("xoay \(rotated, style: .date)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            if secret.kind.isUserSecret {
                Button("Hiện") {
                    Task { await model.reveal(secret.id) }
                }
                Button("Copy") {
                    Task { await model.copy(secret.id) }
                }
            }
            Button("Xóa…", role: .destructive) {
                Task { await model.delete(secret.id) }
            }
        }
        if let revealed = model.revealed[secret.id] {
            Text(revealed)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

/// Thêm secret người nhập: API key hoặc password.
private struct AddSecretForm: View {
    let model: SecretsModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SecretKind = .apiKey
    @State private var label = ""
    @State private var value = ""

    var body: some View {
        Form {
            Picker("Loại", selection: $kind) {
                Text("API key").tag(SecretKind.apiKey)
                Text("Password").tag(SecretKind.password)
            }
            .pickerStyle(.segmented)
            TextField("Tên gợi nhớ", text: $label)
            SecureField("Giá trị", text: $value)
            if let error = model.error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 240)
        .navigationTitle("Thêm secret")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Hủy") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    Task { await save() }
                }
                .disabled(
                    label.trimmingCharacters(in: .whitespaces).isEmpty
                        || value.isEmpty)
            }
        }
    }

    private func save() async {
        await model.add(kind: kind, label: label, value: value)
        // Xóa giá trị secret khỏi state ngay sau khi lưu, kể cả khi lỗi.
        value = ""
        guard model.error == nil else { return }
        dismiss()
    }
}
