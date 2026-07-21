import SwiftUI

/// Placeholder shown in place of the list.
///
/// Built on `ContentUnavailableView` so the layout, metrics and symbol
/// treatment come from the system and stay correct as macOS restyles them.
struct EmptyClipboardView: View {
    enum Reason {
        case noHistory
        case noSearchResults(query: String)
        case monitoringPaused

        var systemImage: String {
            switch self {
            case .noHistory: "doc.on.clipboard"
            case .noSearchResults: "magnifyingglass"
            case .monitoringPaused: "pause.circle"
            }
        }

        var title: String {
            switch self {
            case .noHistory: "No History Yet"
            case .noSearchResults: "No Matches"
            case .monitoringPaused: "Monitoring Paused"
            }
        }

        var message: String {
            switch self {
            case .noHistory: "Copy something with Command-C and it will show up here."
            case .noSearchResults(let query): "Nothing in your history matches “\(query)”."
            case .monitoringPaused: "Clickit is not recording copies right now."
            }
        }
    }

    let reason: Reason

    var body: some View {
        ContentUnavailableView {
            Label(reason.title, systemImage: reason.systemImage)
        } description: {
            Text(reason.message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
