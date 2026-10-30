import AppKit
import Foundation
import OSLog

/// The live-session notification boundary. The legacy AppKit API is deliberately used because V1 ships
/// without an Apple-issued signing identity, which macOS rejects for UserNotifications authorization.
@MainActor
protocol GotifyMessageNotifying: AnyObject {
    /// Called only after a unique WebSocket delivery has entered the in-memory message window.
    func notifyAboutLiveMessage(_ message: GotifyMessage)
}

/// Bridges live Gotify messages to macOS's legacy notification center for unsigned GitHub builds.
@MainActor
final class GotifyNotificationCoordinator: NSObject, ObservableObject, GotifyMessageNotifying, NSUserNotificationCenterDelegate {
    private enum Configuration {
        /// This exact resource filename is copied into the finished main App bundle by the packaging script.
        static let officialSoundFilename = "GotifyNotification.caf"
    }

    private let preferences: NotificationPreferences
    private let notificationCenter: NSUserNotificationCenter
    /// Diagnostics intentionally contain framework state only, never Gotify content or credentials.
    private let logger = Logger(subsystem: "com.gotify.desktop", category: "notifications")

    init(
        preferences: NotificationPreferences,
        notificationCenter: NSUserNotificationCenter = .default
    ) {
        self.preferences = preferences
        self.notificationCenter = notificationCenter
        super.init()
        // AppKit suppresses a frontmost app by default; Gotify banners must stay useful while its window is open.
        notificationCenter.delegate = self
    }

    /// This is an app preference only. The legacy notification center asks macOS for authorization on first delivery.
    func setSystemNotificationsEnabled(_ enabled: Bool) {
        preferences.systemNotificationsEnabled = enabled
    }

    /// Delivers a legacy macOS notification after the message has entered the bounded in-memory session window.
    func notifyAboutLiveMessage(_ message: GotifyMessage) {
        guard preferences.systemNotificationsEnabled else { return }

        let notification = NSUserNotification()
        notification.title = message.title.isEmpty ? message.sourceName : message.title
        notification.informativeText = message.body
        // NSUserNotification resolves a named sound from the application bundle; nil deliberately suppresses it.
        notification.soundName = preferences.notificationSoundEnabled ? Configuration.officialSoundFilename : nil
        notificationCenter.deliver(notification)
        logger.notice("Delivered legacy macOS notification for a live message")
    }

    /// Lets macOS show a banner while Gotify Desktop is frontmost; user notification settings still win.
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }

    /// Records macOS's presentation decision without logging notification content.
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didDeliver notification: NSUserNotification
    ) {
        logger.notice("Legacy notification delivery callback; presented: \(notification.isPresented, privacy: .public)")
    }
}
