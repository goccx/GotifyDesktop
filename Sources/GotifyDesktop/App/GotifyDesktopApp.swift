import AppKit
import Factory
import SwiftUI

@MainActor
final class GotifyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bootstrap = GotifyAppBootstrap.shared
        AppWindowCoordinator.shared.configure(
            rootView: MainWindowRootView(preferences: bootstrap.preferences)
                .environmentObject(bootstrap.messageStore)
                .environmentObject(bootstrap.preferences)
                .environmentObject(bootstrap.notificationPreferences)
                .environmentObject(bootstrap.notificationCoordinator)
                .environmentObject(bootstrap.serverPreferences)
        )
        AppWindowCoordinator.shared.openMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowCoordinator.shared.openMainWindow()
        return false
    }
}

/// The application entry point keeps the menu-bar lifecycle independent of the main window.
@main
struct GotifyDesktopApp: App {
    @NSApplicationDelegateAdaptor(GotifyAppDelegate.self) private var appDelegate
    @ObservedObject private var bootstrap = GotifyAppBootstrap.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(bootstrap.preferences)
                .environmentObject(bootstrap.serverPreferences)
                .environmentObject(bootstrap.notificationPreferences)
                .environmentObject(bootstrap.notificationCoordinator)
                .environment(\.locale, bootstrap.preferences.language.locale)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
private final class GotifyAppBootstrap: ObservableObject {
    static let shared = GotifyAppBootstrap()

    let messageStore: MessageStore
    let preferences: AppPreferences
    let notificationPreferences: NotificationPreferences
    let notificationCoordinator: GotifyNotificationCoordinator
    let serverPreferences: ServerPreferences
    let menuBarController: MenuBarStatusController

    private init() {
        LegacyBundlePreferencesMigration.migrateIfNeeded()
        let store = Container.shared.messageStore()
        let preferences = AppPreferences()
        let notificationPreferences = NotificationPreferences()
        let notificationCoordinator = GotifyNotificationCoordinator(preferences: notificationPreferences)
        let serverPreferences = ServerPreferences(
            sessionController: GotifySessionController(messageStore: store, notifier: notificationCoordinator)
        )
        let menuBarController = MenuBarStatusController()

        self.messageStore = store
        self.preferences = preferences
        self.notificationPreferences = notificationPreferences
        self.notificationCoordinator = notificationCoordinator
        self.serverPreferences = serverPreferences
        self.menuBarController = menuBarController

        menuBarController.configure(messageStore: store, preferences: preferences)

        // This process-level task restores a verified opt-in even when the main window remains closed.
        Task { @MainActor in
            await serverPreferences.restoreReceivingSessionIfNeeded()
        }
    }
}

private struct MainWindowRootView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        InboxView()
            .environment(\.locale, preferences.language.locale)
    }
}
