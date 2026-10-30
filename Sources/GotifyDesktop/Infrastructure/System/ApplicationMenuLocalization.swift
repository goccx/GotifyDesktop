import AppKit

/// Keeps the macOS application-menu title aligned with the in-app language preference.
@MainActor
enum ApplicationMenuLocalization {
    /// AppKit creates the application menu outside SwiftUI's view hierarchy, so it needs an explicit update.
    static func apply(appName: String) {
        NSApp.mainMenu?.items.first?.title = appName
    }
}
