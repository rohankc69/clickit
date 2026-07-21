import Darwin
import Foundation

/// Supplies the moment the system last booted.
protocol BootTimeProviding: Sendable {
    /// `nil` when the value cannot be read, in which case no reset is attempted.
    var bootTime: Date? { get }
}

struct SystemBootTimeProvider: BootTimeProviding {
    var bootTime: Date? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride

        guard sysctl(&mib, u_int(mib.count), &boottime, &size, nil, 0) == 0, boottime.tv_sec != 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(boottime.tv_sec))
    }
}

/// Clears unpinned history when the Mac has restarted since Clickit last ran.
///
/// History is treated as belonging to a single session at the machine, not as a
/// permanent archive: a month of accumulated screenshots and text is far more
/// than anyone reuses, and every retained item is a liability. Persistence still
/// matters, because quitting or crashing Clickit must not lose anything — only a
/// genuine restart wipes the slate.
///
/// Restarts are detected by comparing the kernel's boot time against the value
/// recorded at the last launch. Relaunching the app does not change that value,
/// so only a real reboot triggers a reset.
@MainActor
struct SessionResetService {
    private static let storageKey = "com.clickit.lastBootTime"
    /// The reported boot time can shift by a fraction of a second when the
    /// system clock is adjusted, so an exact comparison would occasionally
    /// wipe history without a reboot having happened.
    private static let tolerance: TimeInterval = 5

    private let bootTimeProvider: BootTimeProviding
    private let defaults: UserDefaults

    init(bootTimeProvider: BootTimeProviding = SystemBootTimeProvider(), defaults: UserDefaults = .standard) {
        self.bootTimeProvider = bootTimeProvider
        self.defaults = defaults
    }

    /// Returns `true` when history was cleared.
    @discardableResult
    func resetIfSystemRestarted(store: any ClipboardStoring, settings: ClickitSettings) -> Bool {
        guard let bootTime = bootTimeProvider.bootTime else {
            ClickitLog.storage.error("Could not read the system boot time; leaving history untouched")
            return false
        }

        let previous = defaults.object(forKey: Self.storageKey) as? Double
        defaults.set(bootTime.timeIntervalSince1970, forKey: Self.storageKey)

        // Record the boot time even when the behaviour is switched off, so that
        // turning it back on later does not treat the current session as new.
        guard settings.clearHistoryOnRestart else { return false }

        // First ever launch: adopt this boot time rather than clearing history
        // the user cannot have accumulated yet.
        guard let previous else { return false }

        guard abs(previous - bootTime.timeIntervalSince1970) > Self.tolerance else { return false }

        let removed = store.items.filter { !$0.isPinned }.count
        guard removed > 0 else { return true }

        store.deleteAll(includingPinned: false)
        ClickitLog.storage.info(
            "System restarted; cleared \(removed, privacy: .public) unpinned items"
        )
        return true
    }
}
