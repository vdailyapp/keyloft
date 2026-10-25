import AppKit
import Foundation
import HealthCheck

/// Đủ điều kiện test: closure lấy notification thay vì dùng NSWorkspace trực tiếp.
struct SystemEvents {
    var onWake: @MainActor () -> Void
    var onLock: @MainActor () -> Void

    @MainActor
    func start() -> [Task<Void, Never>] {
        var tasks: [Task<Void, Never>] = []
        tasks.append(
            Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(
                    named: NSWorkspace.didWakeNotification)
                {
                    onWake()
                }
            })
        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            tasks.append(
                Task { @MainActor in
                    for await _ in NotificationCenter.default.notifications(named: name) {
                        onLock()
                    }
                })
        }
        return tasks
    }
}
