import AppKit
import SwiftUI

/// Settings exposes persistent choices explicitly, keeping transient inbox state out of preferences.
struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var serverPreferences: ServerPreferences
    @EnvironmentObject private var notificationPreferences: NotificationPreferences
    @EnvironmentObject private var notificationCoordinator: GotifyNotificationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsGroupCard {
                    HStack {
                        Text(Localized.string("settings.server"))
                            .font(.headline)
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
                        .toggleStyle(.switch)
                        .accessibilityLabel(Localized.string("settings.receiveMessages"))
                        .accessibilityIdentifier("receive-messages-toggle")
                    }
                } content: {
                    SettingsLabeledRow(Localized.string("settings.serverURL")) {
                        TextField("", text: $serverPreferences.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .disabled(serverPreferences.isTestingConnection || serverPreferences.receivesMessages)
                            .accessibilityIdentifier("server-url-field")
                    }

                    Divider()

                    SettingsLabeledRow(Localized.string("settings.clientToken")) {
                        SecureField("", text: $serverPreferences.clientToken)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .disabled(serverPreferences.isTestingConnection || serverPreferences.receivesMessages)
                            .accessibilityIdentifier("client-token-field")
                    }

                    if serverPreferences.usesUnencryptedHTTP {
                        Divider()
                        Label(Localized.string("settings.httpWarning"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    if serverPreferences.isTestingConnection {
                        Divider()
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(Localized.string("settings.testingConnection"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if serverPreferences.receivesMessages {
                        Divider()
                        Text(Localized.string("settings.connectionFieldsLocked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let feedbackKey = serverPreferences.feedbackKey {
                        Divider()
                        Text(Localized.string(feedbackKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsGroupCard(title: Localized.string("settings.notifications")) {
                    SettingsLabeledRow(Localized.string("settings.systemNotifications")) {
                        Spacer()
                        Toggle(
                            Localized.string("settings.systemNotifications"),
                            isOn: Binding(
                                get: { notificationPreferences.systemNotificationsEnabled },
                                set: { enabled in
                                    notificationCoordinator.setSystemNotificationsEnabled(enabled)
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(Localized.string("settings.systemNotifications"))
                        .accessibilityIdentifier("system-notifications-toggle")
                    }

                    Divider()

                    SettingsLabeledRow(Localized.string("settings.notificationSound")) {
                        Spacer()
                        Toggle(
                            Localized.string("settings.notificationSound"),
                            isOn: $notificationPreferences.notificationSoundEnabled
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!notificationPreferences.systemNotificationsEnabled)
                        .accessibilityLabel(Localized.string("settings.notificationSound"))
                        .accessibilityIdentifier("notification-sound-toggle")
                    }

                    Divider()

                    HStack {
                        Button(Localized.string("settings.openSystemNotificationSettings")) {
                            notificationCoordinator.openSystemNotificationSettings()
                        }
                        .accessibilityIdentifier("open-system-notification-settings-button")
                        Spacer()
                    }

                    Text(Localized.string("settings.notificationSound.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsGroupCard(title: Localized.string("settings.interface")) {
                    SettingsLabeledRow(Localized.string("settings.appearance")) {
                        Spacer()
                        Picker(Localized.string("settings.appearance"), selection: $preferences.appearance) {
                            ForEach(AppearancePreference.allCases) { appearance in
                                Text(appearance.displayName).tag(appearance)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .accessibilityIdentifier("appearance-picker")
                    }

                    Text(Localized.string("settings.appearance.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    SettingsLabeledRow(Localized.string("settings.language")) {
                        Spacer()
                        Picker(Localized.string("settings.language"), selection: $preferences.language) {
                            ForEach(LanguagePreference.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .accessibilityIdentifier("language-picker")
                    }

                    Text(Localized.string("settings.language.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsGroupCard(title: Localized.string("settings.iconCache")) {
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
                        Spacer()
                    }

                    Text(Localized.string("settings.iconCache.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        // Preference windows are deliberately roomier than the message UI: long localized hints
        // must remain readable without turning server credentials into a dense, unlabeled block.
        .frame(width: 560, height: 560)
    }
}

private struct SettingsGroupCard<Header: View, Content: View>: View {
    let header: Header
    let content: Content

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) where Header == Text {
        self.header = Text(title).font(.headline)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct SettingsLabeledRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(minWidth: 120, alignment: .leading)
            content
        }
    }
}
