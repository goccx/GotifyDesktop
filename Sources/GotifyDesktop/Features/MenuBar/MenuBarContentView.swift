import AppKit
import Combine
import SwiftUI

/// Coordinates single-instance main window activation and native Settings window presentation
/// across macOS 12+ without touching SwiftUI's internal `NSWindow.delegate`.
@MainActor
final class AppWindowCoordinator: NSObject {
    static let shared = AppWindowCoordinator()

    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var windowDiscoveryCancellable: AnyCancellable?

    override init() {
        super.init()
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.attachMainWindowIfCandidate(window)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.attachMainWindowIfCandidate(window)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let closingWindow = notification.object as? NSWindow,
                      self.isSettingsWindow(closingWindow)
                else { return }
                DispatchQueue.main.async {
                    self.updateActivationPolicy(ignoringClosingWindow: closingWindow)
                }
            }
            .store(in: &cancellables)

        windowDiscoveryCancellable = NotificationCenter.default.publisher(for: NSWindow.didUpdateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, self.mainWindow == nil, let window = notification.object as? NSWindow else { return }
                self.attachMainWindowIfCandidate(window)
            }
    }

    var hasMainWindow: Bool {
        if mainWindow != nil { return true }
        return (NSApp?.windows ?? []).contains {
            $0.canBecomeMain && !$0.className.contains("StatusBar") && !isSettingsWindow($0)
        }
    }

    func startObserving() {
        for window in NSApp?.windows ?? [] {
            attachMainWindowIfCandidate(window)
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.title.contains("设置")
            || window.title.contains("Settings")
            || window.title.contains("Preferences")
    }

    private func attachMainWindowIfCandidate(_ window: NSWindow) {
        guard window.canBecomeMain,
              !window.className.contains("StatusBar"),
              !isSettingsWindow(window)
        else { return }

        if let mainWindow {
            if window !== mainWindow {
                // Close any duplicate WindowGroup window immediately and activate the single mainWindow.
                DispatchQueue.main.async { [weak self] in
                    window.isRestorable = false
                    window.delegate = nil
                    window.orderOut(nil)
                    window.close()
                    self?.openMainWindow()
                }
            }
            return
        }

        mainWindow = window
        windowDiscoveryCancellable = nil
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 600)
        if window.frame.width < 900 || window.frame.height < 600 {
            window.setContentSize(NSSize(width: 1_080, height: 720))
            window.center()
        }
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(handleCloseButton(_:))
        }
    }

    @objc private func handleCloseButton(_ sender: Any?) {
        mainWindow?.orderOut(nil)
        updateActivationPolicy(ignoringClosingWindow: nil)
    }

    private func updateActivationPolicy(ignoringClosingWindow: NSWindow?) {
        let hasVisibleAppWindow = (NSApp?.windows ?? []).contains { window in
            guard window !== ignoringClosingWindow,
                  window.canBecomeMain,
                  !window.className.contains("StatusBar")
            else { return false }
            return window.isVisible || window.isMiniaturized
        }
        if !hasVisibleAppWindow, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func ensureRegularActivationPolicy() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func openMainWindow() {
        ensureRegularActivationPolicy()
        if let mainWindow {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let candidate = NSApp.windows.first(where: { $0.canBecomeMain && !$0.className.contains("StatusBar") && !isSettingsWindow($0) }) {
            attachMainWindowIfCandidate(candidate)
            if candidate.isMiniaturized {
                candidate.deminiaturize(nil)
            }
            candidate.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettingsWindow() {
        ensureRegularActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
            appMenu.performActionForItem(at: index)
            return
        }
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

/// Owns the native AppKit status bar item (`NSStatusItem`) and `NSMenu` so the menu bar bell
/// works identically from macOS 12 through macOS 15+.
@MainActor
final class MenuBarStatusController: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let appTitleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let openMainWindowItem = NSMenuItem(title: "", action: #selector(handleOpenMainWindow), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: #selector(handleQuit), keyEquivalent: "")
    private var cancellables = Set<AnyCancellable>()
    private weak var messageStore: MessageStore?
    private weak var preferences: AppPreferences?

    func configure(messageStore: MessageStore, preferences: AppPreferences) {
        self.messageStore = messageStore
        self.preferences = preferences

        // `GotifyAppBootstrap.init()` runs while `didFinishLaunchingNotification` is already being
        // dispatched by AppKit (before `NSApp.isRunning` turns true). Scheduling on the main queue
        // guarantees both status-item installation and initial window attachment always execute.
        AppWindowCoordinator.shared.startObserving()
        DispatchQueue.main.async { [weak self] in
            AppWindowCoordinator.shared.startObserving()
            self?.installStatusItemIfNeeded()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil, let messageStore, let preferences else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        appTitleItem.isEnabled = false
        connectionItem.isEnabled = false
        openMainWindowItem.target = self
        openMainWindowItem.setAccessibilityIdentifier("menu-open-app-button")
        quitItem.target = self
        quitItem.setAccessibilityIdentifier("menu-quit-app-button")

        menu.delegate = self
        menu.addItem(appTitleItem)
        menu.addItem(connectionItem)
        menu.addItem(.separator())
        menu.addItem(openMainWindowItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu

        messageStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        guard let messageStore else { return }
        if let button = statusItem?.button {
            let image = NSImage(
                systemSymbolName: "bell",
                accessibilityDescription: Localized.string("message.newMessagesAccessibility", messageStore.newMessageCount)
            )
            image?.isTemplate = true
            button.image = image
            let count = messageStore.newMessageCount
            if count > 0 {
                button.title = "\(NewMessageCountFormat.display(count)) "
                button.imagePosition = .imageRight
            } else {
                button.title = ""
                button.imagePosition = .imageOnly
            }
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.setAccessibilityLabel(Localized.string("message.newMessagesAccessibility", count))
        }

        appTitleItem.title = Localized.string("app.name")
        connectionItem.title = connectionText(for: messageStore.connectionState)
        openMainWindowItem.title = Localized.string("menu.openMainWindow")
        quitItem.title = Localized.string("menu.quit")
    }

    private func connectionText(for state: MessageStore.ConnectionState) -> String {
        switch state {
        case .notConfigured: Localized.string("connection.notConfigured")
        case .connecting: Localized.string("connection.connecting")
        case .connected: Localized.string("connection.connected")
        case .disconnected: Localized.string("connection.disconnected")
        }
    }

    @objc private func handleOpenMainWindow() {
        AppWindowCoordinator.shared.openMainWindow()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
