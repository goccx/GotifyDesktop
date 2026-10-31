import AppKit
import Defaults
import SwiftUI

/// The three supported appearance choices intentionally map to a small, stable preference surface.
enum AppearancePreference: String, CaseIterable, Defaults.Serializable, Identifiable {
    case system
    case dark
    case white

    var id: Self { self }

    /// A forced white theme maps to SwiftUI light mode; system keeps the system decision.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .white: .light
        }
    }

    var displayName: String {
        switch self {
        case .system: Localized.string("appearance.system")
        case .dark: Localized.string("appearance.dark")
        case .white: Localized.string("appearance.white")
        }
    }
}

/// Language selection is stored as a user preference and takes effect without restarting the app.
enum LanguagePreference: String, CaseIterable, Defaults.Serializable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: Self { self }

    /// System uses an autoupdating locale so macOS language changes are honored while the app is open.
    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    var displayName: String {
        switch self {
        case .system: Localized.string("language.system")
        case .english: Localized.string("language.english")
        case .simplifiedChinese: Localized.string("language.simplifiedChinese")
        }
    }
}

extension Defaults.Keys {
    /// Appearance is UI configuration, not message state, so it may persist between launches.
    static let appearance = Key<AppearancePreference>("appearance", default: .system)
    /// The selected language is UI configuration only and never contains Gotify message data.
    static let language = Key<LanguagePreference>("language", default: .system)
    /// The URL is retained with the verified connection choice; it contains no token.
    static let serverURL = Key<String>("serverURL", default: "")
    /// This is AES-GCM ciphertext, never a plaintext Gotify token.
    static let encryptedClientToken = Key<String>("encryptedClientToken", default: "")
    /// This is an opt-in receive preference, not persisted message data or an unread state.
    static let receivesMessages = Key<Bool>("receivesMessages", default: false)
    /// A user choice to request macOS banners; it never controls the Gotify connection itself.
    static let systemNotificationsEnabled = Key<Bool>("systemNotificationsEnabled", default: true)
    /// Controls the custom sound attached to native notification requests, never message data.
    static let notificationSoundEnabled = Key<Bool>("notificationSoundEnabled", default: true)
    /// Records whether the current bundle has triggered initial macOS Notification Center registration.
    static let didRegisterNotificationCenter = Key<Bool>("didRegisterNotificationCenterV1", default: false)
}

enum LegacyBundlePreferencesMigration {
    private static let legacyDomain = "com.gotify.desktop"
    private static let migratedFlagKey = "didMigrateLegacyBundleDomainV1"
    private static let keysToMigrate = [
        "appearance",
        "language",
        "serverURL",
        "encryptedClientToken",
        "receivesMessages",
        "notificationSoundEnabled",
    ]

    /// Preserves non-message preferences across the bundle identifier transition away from the
    /// poisoned `com.gotify.desktop` notification registration domain.
    static func migrateIfNeeded() {
        let standard = UserDefaults.standard
        guard !standard.bool(forKey: migratedFlagKey) else { return }
        defer { standard.set(true, forKey: migratedFlagKey) }

        guard let legacyDefaults = UserDefaults(suiteName: legacyDomain) else { return }
        for key in keysToMigrate where standard.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                standard.set(value, forKey: key)
            }
        }
    }
}

/// This adapter is the sole UI-facing owner of the Defaults-backed appearance setting.
@MainActor
final class AppPreferences: ObservableObject {
    @Published var appearance: AppearancePreference {
        didSet {
            Defaults[.appearance] = appearance
            applyAppearance()
        }
    }
    @Published var language: LanguagePreference {
        didSet {
            Defaults[.language] = language
            // @Published emits before didSet. Emit again after persistence so string lookup observes the new language.
            objectWillChange.send()
        }
    }

    init() {
        appearance = Defaults[.appearance]
        language = Defaults[.language]
        applyAppearance()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyAppearance()
            }
        }
    }

    /// AppKit owns window chrome and menu-bar appearance, so this must not be limited to SwiftUI content.
    private func applyAppearance() {
        // Unit tests instantiate preferences without launching an NSApplication.
        guard let application = NSApp else {
            return
        }

        switch appearance {
        case .system:
            application.appearance = nil
        case .dark:
            application.appearance = NSAppearance(named: .darkAqua)
        case .white:
            application.appearance = NSAppearance(named: .aqua)
        }
    }
}

/// Owns the small, non-sensitive notification preference surface that may survive app relaunches.
@MainActor
final class NotificationPreferences: ObservableObject {
    @Published var systemNotificationsEnabled: Bool {
        didSet { Defaults[.systemNotificationsEnabled] = systemNotificationsEnabled }
    }
    @Published var notificationSoundEnabled: Bool {
        didSet { Defaults[.notificationSoundEnabled] = notificationSoundEnabled }
    }

    init() {
        systemNotificationsEnabled = Defaults[.systemNotificationsEnabled]
        notificationSoundEnabled = Defaults[.notificationSoundEnabled]
    }
}
