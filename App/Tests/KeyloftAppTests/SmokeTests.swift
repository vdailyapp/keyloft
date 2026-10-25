import AppKit
import Foundation
import Testing
@testable import Keyloft

@Suite("App Platform")
struct AppSmokeTests {
    @Test("Smoke: app target build + PlaceholderView dựng được")
    func smoke() {
        #expect(SidebarItem.allCases.count == 5)
        #expect(SidebarItem.accounts.rawValue == "Accounts")
    }

    @Test("Clipboard: clearIfUnchanged tôn trọng changeCount")
    @MainActor
    func clipboardChangeCount() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = Clipboard(pasteboard: pasteboard)

        clipboard.copy("secret-value")
        #expect(pasteboard.string(forType: .string) == "secret-value")
        #expect(clipboard.isTracking)

        // Chưa ai copy đè → clear được.
        clipboard.clearIfUnchanged()
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(!clipboard.isTracking)

        // Người dùng copy đè → không xóa nội dung của họ.
        clipboard.copy("another")
        pasteboard.setString("user-copied", forType: .string)
        // Giả lập changeCount tăng: clearContents + set mới.
        pasteboard.clearContents()
        pasteboard.setString("user-copied", forType: .string)
        clipboard.clearIfUnchanged()
        #expect(pasteboard.string(forType: .string) == "user-copied")
    }

    @Test("Notifier: dedupe 24h")
    func notifierDedupe() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(NotifierPolicy.shouldNotify(lastNotified: nil, now: now))
        #expect(
            !NotifierPolicy.shouldNotify(lastNotified: now.addingTimeInterval(-3600), now: now))
        #expect(
            NotifierPolicy.shouldNotify(
                lastNotified: now.addingTimeInterval(-25 * 3600), now: now))
    }
}
