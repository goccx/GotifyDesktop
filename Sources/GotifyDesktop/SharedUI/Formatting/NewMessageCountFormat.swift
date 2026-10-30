import Foundation

/// Keeps the compact macOS badge readable while accessibility still receives the exact session count.
enum NewMessageCountFormat {
    static let visualMaximum = 999

    static func display(_ count: Int) -> String {
        count > visualMaximum ? "\(visualMaximum)+" : "\(count)"
    }
}
