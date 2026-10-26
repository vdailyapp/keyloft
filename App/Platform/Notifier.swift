import Foundation
import UserNotifications
import VaultDomain

/// Thuần: đã thông báo trong cửa sổ dedupe chưa (test không cần notification center).
enum NotifierPolicy {
    static let dedupeWindow: TimeInterval = 24 * 3600

    static func shouldNotify(
        lastNotified: Date?, now: Date, window: TimeInterval = dedupeWindow
    ) -> Bool {
        guard let lastNotified else { return true }
        return now.timeIntervalSince(lastNotified) >= window
    }
}

/// Thông báo khi account chuyển sang needsReauth; dedupe theo account trong 24 h.
@MainActor
final class Notifier {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let clock: any DateProvider

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        clock: any DateProvider = SystemDateProvider()
    ) {
        self.center = center
        self.defaults = defaults
        self.clock = clock
    }

    func statusChanged(account: Account, from old: AccountStatus, to new: AccountStatus) async {
        guard old != .needsReauth, new == .needsReauth else { return }
        let key = "notifier.last.\(account.id.description)"
        let last = defaults.object(forKey: key) as? Date
        guard NotifierPolicy.shouldNotify(lastNotified: last, now: clock.now()) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Cần đăng nhập lại"
        content.body =
            "Account \(account.email ?? account.externalId) cần cấp lại quyền (đăng xuất ở phía provider?)."
        content.userInfo = ["accountId": account.id.description]
        let request = UNNotificationRequest(
            identifier: "needsReauth-\(account.id.description)", content: content, trigger: nil)
        // try?: thông báo là hành động UI best-effort — lỗi center không được làm chết pipeline.
        try? await center.add(request)
        defaults.set(clock.now(), forKey: key)
    }

    func requestAuthorization() async {
        // try?: người dùng từ chối quyền thông báo là đường bình thường, không phải lỗi.
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}
