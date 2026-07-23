import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum LiveQueuePasteInterceptorError: LocalizedError {
    case permissionDenied
    case unavailable
    case disabled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Live Queue needs Accessibility and Input Monitoring to prepare queued items before your normal Command-V. Enable Clickit in Privacy & Security, then relaunch it."
        case .unavailable:
            "Live Queue could not start keyboard monitoring. Command-V was not changed."
        case .disabled:
            "macOS stopped Live Queue keyboard monitoring. The remaining queue was kept and Command-V is working normally."
        }
    }
}

@MainActor
protocol LiveQueuePasteIntercepting: AnyObject {
    var isActive: Bool { get }
    func activate(
        onCommandV: @escaping @MainActor () -> Bool,
        onFailure: @escaping @MainActor (LiveQueuePasteInterceptorError) -> Void
    ) throws
    func deactivate()
}

/// Temporarily observes physical Command-V while Live Queue is active. It never
/// changes or replaces the keystroke: the callback stages the next payload, then
/// this tap returns the original event to the frontmost application.
@MainActor
final class LiveQueuePasteInterceptor: LiveQueuePasteIntercepting {
    private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCommandV: (@MainActor () -> Bool)?
    private var onFailure: (@MainActor (LiveQueuePasteInterceptorError) -> Void)?
    private var isHandlingEvent = false
    private var teardownAfterEvent = false

    func activate(
        onCommandV: @escaping @MainActor () -> Bool,
        onFailure: @escaping @MainActor (LiveQueuePasteInterceptorError) -> Void
    ) throws {
        guard !isActive else { return }

        if !AXIsProcessTrusted() {
            let promptKey = "AXTrustedCheckOptionPrompt"
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            throw LiveQueuePasteInterceptorError.permissionDenied
        }
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            throw LiveQueuePasteInterceptorError.permissionDenied
        }

        self.onCommandV = onCommandV
        self.onFailure = onFailure
        let context = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<LiveQueuePasteInterceptor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    interceptor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            self.onCommandV = nil
            self.onFailure = nil
            throw LiveQueuePasteInterceptorError.unavailable
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            self.onCommandV = nil
            self.onFailure = nil
            throw LiveQueuePasteInterceptorError.unavailable
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isActive = true
        ClickitLog.shortcut.notice("Live Queue Command-V monitoring started")
    }

    func deactivate() {
        guard isActive || eventTap != nil else { return }
        isActive = false
        if isHandlingEvent {
            teardownAfterEvent = true
        } else {
            tearDown()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        isHandlingEvent = true
        defer {
            isHandlingEvent = false
            if teardownAfterEvent {
                tearDown()
            }
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let failure = onFailure
            deactivate()
            failure?(.disabled)
            return
        }

        guard isActive, Self.isPhysicalCommandV(type: type, event: event) else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        if onCommandV?() != true {
            deactivate()
        }
    }

    static func isPhysicalCommandV(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == 0x09,
              event.getIntegerValueField(.eventSourceUserData) != ClickitEventMarker.syntheticPaste
        else { return false }

        let flags = event.flags
        guard flags.contains(.maskCommand) else { return false }
        let disallowed: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
        guard flags.intersection(disallowed).isEmpty else { return false }

        let sourceState = event.getIntegerValueField(.eventSourceStateID)
        return sourceState == Int64(CGEventSourceStateID.hidSystemState.rawValue)
    }

    private func tearDown() {
        teardownAfterEvent = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        onCommandV = nil
        onFailure = nil
        ClickitLog.shortcut.notice("Live Queue Command-V monitoring stopped")
    }
}
