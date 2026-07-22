import CoreGraphics
import Foundation

@MainActor
protocol ScreenshotCapturing: AnyObject {
    func captureSelectionToClipboard(
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws
    func cancel()
}

/// Starts macOS's native interactive screenshot selector with clipboard output.
@MainActor
final class ScreenshotService: ScreenshotCapturing {
    private var activeProcess: Process?

    func captureSelectionToClipboard(
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws {
        guard activeProcess == nil else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenshotCaptureError.permissionDenied
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] process in
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in
                guard let self, self.activeProcess === process else { return }
                self.activeProcess = nil
                // Escape exits non-zero without an error message. That is a
                // cancellation, not a failure worth surfacing.
                if process.terminationStatus != 0, let detail, !detail.isEmpty {
                    onFailure("Screenshot capture failed. \(detail)")
                }
            }
        }

        activeProcess = process
        do {
            try process.run()
        } catch {
            activeProcess = nil
            process.terminationHandler = nil
            throw error
        }
    }

    func cancel() {
        guard let process = activeProcess else { return }
        activeProcess = nil
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }
}

private enum ScreenshotCaptureError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Screen Recording permission is required. Enable Clickit in Privacy & Security, then relaunch it."
    }
}
