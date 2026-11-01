import AppKit
import Factory
import SwiftUI

@MainActor
final class GotifyAppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        // Disable macOS window state restoration so `NSPersistentUIManager` never restores
        // a "0 visible windows" snapshot after the main window was hidden with `orderOut(nil)`.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
        _ = AppWindowCoordinator.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        AppWindowCoordinator.shared.startObserving()
        DispatchQueue.main.async {
            AppWindowCoordinator.shared.ensureMainWindowPresentedAtLaunch()
            NSAppleEventManager.shared().setEventHandler(
                self,
                andSelector: #selector(self.handleReopenAppleEvent(_:withReplyEvent:)),
                forEventClass: AEEventClass(kCoreEventClass),
                andEventID: AEEventID(kAEReopenApplication)
            )
        }
    }

    @objc private func handleReopenAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        AppWindowCoordinator.shared.openMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppWindowCoordinator.shared.hasMainWindow {
            AppWindowCoordinator.shared.openMainWindow()
            return false
        }
        return true
    }

    func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }
}

/// The application entry point keeps the menu-bar lifecycle independent of the main window.
@main
struct GotifyDesktopApp: App {
    @NSApplicationDelegateAdaptor(GotifyAppDelegate.self) private var appDelegate
    @StateObject private var bootstrap = GotifyAppBootstrap()

    var body: some Scene {
        WindowGroup(Localized.string("app.name")) {
            InboxView()
                .environmentObject(bootstrap.messageStore)
                .environmentObject(bootstrap.preferences)
                .environmentObject(bootstrap.notificationPreferences)
                .environmentObject(bootstrap.notificationCoordinator)
                .environmentObject(bootstrap.serverPreferences)
                .environment(\.locale, bootstrap.preferences.language.locale)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(bootstrap.preferences)
                .environmentObject(bootstrap.serverPreferences)
                .environmentObject(bootstrap.notificationPreferences)
                .environmentObject(bootstrap.notificationCoordinator)
                .environment(\.locale, bootstrap.preferences.language.locale)
        }
    }
}

@MainActor
private final class GotifyAppBootstrap: ObservableObject {
    let messageStore: MessageStore
    let preferences: AppPreferences
    let notificationPreferences: NotificationPreferences
    let notificationCoordinator: GotifyNotificationCoordinator
    let serverPreferences: ServerPreferences
    let menuBarController: MenuBarStatusController

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

        self.messageStore = store
        self.preferences = preferences
        self.notificationPreferences = notificationPreferences
        self.notificationCoordinator = notificationCoordinator
        self.serverPreferences = serverPreferences
        self.menuBarController = menuBarController

        // This process-level task restores a verified opt-in even when the main window remains closed.
        Task { @MainActor in
            await serverPreferences.restoreReceivingSessionIfNeeded()
        }
    }
}
