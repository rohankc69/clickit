import Foundation
import ServiceManagement

/// Controls whether Clickit is launched when the user logs in.
///
/// Behind a protocol so `AppEnvironment` can be exercised without registering a
/// real login item, which a test process cannot meaningfully do.
@MainActor
protocol LoginItemManaging: AnyObject {
    /// Whether macOS currently launches Clickit at login.
    ///
    /// Read fresh each time rather than cached: the user can flip it in System
    /// Settings under General > Login Items while Clickit is running, and a stale
    /// answer would leave the toggle showing the wrong state.
    var isEnabled: Bool { get }

    /// Registers or unregisters Clickit as a login item. Idempotent. Throws if
    /// macOS refuses, which it does for a bundle it will not verify.
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class LoginItemService: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            // Registering an already-enabled service throws; skipping keeps the
            // call idempotent.
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
