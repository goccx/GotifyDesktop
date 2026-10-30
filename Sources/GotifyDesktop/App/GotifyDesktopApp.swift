import Factory
import SwiftUI

/// The application entry point keeps the menu-bar lifecycle independent of the main window.
@main
struct GotifyDesktopApp: App {
    /// Factory owns the process-wide in-memory session; quitting the app releases it.
    @StateObject private var messageStore: MessageStore
    /// Preferences are deliberately limited to non-message UI choices.
    @StateObject private var preferences = AppPreferences()
    /// Notification choices are persistent UI preferences, never message data.
    @StateObject private var notificationPreferences: NotificationPreferences
    /// The coordinator bridges one in-memory live delivery to macOS presentation and audio.
    @StateObject private var notificationCoordinator: GotifyNotificationCoordinator
    /// Server configuration is separate from UI preferences because it owns connection lifecycle and token encryption.
    @StateObject private var serverPreferences: ServerPreferences

    init() {
        let store = Container.shared.messageStore()
        let notificationPreferences = NotificationPreferences()
        let notificationCoordinator = GotifyNotificationCoordinator(preferences: notificationPreferences)
        let serverPreferences = ServerPreferences(
            sessionController: GotifySessionController(messageStore: store, notifier: notificationCoordinator)
        )
        _messageStore = StateObject(wrappedValue: store)
        _notificationPreferences = StateObject(wrappedValue: notificationPreferences)
        _notificationCoordinator = StateObject(wrappedValue: notificationCoordinator)
        _serverPreferences = StateObject(wrappedValue: serverPreferences)

        // This process-level task restores a verified opt-in even when the main window remains closed.
        Task { @MainActor in
            await serverPreferences.restoreReceivingSessionIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup(Localized.string("app.name"), id: "main") {
            InboxView()
                .environmentObject(messageStore)
                .environmentObject(preferences)
                .environmentObject(notificationPreferences)
                .environmentObject(notificationCoordinator)
                .environmentObject(serverPreferences)
                .environment(\.locale, preferences.language.locale)
        }
        .defaultSize(width: 1_080, height: 720)

        // This deliberately uses only native template content: count first, then the familiar macOS bell.
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(messageStore)
                .environmentObject(preferences)
                .environmentObject(notificationPreferences)
                .environment(\.locale, preferences.language.locale)
        } label: {
            HStack(spacing: 3) {
                if messageStore.newMessageCount > 0 {
                    Text(NewMessageCountFormat.display(messageStore.newMessageCount))
                        .monospacedDigit()
                }
                Image(systemName: "bell")
                    .symbolRenderingMode(.monochrome)
            }
            .accessibilityLabel(Localized.string("message.newMessagesAccessibility", messageStore.newMessageCount))
        }
        // `.menu` gives the status item the same vertical menu structure as other macOS utilities.
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(serverPreferences)
                .environmentObject(notificationPreferences)
                .environmentObject(notificationCoordinator)
                .environment(\.locale, preferences.language.locale)
        }
        // Settings has a deliberately compact, complete form; allowing an old saved window width
        // to stretch it makes the native grouped layout visually sparse and harder to scan.
        .windowResizability(.contentSize)
    }
}
