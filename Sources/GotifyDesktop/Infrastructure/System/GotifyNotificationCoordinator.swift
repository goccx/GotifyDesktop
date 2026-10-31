import AppKit
import Defaults
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
        static let messageIDUserInfoKey = "messageID"
        static let sourceIDUserInfoKey = "sourceID"
    }

    struct ActivatedNotificationTarget: Equatable, Sendable {
        let id = UUID()
        let messageID: Int64
        let sourceID: Int64
    }

    @Published private(set) var activatedTarget: ActivatedNotificationTarget?
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
        if NSApp != nil, NSApp.isRunning {
            registerWithSystemNotificationCenterIfNeeded()
        } else {
            NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.registerWithSystemNotificationCenterIfNeeded()
                }
            }
        }
    }

    /// Registers the packaged `.app` with macOS Notification Center on first launch so the system
    /// authorization prompt appears immediately and the app is listed under System Settings -> Notifications.
    private func registerWithSystemNotificationCenterIfNeeded() {
        guard Bundle.main.bundlePath.hasSuffix(".app"),
              preferences.systemNotificationsEnabled,
              !Defaults[.didRegisterNotificationCenter]
        else { return }
        Defaults[.didRegisterNotificationCenter] = true
        deliverNotification(
            title: Localized.string("notification.enabled.title"),
            body: Localized.string("notification.enabled.body")
        )
    }

    /// Toggling system notifications on immediately delivers a registration/preview banner so macOS
    /// adds Gotify Desktop to Notification Center and opens System Notification Settings for verification.
    func setSystemNotificationsEnabled(_ enabled: Bool) {
        preferences.systemNotificationsEnabled = enabled
        guard enabled else { return }
        deliverNotification(
            title: Localized.string("notification.enabled.title"),
            body: Localized.string("notification.enabled.body")
        )
        openSystemNotificationSettings()
    }

    /// Opens the macOS System Preferences / System Settings -> Notifications pane directly across macOS 12+.
    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Delivers a legacy macOS notification after the message has entered the bounded in-memory session window.
    func notifyAboutLiveMessage(_ message: GotifyMessage) {
        guard preferences.systemNotificationsEnabled else { return }
        deliverNotification(
            title: message.title.isEmpty ? message.sourceName : MessageMarkdownParser.plainTextSummary(from: message.title),
            body: MessageMarkdownParser.plainTextSummary(from: message.body),
            userInfo: [
                Configuration.messageIDUserInfoKey: NSNumber(value: message.id),
                Configuration.sourceIDUserInfoKey: NSNumber(value: message.sourceID),
            ]
        )
    }

    func consumeActivatedTarget(_ target: ActivatedNotificationTarget) {
        guard activatedTarget == target else { return }
        activatedTarget = nil
    }

    private func deliverNotification(title: String, body: String, userInfo: [String: Any]? = nil) {
        let notification = NSUserNotification()
        notification.identifier = UUID().uuidString
        notification.title = title
        notification.informativeText = body
        notification.userInfo = userInfo
        // NSUserNotification resolves a named sound from the application bundle; nil deliberately suppresses it.
        notification.soundName = preferences.notificationSoundEnabled ? Configuration.officialSoundFilename : nil
        notificationCenter.deliver(notification)
        logger.notice("Delivered legacy macOS notification")
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

    /// Clicking a delivered macOS banner brings the application forward and navigates to the message detail.
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didActivate notification: NSUserNotification
    ) {
        let messageID = (notification.userInfo?[Configuration.messageIDUserInfoKey] as? NSNumber)?.int64Value
        let sourceID = (notification.userInfo?[Configuration.sourceIDUserInfoKey] as? NSNumber)?.int64Value
        Task { @MainActor in
            AppWindowCoordinator.shared.openMainWindow()
            if let messageID, let sourceID {
                self.activatedTarget = ActivatedNotificationTarget(messageID: messageID, sourceID: sourceID)
            }
        }
    }
}
