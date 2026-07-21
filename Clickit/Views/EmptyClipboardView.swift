import SwiftUI

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
            case .noHistory: "No clipboard history yet"
            case .noSearchResults: "No matches"
            case .monitoringPaused: "Monitoring paused"
            }
        }

        var message: String {
            switch self {
            case .noHistory: "Copy something with ⌘C and it will show up here."
            case .noSearchResults(let query): "Nothing in your history matches “\(query)”."
            case .monitoringPaused: "Clickit is not recording copies right now."
            }
        }
    }

    let reason: Reason

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: reason.systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(reason.title)
                .font(.system(size: 12, weight: .medium))
            Text(reason.message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
