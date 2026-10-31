import AppKit
import Factory
import SwiftUI

@MainActor
final class GotifyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppWindowCoordinator.shared.openMainWindow()
        }
        return true
    }
}

/// The application entry point keeps the menu-bar lifecycle independent of the main window.
@main
struct GotifyDesktopApp: App {
    @NSApplicationDelegateAdaptor(GotifyAppDelegate.self) private var appDelegate
    /// Factory owns the process-wide in-memory session; quitting the app releases it.
    @StateObject private var messageStore: MessageStore
    /// Preferences are deliberately limited to non-message UI choices.
    @StateObject private var preferences: AppPreferences
    /// Notification choices are persistent UI preferences, never message data.
    @StateObject private var notificationPreferences: NotificationPreferences
    /// The coordinator bridges one in-memory live delivery to macOS presentation and audio.
    @StateObject private var notificationCoordinator: GotifyNotificationCoordinator
    /// Server configuration is separate from UI preferences because it owns connection lifecycle and token encryption.
    @StateObject private var serverPreferences: ServerPreferences
    /// Native AppKit status item keeps menu-bar behavior identical from macOS 12 through macOS 15+.
    @StateObject private var menuBarController: MenuBarStatusController

    init() {
        LegacyBundlePreferencesMigration.migrateIfNeeded()
        let store = Container.shared.messageStore()
        let preferences = AppPreferences()
        let notificationPreferences = NotificationPreferences()
        let notificationCoordinator = GotifyNotificationCoordinator(preferences: notificationPreferences)
        let serverPreferences = ServerPreferences(
            sessionController: GotifySessionController(messageStore: store, notifier: notificationCoordinator)
        )
        let menuBarController = MenuBarStatusController()
        menuBarController.configure(messageStore: store, preferences: preferences)

        _messageStore = StateObject(wrappedValue: store)
        _preferences = StateObject(wrappedValue: preferences)
        _notificationPreferences = StateObject(wrappedValue: notificationPreferences)
        _notificationCoordinator = StateObject(wrappedValue: notificationCoordinator)
        _serverPreferences = StateObject(wrappedValue: serverPreferences)
        _menuBarController = StateObject(wrappedValue: menuBarController)

        // This process-level task restores a verified opt-in even when the main window remains closed.
        Task { @MainActor in
            await serverPreferences.restoreReceivingSessionIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup(Localized.string("app.name")) {
            InboxView()
                .background(MainWindowAccessor())
                .frame(minWidth: 900, idealWidth: 1_080, minHeight: 600, idealHeight: 720)
                .environmentObject(messageStore)
                .environmentObject(preferences)
                .environmentObject(notificationPreferences)
                .environmentObject(notificationCoordinator)
                .environmentObject(serverPreferences)
                .environment(\.locale, preferences.language.locale)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(serverPreferences)
                .environmentObject(notificationPreferences)
                .environmentObject(notificationCoordinator)
                .environment(\.locale, preferences.language.locale)
        }
    }
}
