import Foundation
import VaultDomain

public enum HealthTrigger: Sendable, Equatable {
    case appLaunch
    case wake
    case periodic
    case manual(AccountID?)
    case retry(AccountID)
}

/// Điều phối chạy HealthChecker: trigger ngoài (app mở/máy thức), vòng 6 giờ, retry
/// backoff khi unreachable, dedupe theo account, giới hạn đồng thời, ensureFresh cho
/// tác vụ lớn. Thời gian đi qua Sleeper + DateProvider để test tất định.
public actor HealthScheduler {
    public static let backoff: [TimeInterval] = [60, 120, 240, 480, 960, 1800]

    private let checker: HealthChecker
    private let accounts: any AccountRepository
    private let results: any HealthCheckRepository
    private let clock: any DateProvider
    private let sleeper: any Sleeper
    private let interval: TimeInterval
    private let maxConcurrent: Int
    private let policy: HealthPolicy

    private var running: [AccountID: Task<HealthCheckResult, any Error>] = [:]
    private var retryCounts: [AccountID: Int] = [:]
    private var retryTasks: [AccountID: Task<Void, Never>] = [:]
    private var periodicTask: Task<Void, Never>?
    private var externalTask: Task<Void, Never>?
    private var stopped = false
    /// Lỗi gần nhất của vòng scheduled (periodic/wake/retry) — vòng phải chạy tiếp nên
    /// không throw được; lỗi được giữ lại đây cho UI/test, không nuốt lặng lẽ.
    public private(set) var lastRunError: (any Error)?
    // Multicast đơn giản: một subscriber (menu bar).
    private var updateContinuation: AsyncStream<HealthCheckResult>.Continuation?

    public init(
        checker: HealthChecker,
        accounts: any AccountRepository,
        results: any HealthCheckRepository,
        clock: any DateProvider,
        sleeper: any Sleeper,
        interval: TimeInterval = 6 * 3600,
        maxConcurrent: Int = 3,
        policy: HealthPolicy = HealthPolicy()
    ) {
        self.checker = checker
        self.accounts = accounts
        self.results = results
        self.clock = clock
        self.sleeper = sleeper
        self.interval = interval
        self.maxConcurrent = maxConcurrent
        self.policy = policy
    }

    /// Bắt đầu vòng định kỳ + tiêu thụ trigger ngoài. Gọi một lần.
    public func start(external: AsyncStream<HealthTrigger>) {
        guard !stopped, periodicTask == nil else { return }
        periodicTask = Task { await self.periodicLoop() }
        externalTask = Task { await self.consumeExternal(external) }
    }

    public func stop() {
        stopped = true
        periodicTask?.cancel()
        periodicTask = nil
        externalTask?.cancel()
        externalTask = nil
        for task in retryTasks.values {
            task.cancel()
        }
        retryTasks.removeAll()
    }

    /// Chạy ngay theo trigger; trả kết quả theo thứ tự account. Throw khi không lấy được
    /// danh sách account hoặc một account lỗi hạ tầng (caller scheduled tự bắt để chạy tiếp).
    @discardableResult
    public func run(_ trigger: HealthTrigger) async throws -> [HealthCheckResult] {
        lastRunError = nil
        let targets: [AccountID]
        switch trigger {
        case .manual(let account?):
            targets = [account]
        case .retry(let account):
            targets = [account]
        default:
            targets = try await accounts.list().map(\.id)
        }
        let auditActor: AuditActor
        if case .manual = trigger {
            auditActor = .user
        } else {
            auditActor = .scheduler
        }

        var byAccount: [AccountID: HealthCheckResult] = [:]
        var iterator = targets.makeIterator()
        let limit = max(1, maxConcurrent)
        try await withThrowingTaskGroup(of: (AccountID, HealthCheckResult?).self) { group in
            func addNext() -> Bool {
                guard let id = iterator.next() else { return false }
                group.addTask { try await self.runOne(id, actor: auditActor) }
                return true
            }
            for _ in 0..<limit where addNext() {}
            while let (id, result) = try await group.next() {
                if let result {
                    byAccount[id] = result
                }
                _ = addNext()
            }
        }
        return targets.compactMap { byAccount[$0] }
    }

    /// Trước tác vụ lớn: kết quả còn mới và healthy/degraded → dùng lại; ngược lại check.
    public func ensureFresh(_ account: AccountID) async throws -> HealthCheckResult {
        if let latest = try await results.latest(for: account),
            clock.now().timeIntervalSince(latest.checkedAt) < policy.freshnessForHeavyTask,
            latest.status == .healthy || latest.status == .degraded
        {
            return latest
        }
        _ = try await run(.manual(account))
        guard let fresh = try await results.latest(for: account) else {
            throw DomainError.notFound("account:\(account)")
        }
        return fresh
    }

    public nonisolated var updates: AsyncStream<HealthCheckResult> {
        get async {
            await self.makeUpdatesStream()
        }
    }

    // MARK: - Nội bộ

    private func makeUpdatesStream() -> AsyncStream<HealthCheckResult> {
        let (stream, continuation) = AsyncStream<HealthCheckResult>.makeStream()
        updateContinuation = continuation
        return stream
    }

    private func periodicLoop() async {
        while !stopped {
            // try?: ngủ bị hủy khi stop() là đường thoát bình thường của vòng định kỳ.
            try? await sleeper.sleep(for: .seconds(interval))
            guard !stopped, !Task.isCancelled else { break }
            do {
                _ = try await run(.periodic)
            } catch {
                lastRunError = error
            }
        }
    }

    private func consumeExternal(_ external: AsyncStream<HealthTrigger>) async {
        for await trigger in external {
            guard !stopped, !Task.isCancelled else { break }
            do {
                _ = try await run(trigger)
            } catch {
                lastRunError = error
            }
        }
    }

    /// Chuyển lỗi check thành kết quả: cancel/append hủy và account bị xóa giữa chừng
    /// (notFound) là bình thường → nil; lỗi hạ tầng khác throw để run() báo ra.
    private func tolerantResult(
        _ task: Task<HealthCheckResult, any Error>
    ) async throws -> HealthCheckResult? {
        do {
            return try await task.value
        } catch is CancellationError {
            return nil
        } catch {
            if let domain = error as? DomainError, case .notFound = domain {
                return nil
            }
            throw error
        }
    }

    /// Dedupe theo account (single-flight như SPEC-006) + lên lịch backoff theo kết quả.
    private func runOne(
        _ account: AccountID, actor auditActor: AuditActor
    ) async throws -> (AccountID, HealthCheckResult?) {
        if let existing = running[account] {
            guard let result = try await tolerantResult(existing) else {
                return (account, nil)
            }
            return (account, result)
        }
        let task = Task<HealthCheckResult, any Error> {
            try await self.checker.check(account, actor: auditActor)
        }
        running[account] = task
        defer { running[account] = nil }

        guard let result = try await tolerantResult(task) else {
            return (account, nil)
        }
        scheduleBackoff(for: account, status: result.status)
        updateContinuation?.yield(result)
        return (account, result)
    }

    private func scheduleBackoff(for account: AccountID, status: AccountStatus) {
        retryTasks[account]?.cancel()
        retryTasks[account] = nil
        guard status == .unreachable else {
            retryCounts[account] = 0
            return
        }
        let count = (retryCounts[account] ?? 0) + 1
        retryCounts[account] = count
        let delay = Self.backoff[min(count - 1, Self.backoff.count - 1)]
        retryTasks[account] = Task {
            // try?: ngủ bị hủy khi stop()/kết quả mới là đường bình thường của backoff.
            try? await self.sleeper.sleep(for: .seconds(delay))
            guard !Task.isCancelled, await !self.isStopped else { return }
            do {
                _ = try await self.run(.retry(account))
            } catch {
                self.lastRunError = error
            }
        }
    }

    private var isStopped: Bool { stopped }
}
