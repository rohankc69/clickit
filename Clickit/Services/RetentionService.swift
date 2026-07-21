import Foundation

/// What a cleanup pass removed. Returned rather than logged so tests can assert
/// on it and the settings screen can eventually surface it.
struct RetentionReport: Equatable {
    var expired: Int = 0
    var overItemLimit: Int = 0
    var overSizeLimit: Int = 0

    var total: Int { expired + overItemLimit + overSizeLimit }
    var isEmpty: Bool { total == 0 }
}

/// Enforces the retention policy against any `ClipboardStoring`.
///
/// Stateless by design: every decision is derived from the store snapshot, the
/// settings value and an injected `now`, which makes the age-based rules
/// testable without waiting or stubbing the clock globally.
@MainActor
struct RetentionService {
    @discardableResult
    func runCleanup(
        store: ClipboardStoring,
        settings: ClickitSettings,
        now: Date = Date()
    ) -> RetentionReport {
        var report = RetentionReport()
        report.expired = removeExpired(store: store, settings: settings, now: now)
        report.overItemLimit = trimToItemLimit(store: store, settings: settings)
        report.overSizeLimit = trimToSizeLimit(store: store, settings: settings)

        if !report.isEmpty {
            ClickitLog.retention.info(
                """
                Cleanup removed \(report.total, privacy: .public) items \
                (expired: \(report.expired, privacy: .public), \
                count: \(report.overItemLimit, privacy: .public), \
                size: \(report.overSizeLimit, privacy: .public))
                """
            )
        }
        return report
    }

    /// Rule 1 — anything past its per-type retention window, pins excepted.
    private func removeExpired(store: ClipboardStoring, settings: ClickitSettings, now: Date) -> Int {
        let doomed = store.items.filter { item in
            guard !item.isPinned else { return false }
            return item.lastUsedAt < settings.expirationDate(for: item.type, now: now)
        }
        store.delete(ids: doomed.map(\.id))
        return doomed.count
    }

    /// Rule 2 — oldest unpinned entries once the history is longer than the cap.
    ///
    /// Pinned entries count toward the total but are never the ones removed, so
    /// a user who pins more than `maxItems` keeps all of them and simply stops
    /// accumulating new history.
    private func trimToItemLimit(store: ClipboardStoring, settings: ClickitSettings) -> Int {
        let overflow = store.items.count - settings.maxItems
        guard overflow > 0 else { return 0 }

        let doomed = oldestFirst(store.items.filter { !$0.isPinned }).prefix(overflow)
        store.delete(ids: doomed.map(\.id))
        return doomed.count
    }

    /// Rule 3 — oldest unpinned *images* while the footprint is over budget.
    ///
    /// Only images are evicted here: they are what actually consume the disk
    /// budget, and dropping text to satisfy a byte limit would lose far more
    /// history than it reclaims.
    private func trimToSizeLimit(store: ClipboardStoring, settings: ClickitSettings) -> Int {
        guard store.totalByteSize > settings.maxStorageBytes else { return 0 }

        var remaining = store.totalByteSize
        var doomed: [UUID] = []
        for candidate in oldestFirst(store.items.filter { !$0.isPinned && $0.type == .image }) {
            guard remaining > settings.maxStorageBytes else { break }
            remaining -= candidate.byteSize
            doomed.append(candidate.id)
        }
        store.delete(ids: doomed)
        return doomed.count
    }

    private func oldestFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted { $0.lastUsedAt < $1.lastUsedAt }
    }
}
