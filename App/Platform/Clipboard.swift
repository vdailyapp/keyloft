import AppKit
import Foundation
import VaultDomain

/// Copy vào clipboard rồi tự xóa sau 60 s nếu người dùng chưa copy đè (changeCount).
@MainActor
final class Clipboard {
    static let autoClearInterval: TimeInterval = 60

    private let pasteboard: NSPasteboard
    private var copiedChangeCount: Int?
    private var clearTask: Task<Void, Never>?
    private let clock: any DateProvider

    init(
        pasteboard: NSPasteboard = .general,
        clock: any DateProvider = SystemDateProvider()
    ) {
        self.pasteboard = pasteboard
        self.clock = clock
    }

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedChangeCount = pasteboard.changeCount
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            // try?: ngủ bị hủy khi copy đè là đường bình thường của auto-clear.
            try? await Task.sleep(for: .seconds(Self.autoClearInterval))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.clearIfUnchanged() }
        }
    }

    /// Xóa nếu clipboard còn đúng phiên bản ta copy (người dùng chưa chép gì khác).
    func clearIfUnchanged(now date: Date? = nil) {
        guard let count = copiedChangeCount else { return }
        guard pasteboard.changeCount == count else {
            copiedChangeCount = nil
            return
        }
        pasteboard.clearContents()
        copiedChangeCount = nil
        _ = date ?? clock.now()
    }

    var isTracking: Bool { copiedChangeCount != nil }
}
