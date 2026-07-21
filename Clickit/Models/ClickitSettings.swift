import Foundation
import Observation

/// User-configurable behaviour, as a value type so retention logic can be
/// exercised in tests without touching `UserDefaults`.
struct ClickitSettings: Codable, Equatable, Sendable {
    /// Hard ceiling on history length. Pinned items are exempt from trimming
    /// but still count toward the total.
    var maxItems: Int
    var maxStorageBytes: Int
    var textRetentionDays: Int
    var imageRetentionDays: Int

    /// How often the pasteboard change count is sampled. macOS provides no
    /// change notification for `NSPasteboard`, so polling is the only option.
    var pollInterval: TimeInterval

    var isMonitoringPaused: Bool

    /// Briefly show a confirmation mark in the menu bar when something is
    /// recorded. macOS gives no feedback of its own when content reaches the
    /// clipboard, so without this a capture is invisible.
    var flashOnCapture: Bool

    /// Discard unpinned history when the Mac restarts.
    ///
    /// On by default: history is a working set for the current session at the
    /// machine, not an archive. The retention windows below stay as a backstop
    /// for machines that go weeks between restarts.
    var clearHistoryOnRestart: Bool

    /// Bundle identifiers whose copies are dropped instead of recorded.
    ///
    /// - Note: Enforcement depends on `NSWorkspace.frontmostApplication`, which
    ///   is a best-effort attribution rather than a guarantee of which process
    ///   wrote to the pasteboard. See `PasteboardService` and PRIVACY.md.
    var excludedBundleIdentifiers: [String]

    static let `default` = ClickitSettings(
        maxItems: 1_000,
        maxStorageBytes: FileSizeFormatter.megabytes(500),
        textRetentionDays: 30,
        imageRetentionDays: 7,
        pollInterval: 0.5,
        isMonitoringPaused: false,
        flashOnCapture: true,
        clearHistoryOnRestart: true,
        excludedBundleIdentifiers: []
    )

    func retentionDays(for type: ClipboardItemType) -> Int {
        type.usesImageRetentionPolicy ? imageRetentionDays : textRetentionDays
    }

    func expirationDate(for type: ClipboardItemType, now: Date) -> Date {
        now.addingTimeInterval(-Double(retentionDays(for: type)) * 86_400)
    }
}

extension ClickitSettings {
    /// Decodes tolerantly: a field added after a user's settings were written
    /// falls back to its default instead of failing the whole payload and
    /// silently resetting every other preference they had chosen.
    ///
    /// Declared in an extension so the memberwise initialiser survives.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ClickitSettings.default

        self.init(
            maxItems: try container.decodeIfPresent(Int.self, forKey: .maxItems)
                ?? fallback.maxItems,
            maxStorageBytes: try container.decodeIfPresent(Int.self, forKey: .maxStorageBytes)
                ?? fallback.maxStorageBytes,
            textRetentionDays: try container.decodeIfPresent(Int.self, forKey: .textRetentionDays)
                ?? fallback.textRetentionDays,
            imageRetentionDays: try container.decodeIfPresent(Int.self, forKey: .imageRetentionDays)
                ?? fallback.imageRetentionDays,
            pollInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .pollInterval)
                ?? fallback.pollInterval,
            isMonitoringPaused: try container.decodeIfPresent(Bool.self, forKey: .isMonitoringPaused)
                ?? fallback.isMonitoringPaused,
            flashOnCapture: try container.decodeIfPresent(Bool.self, forKey: .flashOnCapture)
                ?? fallback.flashOnCapture,
            clearHistoryOnRestart: try container.decodeIfPresent(Bool.self, forKey: .clearHistoryOnRestart)
                ?? fallback.clearHistoryOnRestart,
            excludedBundleIdentifiers: try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers)
                ?? fallback.excludedBundleIdentifiers
        )
    }
}

/// Observable wrapper that persists `ClickitSettings` to `UserDefaults`.
///
/// Kept separate from the value type so that views observe changes while the
/// retention and monitoring services take a plain snapshot.
@MainActor
@Observable
final class SettingsStore {
    private static let defaultsKey = "com.clickit.settings"

    private let defaults: UserDefaults

    var settings: ClickitSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults) ?? .default
    }

    private static func load(from defaults: UserDefaults) -> ClickitSettings? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        do {
            return try JSONDecoder().decode(ClickitSettings.self, from: data)
        } catch {
            // A settings payload written by an older build may no longer decode.
            // Falling back to defaults is safe; silently ignoring it is not.
            ClickitLog.app.error("Discarding unreadable settings: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.defaultsKey)
        } catch {
            ClickitLog.app.error("Failed to persist settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    func resetToDefaults() {
        settings = .default
    }
}
