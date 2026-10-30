import AppKit
import SwiftUI

/// Settings exposes persistent choices explicitly, keeping transient inbox state out of preferences.
struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var serverPreferences: ServerPreferences
    @EnvironmentObject private var notificationPreferences: NotificationPreferences
    @EnvironmentObject private var notificationCoordinator: GotifyNotificationCoordinator

    var body: some View {
        Form {
            Section {
                LabeledContent(Localized.string("settings.serverURL")) {
                    TextField("", text: $serverPreferences.serverURL)
                        .textContentType(.URL)
                        .labelsHidden()
                        .disabled(serverPreferences.isTestingConnection || serverPreferences.receivesMessages)
                        .accessibilityIdentifier("server-url-field")
                }

                LabeledContent(Localized.string("settings.clientToken")) {
                    SecureField("", text: $serverPreferences.clientToken)
                        .textContentType(.password)
                        .labelsHidden()
                        .disabled(serverPreferences.isTestingConnection || serverPreferences.receivesMessages)
                        .accessibilityIdentifier("client-token-field")
                }

                if serverPreferences.usesUnencryptedHTTP {
                    Label(Localized.string("settings.httpWarning"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if serverPreferences.isTestingConnection {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(Localized.string("settings.testingConnection"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if serverPreferences.receivesMessages {
                    Text(Localized.string("settings.connectionFieldsLocked"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let feedbackKey = serverPreferences.feedbackKey {
                    Text(Localized.string(feedbackKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
            } header: {
                HStack {
                    Text(Localized.string("settings.server"))
                    Spacer()
                    Toggle(
                        Localized.string("settings.receiveMessages"),
                        isOn: Binding(
                            get: { serverPreferences.receivesMessages },
                            set: { enabled in
                                Task { await serverPreferences.setReceivesMessages(enabled) }
                            }
                        )
                    )
                    .labelsHidden()
                    // Form section headers otherwise inherit macOS's checkbox-style Toggle rendering.
                    .toggleStyle(.switch)
                    .accessibilityLabel(Localized.string("settings.receiveMessages"))
                    .accessibilityIdentifier("receive-messages-toggle")
                }
            }

            Section(Localized.string("settings.notifications")) {
                Toggle(
                    Localized.string("settings.systemNotifications"),
                    isOn: Binding(
                        get: { notificationPreferences.systemNotificationsEnabled },
                        set: { enabled in
                            notificationCoordinator.setSystemNotificationsEnabled(enabled)
                        }
                    )
                )
                .toggleStyle(.switch)
                .accessibilityIdentifier("system-notifications-toggle")

                Toggle(Localized.string("settings.notificationSound"), isOn: $notificationPreferences.notificationSoundEnabled)
                    .toggleStyle(.switch)
                    .disabled(!notificationPreferences.systemNotificationsEnabled)
                    .accessibilityIdentifier("notification-sound-toggle")

                Text(Localized.string("settings.notificationSound.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Localized.string("settings.interface")) {
                Picker(Localized.string("settings.appearance"), selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("appearance-picker")

                Text(Localized.string("settings.appearance.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(Localized.string("settings.language"), selection: $preferences.language) {
                    ForEach(LanguagePreference.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("language-picker")

                Text(Localized.string("settings.language.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Localized.string("settings.iconCache")) {
                Text(GotifyIconPipeline.cacheDirectory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button(Localized.string("settings.showIconCache")) {
                        // The cache directory contains application icons only; Finder is the clearest inspection surface.
                        NSWorkspace.shared.activateFileViewerSelecting([GotifyIconPipeline.cacheDirectory])
                    }
                    .accessibilityIdentifier("show-icon-cache-button")

                    Button(Localized.string("settings.clearIconCache")) {
                        // Nuke owns its cache format and both its memory/disk cleanup, so no files are deleted manually.
                        GotifyIconPipeline.clear()
                    }
                    .accessibilityIdentifier("clear-icon-cache-button")
                }

                Text(Localized.string("settings.iconCache.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Preference windows are deliberately roomier than the message UI: long localized hints
        // must remain readable without turning server credentials into a dense, unlabeled block.
        .padding(20)
        .frame(width: 560, height: 560)
    }
}
