import AppKit
import SwiftUI

/// A native menu-bar menu contains vertical system menu rows, not a custom popover layout.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var messageStore: MessageStore
    /// Observing preferences refreshes translated text when the selected language changes.
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Text(Localized.string("app.name"))
        Text(connectionText)

        Divider()

        Button(Localized.string("menu.openMainWindow")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .accessibilityIdentifier("menu-open-app-button")

        Divider()

        Button(Localized.string("menu.quit"), role: .destructive) {
            NSApp.terminate(nil)
        }
        .accessibilityIdentifier("menu-quit-app-button")
        // Rebuilds the menu contents immediately when the chosen language changes.
        .id(preferences.language)
    }

    private var connectionText: String {
        switch messageStore.connectionState {
        case .notConfigured: Localized.string("connection.notConfigured")
        case .connecting: Localized.string("connection.connecting")
        case .connected: Localized.string("connection.connected")
        case .disconnected: Localized.string("connection.disconnected")
        }
    }
}
