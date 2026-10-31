import AppKit
import Combine
import SwiftUI

/// Transparently forwards all `NSWindowDelegate` callbacks to SwiftUI's internal window delegate
/// while intercepting `windowShouldClose(_:)` so closing the main window hides it (`orderOut`)
/// instead of tearing down the SwiftUI window scene.
@MainActor
private final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var originalDelegate: (any NSWindowDelegate)?

    init(originalDelegate: (any NSWindowDelegate)?) {
        self.originalDelegate = originalDelegate
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let originalDelegate, originalDelegate.responds(to: aSelector) {
            return originalDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// Coordinates single-instance main window activation and native Settings window presentation
/// across macOS 12+ without duplicating windows.
@MainActor
final class AppWindowCoordinator: NSObject {
    static let shared = AppWindowCoordinator()

    private var mainWindow: NSWindow?
    private var delegateProxy: MainWindowDelegateProxy?

    func attachMainWindowIfNeeded(_ window: NSWindow?) {
        guard let window else { return }
        if window !== mainWindow {
            mainWindow = window
            window.isReleasedWhenClosed = false
        }
        if !(window.delegate is MainWindowDelegateProxy) {
            let proxy = MainWindowDelegateProxy(originalDelegate: window.delegate)
            delegateProxy = proxy
            window.delegate = proxy
        }
    }

    func openMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let candidate = NSApp.windows.first(where: { $0.canBecomeMain && !$0.className.contains("StatusBar") }) {
            attachMainWindowIfNeeded(candidate)
            candidate.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettingsWindow() {
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

/// Bridges the SwiftUI root view to its hosting `NSWindow` so `AppWindowCoordinator` can manage it.
struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            AppWindowCoordinator.shared.attachMainWindowIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            AppWindowCoordinator.shared.attachMainWindowIfNeeded(nsView.window)
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

        if NSApp != nil, NSApp.isRunning {
            installStatusItemIfNeeded()
        } else {
            NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.installStatusItemIfNeeded()
                }
                .store(in: &cancellables)
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
