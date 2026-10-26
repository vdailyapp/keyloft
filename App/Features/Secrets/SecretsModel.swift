import Foundation
import Observation
import SecretVault
import VaultDomain
import VaultRuntime

/// Model màn Secrets: yêu cầu vault mở khóa, liệt kê secret, reveal tự xóa sau 30 s,
/// copy qua Clipboard (tự xóa 60 s). Lắng nghe `runtime.lock.states()` — locked → xóa rows.
@MainActor
@Observable
final class SecretsModel {
    static let revealWindow: TimeInterval = 30

    private(set) var rows: [Secret] = []
    private(set) var needsUnlock = true
    private(set) var error: String?
    /// Giá trị đang hiện trên UI; entry quá 30 s (theo clock) bị loại khỏi kết quả đọc.
    private var revealedStorage: [SecretID: (value: String, revealedAt: Date)] = [:]

    /// Giá trị đang hiện trên UI; entry quá 30 s (theo clock) bị loại khỏi kết quả đọc.
    var revealed: [SecretID: String] {
        let now = runtime.clock.now()
        return revealedStorage
            .filter { now.timeIntervalSince($0.value.revealedAt) < Self.revealWindow }
            .mapValues(\.value)
    }

    private let runtime: VaultRuntime
    private let clipboard: Clipboard
    private var observer: Task<Void, Never>?

    init(runtime: VaultRuntime, clipboard: Clipboard = Clipboard()) {
        self.runtime = runtime
        self.clipboard = clipboard
    }

    func load() async {
        error = nil
        await refreshLockState()
        guard !needsUnlock else { return }
        do {
            rows = try await runtime.secrets.list(kind: nil)
        } catch {
            self.error = "\(error)"
        }
    }

    /// Đọc lại trạng thái khóa: VaultLock tự hết hạn theo clock mà không phát event,
    /// nên UI phải kiểm tra chủ động (onAppear, sau mỗi hành động).
    func refreshLockState() async {
        apply(await runtime.lock.state)
    }

    /// Lắng nghe khóa/mở khóa tường minh (lock() khi máy ngủ, unlock từ UI).
    func observeLockState() {
        observer?.cancel()
        observer = Task { [weak self] in
            guard let states = await self?.runtime.lock.states() else { return }
            for await state in states {
                await MainActor.run {
                    self?.apply(state)
                    if case .unlocked = state {
                        Task { await self?.load() }
                    }
                }
            }
        }
    }

    func stopObserving() {
        observer?.cancel()
        observer = nil
    }

    func unlock() async {
        do {
            try await runtime.lock.unlock(reason: "Xem secret trong Keyloft")
        } catch let storeError as SecretStoreError where storeError == .userCanceled {
            self.error = "Đã hủy mở khóa"
        } catch {
            self.error = "\(error)"
        }
        await refreshLockState()
    }

    /// Hiện giá trị secret (Touch ID xảy ra ở tầng store nếu kind cần presence).
    /// Giữ tối đa 30 s trong state rồi tự xóa.
    @discardableResult
    func reveal(_ id: SecretID) async -> String? {
        guard !needsUnlock else { return nil }
        purgeExpiredReveals()
        do {
            let data = try await runtime.secrets.read(id, reason: "Hiện secret", actor: .user)
            let value = String(decoding: data, as: UTF8.self)
            revealedStorage[id] = (value, runtime.clock.now())
            return value
        } catch {
            self.error = "\(error)"
            return nil
        }
    }

    /// Copy vào clipboard; Clipboard tự xóa sau 60 s nếu không bị copy đè.
    func copy(_ id: SecretID) async {
        guard let value = await reveal(id) else { return }
        clipboard.copy(value)
    }

    /// Thêm secret người nhập (API key/password) — presence mặc định bật.
    func add(kind: SecretKind, label: String, value: String) async {
        error = nil
        do {
            _ = try await runtime.secrets.create(
                kind: kind, label: label, value: Data(value.utf8), actor: .user)
            await load()
        } catch {
            self.error = "\(error)"
        }
    }

    func delete(_ id: SecretID) async {
        error = nil
        do {
            try await runtime.secrets.delete(id, actor: .user)
            revealedStorage[id] = nil
            await load()
        } catch {
            self.error = "\(error)"
        }
    }

    private func apply(_ state: VaultLockState) {
        switch state {
        case .locked:
            needsUnlock = true
            rows = []
            revealedStorage = [:]
        case .unlocked:
            needsUnlock = false
        }
    }

    private func purgeExpiredReveals() {
        let now = runtime.clock.now()
        revealedStorage = revealedStorage.filter {
            now.timeIntervalSince($0.value.revealedAt) < Self.revealWindow
        }
    }
}

extension SecretKind {
    var systemImage: String {
        switch self {
        case .apiKey: "key"
        case .password: "ellipsis.circle"
        case .clientSecret: "app.badge.checkmark"
        case .refreshToken: "arrow.triangle.2.circlepath"
        }
    }

    /// Chỉ secret người nhập có nút Hiện/Copy; refresh token/client secret chỉ metadata.
    var isUserSecret: Bool {
        switch self {
        case .apiKey, .password: true
        case .clientSecret, .refreshToken: false
        }
    }
}
