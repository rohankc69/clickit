import Foundation

/// Renders the "2m ago" style timestamps shown in the history list.
///
/// Not part of the originally sketched utility set, but pulled out of the view
/// layer so the rounding rule below lives in one place.
enum RelativeTimeFormatter {
    static func string(for date: Date, relativeTo reference: Date = Date()) -> String {
        let elapsed = reference.timeIntervalSince(date)
        // Below a few seconds the system formatter says "in 0 seconds", which
        // reads as a bug in a list that updates this quickly.
        guard elapsed >= 5 else { return "now" }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
