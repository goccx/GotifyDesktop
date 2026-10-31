import SwiftUI
import NukeUI
import SwiftUIIntrospect

/// The fixed two-column shell prevents a detail inspector from resizing the app window.
struct InboxView: View {
    @EnvironmentObject private var messageStore: MessageStore
    /// Language changes update localized values without replacing the native toolbar's identity.
    @EnvironmentObject private var preferences: AppPreferences
    /// The token is supplied only to authenticated icon requests and is never serialized by the image cache.
    @EnvironmentObject private var serverPreferences: ServerPreferences
    @EnvironmentObject private var notificationCoordinator: GotifyNotificationCoordinator
    @State private var selection: SidebarSelection? = .allMessages
    @State private var readyPage: MessagePage = .all
    @State private var transitionID = UUID()
    @State private var pageSwitchTask: Task<Void, Never>?
    @State private var pendingSingleDeleteMessage: GotifyMessage?
    @State private var pendingBulkDeletePage: MessagePage?
    @State private var showsDeleteErrorAlert = false
    @State private var sidebarReselectionVersion = UUID()
    @State private var selectedMessage: GotifyMessage?
    @State private var isNavigatingFromNotification = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `page` always follows `selectedPage` at T0 so the previous page's messages can never
        // linger on screen. When switching to a non-empty page, `isTransitioning` is synchronously
        // true on Frame T0, presenting `.loading` immediately until the T0 frame commits.
        let page = selectedPage
        let pageItems = messageStore.timelineItems(for: page)
        let isTransitioning = readyPage != page && !pageItems.isEmpty
        SplitNavigationContainer {
            SidebarView(
                selection: $selection,
                sources: sourceItems,
                newMessageCount: messageStore.newMessageCount,
                newMessageCountsBySource: newMessageCountsBySource,
                clientToken: serverPreferences.clientToken,
                reselectCurrentItem: {
                    sidebarReselectionVersion = UUID()
                },
                requestBulkDelete: { targetPage in
                    pendingBulkDeletePage = targetPage
                }
            )
        } detail: {
            ReadingCanvas(
                timelineItems: isTransitioning ? [] : pageItems,
                page: page,
                sidebarReselectionVersion: sidebarReselectionVersion,
                navigationTitle: navigationTitle,
                pageLoadState: isTransitioning ? .loading(transitionID) : messageStore.pageLoadState(for: page),
                hasNextPage: !isTransitioning && messageStore.hasNextPage(for: page),
                scrollAnchorID: messageStore.scrollAnchorID(for: page),
                hasPendingLiveMessages: messageStore.hasPendingLiveMessages(for: page),
                newMessageCount: messageStore.newMessageCount(for: page),
                isNewMessage: { messageStore.isNewMessage($0.id, sourceID: $0.sourceID) },
                clientToken: serverPreferences.clientToken,
                markMessageViewed: messageStore.markMessageViewed,
                markAllMessagesViewed: { messageStore.markAllMessagesViewed(for: page) },
                retryLoading: loadSelectedPage,
                loadMore: { gapID in try await serverPreferences.loadMoreMessages(for: page.sourceID, gapID: gapID) },
                loadNextPage: { try await serverPreferences.loadNextPage(for: page.sourceID) },
                revealPendingLiveMessages: { await messageStore.revealPendingLiveMessages(for: page) },
                setMessageVisibility: { id, visible in setMessageVisibility(id, visible, for: page) },
                consumeScrollAnchor: { id in consumeScrollAnchor(id, for: page) },
                deleteMessage: { message in pendingSingleDeleteMessage = message },
                requestBulkDelete: { pendingBulkDeletePage = page },
                selectedMessage: $selectedMessage
            )
        }
        .confirmationDialog(
            Localized.string("message.delete.confirm.title"),
            isPresented: Binding(
                get: { pendingSingleDeleteMessage != nil },
                set: { if !$0 { pendingSingleDeleteMessage = nil } }
            ),
            presenting: pendingSingleDeleteMessage
        ) { targetMessage in
            Button(Localized.string("message.delete.confirmAction"), role: .destructive) {
                pendingSingleDeleteMessage = nil
                performDeleteMessage(targetMessage)
            }
            .accessibilityIdentifier("confirm-delete-message-button")
            Button(Localized.string("message.delete.cancelAction"), role: .cancel) {
                pendingSingleDeleteMessage = nil
            }
        } message: { targetMessage in
            let summary = MessageMarkdownParser.plainTextSummary(
                from: targetMessage.title.isEmpty ? targetMessage.body : targetMessage.title
            )
            Text(Localized.string("message.delete.confirm.description", summary))
        }
        .confirmationDialog(
            bulkDeleteConfirmationTitle(for: pendingBulkDeletePage),
            isPresented: Binding(
                get: { pendingBulkDeletePage != nil },
                set: { if !$0 { pendingBulkDeletePage = nil } }
            ),
            presenting: pendingBulkDeletePage
        ) { targetPage in
            Button(Localized.string("message.delete.confirmAction"), role: .destructive) {
                pendingBulkDeletePage = nil
                deleteAllMessages(for: targetPage)
            }
            .accessibilityIdentifier("confirm-bulk-delete-messages-button")
            Button(Localized.string("message.delete.cancelAction"), role: .cancel) {
                pendingBulkDeletePage = nil
            }
        } message: { targetPage in
            Text(bulkDeleteConfirmationDescription(for: targetPage))
        }
        .alert(
            Localized.string("inbox.deleteFailed.title"),
            isPresented: $showsDeleteErrorAlert
        ) {
            Button(Localized.string("message.delete.cancelAction"), role: .cancel) {}
        } message: {
            Text(Localized.string("inbox.deleteFailed.description"))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConnectionStatusLabel(state: messageStore.connectionState, language: preferences.language)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppWindowCoordinator.shared.openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help(Localized.string("settings.open"))
                .accessibilityLabel(Localized.string("settings.open"))
                .accessibilityIdentifier("settings-button")
            }
        }
        // The application menu is AppKit-owned rather than a SwiftUI view, so language changes require this bridge.
        .onAppear {
            ApplicationMenuLocalization.apply(appName: Localized.string("app.name"))
            if let target = notificationCoordinator.activatedTarget {
                handleActivatedNotification(target)
            }
        }
        .onChange(of: preferences.language) { _ in
            ApplicationMenuLocalization.apply(appName: Localized.string("app.name"))
        }
        .onChange(of: selection) { _ in
            if isNavigatingFromNotification {
                isNavigatingFromNotification = false
            } else {
                selectedMessage = nil
            }
            schedulePageSwitch(to: selectedPage)
        }
        .onChange(of: notificationCoordinator.activatedTarget) { target in
            guard let target else { return }
            handleActivatedNotification(target)
        }
        .onChange(of: messageStore.sessionVersion) { _ in
            selectedMessage = nil
        }
    }

    private func handleActivatedNotification(_ target: GotifyNotificationCoordinator.ActivatedNotificationTarget) {
        notificationCoordinator.consumeActivatedTarget(target)
        Task { @MainActor in
            guard let message = await messageStore.findMessage(id: target.messageID) else { return }
            let currentPage = selectedPage
            if case let .application(currentSourceID) = currentPage, currentSourceID != target.sourceID {
                isNavigatingFromNotification = true
                selection = .source(id: target.sourceID)
            }
            messageStore.markMessageViewed(message.id, sourceID: message.sourceID)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selectedMessage = message
            }
        }
    }

    private func schedulePageSwitch(to targetPage: MessagePage) {
        pageSwitchTask?.cancel()
        let sourceID = targetPage.sourceID
        let hasMessages = !messageStore.timelineItems(for: targetPage).isEmpty

        if !hasMessages {
            readyPage = targetPage
            Task {
                await serverPreferences.loadMessages(for: sourceID)
                await messageStore.revealPendingLiveMessages(for: targetPage)
            }
            return
        }

        // Frame T0 is already rendering `.loading(transitionID)` with `timelineItems: []`
        // synchronously via `isTransitioning`. Wait for T0 to commit to WindowServer, then
        // mark `readyPage = targetPage` so Frame T1 mounts the target message list.
        transitionID = UUID()
        pageSwitchTask = Task { @MainActor in
            await Self.waitForCurrentFrameCommit()
            guard !Task.isCancelled else { return }
            readyPage = targetPage
            await serverPreferences.loadMessages(for: sourceID)
            await messageStore.revealPendingLiveMessages(for: targetPage)
        }
    }

    /// Bridges CoreAnimation's transaction commit callback into structured concurrency (zero sleep).
    /// Resumes on the next main-queue turn strictly after the current T0 frame has committed.
    @MainActor
    private static func waitForCurrentFrameCommit() async {
        await withCheckedContinuation { continuation in
            let existingBlock = CATransaction.completionBlock()
            CATransaction.setCompletionBlock {
                existingBlock?()
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }

    /// Sources come only from the live session; the UI must never invent demo applications.
    private var sourceItems: [SidebarSource] {
        messageStore.applications.map { SidebarSource(id: $0.id, name: $0.name, iconURL: $0.iconURL) }
    }

    /// Source attention is independent from message pagination, so a loaded history page cannot change this count.
    private var newMessageCountsBySource: [Int64: Int] {
        Dictionary(uniqueKeysWithValues: sourceItems.map { ($0.id, messageStore.newMessageCount(for: $0.id)) })
    }

    private var selectedPage: MessagePage {
        selection?.sourceID.map(MessagePage.application) ?? .all
    }

    private var navigationTitle: String {
        guard let sourceID = selection?.sourceID else {
            return Localized.string("sidebar.allMessages")
        }
        return sourceItems.first(where: { $0.id == sourceID })?.name
            ?? Localized.string("sidebar.allMessages")
    }

    /// Selection changes immediately; the controller performs any missing REST page request off the UI path.
    private func loadSelectedPage() {
        let sourceID = selection?.sourceID
        Task { await serverPreferences.loadMessages(for: sourceID) }
    }

    /// The actor uses this transient signal only to protect the reading anchor during reclamation.
    private func setMessageVisibility(_ messageID: Int64, _ visible: Bool, for page: MessagePage) {
        Task { await messageStore.setMessageVisibility(messageID, visible: visible, for: page) }
    }

    private func consumeScrollAnchor(_ anchorID: Int64, for page: MessagePage) {
        Task { await messageStore.consumeScrollAnchor(anchorID, for: page) }
    }

    private func performDeleteMessage(_ message: GotifyMessage) {
        Task {
            do {
                try await serverPreferences.deleteMessage(message)
                if selectedMessage?.id == message.id {
                    selectedMessage = nil
                }
            } catch {
                showsDeleteErrorAlert = true
            }
        }
    }

    private func deleteAllMessages(for page: MessagePage) {
        Task {
            do {
                try await serverPreferences.deleteMessages(for: page.sourceID)
                if let current = selectedMessage {
                    if page == .all || page == .application(current.sourceID) {
                        selectedMessage = nil
                    }
                }
            } catch {
                showsDeleteErrorAlert = true
            }
        }
    }

    private func bulkDeleteConfirmationTitle(for page: MessagePage?) -> String {
        switch page {
        case .all, .none:
            Localized.string("message.deleteAll.confirm.title")
        case let .application(sourceID):
            Localized.string("message.deleteSourceAll.confirm.title", sourceName(for: sourceID))
        }
    }

    private func bulkDeleteConfirmationDescription(for page: MessagePage) -> String {
        switch page {
        case .all:
            Localized.string("message.deleteAll.confirm.description")
        case let .application(sourceID):
            Localized.string("message.deleteSourceAll.confirm.description", sourceName(for: sourceID))
        }
    }

    private func sourceName(for sourceID: Int64) -> String {
        sourceItems.first(where: { $0.id == sourceID })?.name ?? "#\(sourceID)"
    }

}

/// Sidebar selection contains only stable navigation identity, never mutable server presentation metadata.
private enum SidebarSelection: Hashable, Identifiable {
    case allMessages
    case source(id: Int64)

    var id: Self { self }

    var sourceID: Int64? {
        guard case let .source(id) = self else { return nil }
        return id
    }
}

/// Presentation belongs to the current in-memory snapshot, separately from the stable selection ID.
private struct SidebarSource: Identifiable {
    let id: Int64
    let name: String
    let iconURL: URL?
}

/// Counts are plain secondary text, not persistent unread badges: Gotify has no server-side unread state.
private struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    let sources: [SidebarSource]
    let newMessageCount: Int
    let newMessageCountsBySource: [Int64: Int]
    let clientToken: String
    let reselectCurrentItem: () -> Void
    let requestBulkDelete: (MessagePage) -> Void

    var body: some View {
        List(selection: $selection) {
            NavigationSidebarRow(
                title: Localized.string("sidebar.allMessages"),
                systemImage: "tray.full",
                count: newMessageCount,
                isSelected: selection == .allMessages
            )
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    if selection == .allMessages {
                        reselectCurrentItem()
                    }
                }
            )
            .tag(SidebarSelection.allMessages)
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(SidebarSelectionBackground(isSelected: selection == .allMessages))
            .contextMenu {
                Button(role: .destructive) {
                    requestBulkDelete(.all)
                } label: {
                    Label(Localized.string("message.deleteAll"), systemImage: "trash")
                }
                .accessibilityIdentifier("sidebar-delete-all-messages-button")
            }
            .accessibilityIdentifier("all-messages-sidebar-item")

            ForEach(sources) { source in
                let item = SidebarSelection.source(id: source.id)
                NavigationSidebarRow(
                    title: source.name,
                    iconURL: source.iconURL,
                    count: newMessageCountsBySource[source.id] ?? 0,
                    clientToken: clientToken,
                    isSelected: selection == item
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if selection == item {
                            reselectCurrentItem()
                        }
                    }
                )
                .tag(item)
                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                .listRowBackground(SidebarSelectionBackground(isSelected: selection == item))
                .contextMenu {
                    Button(role: .destructive) {
                        requestBulkDelete(.application(source.id))
                    } label: {
                        Label(Localized.string("message.deleteSourceAll"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("sidebar-delete-source-messages-\(source.id)")
                }
                .accessibilityIdentifier("source-sidebar-item-\(source.id)")
            }
        }
        .listStyle(.sidebar)
        // SwiftUI does not expose NSTableView.selectionHighlightStyle. This mature adapter uses
        // public AppKit introspection only; native selection, scrolling, keyboard navigation, and
        // accessibility remain owned by the table view.
        .introspect(.list(style: .sidebar), on: .macOS(.v12, .v13, .v14, .v15, .v26)) { tableView in
            if tableView.selectionHighlightStyle != .none {
                tableView.selectionHighlightStyle = .none
            }
            if tableView.usesAlternatingRowBackgroundColors {
                tableView.usesAlternatingRowBackgroundColors = false
            }
        }
        .navigationTitle(Localized.string("app.name"))
        .accessibilityIdentifier("sidebar-navigation")
    }
}

/// Keeps source names at a readable text hierarchy; selection color is supplied by the navigation button.
private struct NavigationSidebarRow: View {
    let title: String
    var systemImage: String?
    var iconURL: URL?
    let count: Int
    var clientToken = ""
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let iconURL {
                GotifyApplicationIcon(url: iconURL, clientToken: clientToken, size: 24)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)

            if count > 0 {
                Text(NewMessageCountFormat.display(count))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Localized.string("message.newMessagesAccessibility", count))
            }
        }
        // The native table owns the full-row hit target, selection, keyboard navigation and focus.
        .frame(minHeight: 48)
        // The selection surface fills the sidebar; only the row content receives horizontal inset.
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }
}

/// A neutral selected surface remains visually stable whether this window is key or inactive.
private struct SidebarSelectionBackground: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selectionColor)
            .padding(.vertical, 1)
    }

    private var selectionColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.07)
    }
}

/// A standard toolbar label uses a semantic system color only for its symbol.
/// This preserves the native toolbar hierarchy while making a healthy connection scannable at a glance.
private struct ConnectionStatusLabel: View {
    let state: MessageStore.ConnectionState
    /// This explicit dependency refreshes text on an in-app language change without replacing the toolbar item.
    let language: LanguagePreference

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            Text(title)
        }
            .accessibilityLabel(title)
            .accessibilityIdentifier("connection-status")
    }

    private var title: String {
        // `Localized` reads the persisted preference; retaining this value makes SwiftUI invalidate this label immediately.
        _ = language
        return switch state {
        case .notConfigured: Localized.string("connection.notConfigured")
        case .connecting: Localized.string("connection.connecting")
        case .connected: Localized.string("connection.connected")
        case .disconnected: Localized.string("connection.disconnected")
        }
    }

    /// These are macOS semantic state cues, not product branding or a custom status component.
    private var symbolColor: Color {
        switch state {
        case .notConfigured:
            .secondary
        case .connecting:
            .orange
        case .connected:
            .green
        case .disconnected:
            .red
        }
    }
}

/// The right canvas replaces content in-place, preserving window geometry for every state.
private struct ReadingCanvas: View {
    let timelineItems: [MessageTimelineItem]
    let page: MessagePage
    let sidebarReselectionVersion: UUID
    let navigationTitle: String
    let pageLoadState: MessagePageLoadState
    let hasNextPage: Bool
    let scrollAnchorID: Int64?
    let hasPendingLiveMessages: Bool
    let newMessageCount: Int
    let isNewMessage: (GotifyMessage) -> Bool
    let clientToken: String
    let markMessageViewed: (Int64, Int64) -> Void
    let markAllMessagesViewed: () -> Void
    let retryLoading: () -> Void
    let loadMore: (UUID) async throws -> Void
    let loadNextPage: () async throws -> Void
    let revealPendingLiveMessages: () async -> Void
    let setMessageVisibility: (Int64, Bool) -> Void
    let consumeScrollAnchor: (Int64) -> Void
    let deleteMessage: (GotifyMessage) -> Void
    let requestBulkDelete: () -> Void
    @Binding var selectedMessage: GotifyMessage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Keep the list mounted under the detail canvas. Returning therefore preserves the
            // native List's scroll position and per-row image/timestamp lifetime.
            Group {
                switch pageLoadState {
                case .loading:
                    ProgressView(Localized.string("inbox.loading"))
                        .controlSize(.regular)
                case .failed:
                    VStack(spacing: 16) {
                        EmptyStatePlaceholderView(
                            title: Localized.string("inbox.loadFailed.title"),
                            systemImage: "exclamationmark.icloud",
                            description: Localized.string("inbox.loadFailed.description")
                        )
                        Button(Localized.string("inbox.retry"), action: retryLoading)
                            .accessibilityIdentifier("retry-message-page-button")
                    }
                case .idle, .loaded:
                    if timelineItems.isEmpty {
                        EmptyStatePlaceholderView(
                            title: Localized.string("inbox.empty.title"),
                            systemImage: "bell.badge",
                            description: Localized.string("inbox.empty.description")
                        )
                    } else {
                        MessageListView(
                            timelineItems: timelineItems,
                            page: page,
                            newMessageCount: newMessageCount,
                            hasNextPage: hasNextPage,
                            scrollAnchorID: scrollAnchorID,
                            hasPendingLiveMessages: hasPendingLiveMessages,
                            isPresented: selectedMessage == nil,
                            isNewMessage: isNewMessage,
                            clientToken: clientToken,
                            markAllMessagesViewed: markAllMessagesViewed,
                            loadMore: loadMore,
                            loadNextPage: loadNextPage,
                            revealPendingLiveMessages: revealPendingLiveMessages,
                            setMessageVisibility: setMessageVisibility,
                            consumeScrollAnchor: consumeScrollAnchor,
                            deleteMessage: deleteMessage,
                            requestBulkDelete: requestBulkDelete
                        ) { message in
                            markMessageViewed(message.id, message.sourceID)
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                selectedMessage = message
                            }
                        }
                        // Only explicit source navigation starts another List lifetime. Pagination
                        // keeps this page ID unchanged; the tail row itself never receives an ID.
                        .id(page)
                    }
                }
            }
            .opacity(selectedMessage == nil ? 1 : 0)
            .allowsHitTesting(selectedMessage == nil)
            .accessibilityHidden(selectedMessage != nil)
            if let selectedMessage {
                MessageDetailView(
                    message: selectedMessage,
                    deleteMessage: {
                        deleteMessage(selectedMessage)
                    }
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        self.selectedMessage = nil
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: sidebarReselectionVersion) { _ in
            guard selectedMessage != nil else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selectedMessage = nil
            }
        }
    }
}

/// Uniform rows keep message density calm even when bodies vary substantially in length.
private struct MessageListView: View {
    let timelineItems: [MessageTimelineItem]
    let page: MessagePage
    let newMessageCount: Int
    let hasNextPage: Bool
    let scrollAnchorID: Int64?
    let hasPendingLiveMessages: Bool
    let isPresented: Bool
    let isNewMessage: (GotifyMessage) -> Bool
    let clientToken: String
    let markAllMessagesViewed: () -> Void
    let loadMore: (UUID) async throws -> Void
    let loadNextPage: () async throws -> Void
    let revealPendingLiveMessages: () async -> Void
    let setMessageVisibility: (Int64, Bool) -> Void
    let consumeScrollAnchor: (Int64) -> Void
    let deleteMessage: (GotifyMessage) -> Void
    let requestBulkDelete: () -> Void
    let selectMessage: (GotifyMessage) -> Void
    @Environment(\.locale) private var locale
    @State private var isTopBarHovered = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if isPresented && (newMessageCount > 0 || hasPendingLiveMessages) {
                    newMessagesTopBar(proxy: proxy)
                    Divider()
                }

                List {
                    // `List` virtualizes rows. A gap loads only when it enters the visible range.
                    ForEach(timelineItems) { item in
                        MessageTimelineListRow(
                            item: item,
                            page: page,
                            isNewMessage: isNewMessage,
                            clientToken: clientToken,
                            locale: locale,
                            isPresented: isPresented,
                            selectMessage: selectMessage,
                            deleteMessage: deleteMessage,
                            requestBulkDelete: requestBulkDelete,
                            loadMore: loadMore,
                            setMessageVisibility: setMessageVisibility
                        )
                    }
                    // A fixed row container matches the reference timeline's footer structure.
                    // No explicit footer ID: appending history must not anchor scrolling to the footer.
                    ZStack {
                        if hasNextPage {
                            NextMessagePageSentinel(isEnabled: isPresented, loadNextPage: loadNextPage)
                        }
                    }
                    .compatibleHiddenListRowSeparator()
                }
                .listStyle(.inset)
                .accessibilityIdentifier("message-timeline-list")
                // Explicit top-bar reveal keeps the newest arrival at the top of the feed visible.
                .onChange(of: scrollAnchorID) { anchorID in
                    guard let anchorID else { return }
                    if isPresented {
                        proxy.scrollTo(timelineItems.first?.id ?? "message-\(anchorID)", anchor: .top)
                    }
                    consumeScrollAnchor(anchorID)
                }
            }
        }
    }

    /// Top bar for unread / pending live messages: clicking the main area reveals pending messages
    /// and scrolls to the top while keeping each message unread until its detail view is opened;
    /// the trailing action explicitly marks all messages in the current scope as viewed.
    private func newMessagesTopBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            Button {
                Task {
                    await revealPendingLiveMessages()
                    if let firstID = timelineItems.first?.id {
                        proxy.scrollTo(firstID, anchor: .top)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                    Text(newMessageHeader)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(newMessageHeader)
            .accessibilityIdentifier("show-new-messages-button")

            if newMessageCount > 0 {
                Button(action: markAllMessagesViewed) {
                    Text(Localized.string("message.markAllViewed"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mark-all-messages-viewed-button")
            }
        }
        .background(isTopBarHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
        .background(.bar)
        .onHover { hovering in
            isTopBarHovered = hovering
        }
    }

    /// The exact count remains available to accessibility; the visual counter follows the agreed compact cap.
    private var newMessageHeader: String {
        if newMessageCount == 0 { return Localized.string("message.latestMessagesAvailable") }
        return newMessageCount > NewMessageCountFormat.visualMaximum
            ? Localized.string("message.newMessagesOverflowHeader")
            : Localized.string("message.newMessagesHeader", newMessageCount)
    }
}

/// The terminal sentinel clean-room aligns with Ice Cubes' `NextPageView`: one local loading state,
/// a task on row appearance, and a retry control only when the request throws.
private struct NextMessagePageSentinel: View {
    let isEnabled: Bool
    let loadNextPage: () async throws -> Void
    var loadingIdentifier = "next-message-page-sentinel"
    var retryIdentifier = "retry-next-message-page-button"
    @State private var isLoading = false
    @State private var showsRetry = false

    var body: some View {
        HStack {
            Spacer()
            if showsRetry {
                Button(Localized.string("inbox.retry")) {
                    Task { await requestNextPage() }
                }
                    .accessibilityIdentifier(retryIdentifier)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier(loadingIdentifier)
            }
            Spacer()
        }
        // Native task cancellation also suspends pagination while a detail overlays this List.
        // Appending messages changes neither this key nor a tail row's explicit identity.
        .task(id: isEnabled) {
            guard isEnabled else { return }
            await requestNextPage()
        }
    }

    /// The loading guard covers this row's async request. A transport error alone exposes retry;
    /// ordinary body updates do not restart a `.task` for a row whose identity is unchanged.
    private func requestNextPage() async {
        guard isEnabled, !isLoading, !Task.isCancelled else { return }
        isLoading = true
        showsRetry = false
        defer { isLoading = false }
        do {
            try await loadNextPage()
        } catch {
            // Cancellation is navigation/lifecycle, not a failed network operation to retry.
            showsRetry = !Task.isCancelled && !(error is CancellationError)
        }
    }
}

/// The outer stack always contributes one List row, regardless of its message/gap content.
/// This preserves the reference timeline's row structure and efficient native identification.
private struct MessageTimelineListRow: View {
    let item: MessageTimelineItem
    let page: MessagePage
    let isNewMessage: (GotifyMessage) -> Bool
    let clientToken: String
    let locale: Locale
    let isPresented: Bool
    let selectMessage: (GotifyMessage) -> Void
    let deleteMessage: (GotifyMessage) -> Void
    let requestBulkDelete: () -> Void
    let loadMore: (UUID) async throws -> Void
    let setMessageVisibility: (Int64, Bool) -> Void

    var body: some View {
        ZStack {
            switch item {
            case let .message(message):
                MessageListRow(
                    message: message,
                    isNew: isNewMessage(message),
                    clientToken: clientToken,
                    locale: locale,
                    select: selectMessage,
                    delete: deleteMessage
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteMessage(message)
                    } label: {
                        Label(Localized.string("message.delete"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("swipe-delete-message-\(message.id)")
                }
                .contextMenu {
                    Button(role: .destructive) {
                        deleteMessage(message)
                    } label: {
                        Label(Localized.string("message.delete"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("context-delete-message-\(message.id)")

                    Divider()

                    Button(role: .destructive, action: requestBulkDelete) {
                        Label(
                            Localized.string(page == .all ? "message.deleteAll" : "message.deleteSourceAll"),
                            systemImage: "trash"
                        )
                    }
                    .accessibilityIdentifier("context-delete-page-messages-\(message.id)")
                }
                .onAppear { setMessageVisibility(message.id, true) }
                .onDisappear { setMessageVisibility(message.id, false) }
            case let .gap(gap):
                NextMessagePageSentinel(
                    isEnabled: isPresented,
                    loadNextPage: { try await loadMore(gap.id) },
                    loadingIdentifier: "load-more-messages-footer-\(gap.id)",
                    retryIdentifier: "retry-load-more-messages-button-\(gap.id)"
                )
            }
        }
    }
}

/// One semantic full-row button keeps message selection and row presentation consistent.
private struct MessageListRow: View {
    let message: GotifyMessage
    let isNew: Bool
    let clientToken: String
    let locale: Locale
    let select: (GotifyMessage) -> Void
    let delete: (GotifyMessage) -> Void
    @State private var isRowHovered = false
    @State private var isDeleteHovered = false

    private var showsDeleteButton: Bool {
        isRowHovered || isDeleteHovered
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { select(message) } label: {
                // Only values participate in presentation equality. The button action stays current,
                // while unchanged old image/timestamp content skips parent-driven body recomputation.
                MessageRowContent(message: message, isNew: isNew, clientToken: clientToken, locale: locale)
                    .equatable()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("message-row-\(message.id)")

            MessageDeleteButton(
                messageID: message.id,
                isVisible: showsDeleteButton,
                isHovered: $isDeleteHovered
            ) {
                delete(message)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isRowHovered = hovering
        }
    }
}

/// Slightly larger native borderless delete icon that appears only when the row is hovered/active
/// and highlights the symbol itself on hover.
private struct MessageDeleteButton: View {
    let messageID: Int64
    let isVisible: Bool
    @Binding var isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isHovered ? Color.red : Color.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .opacity(isVisible ? 1 : 0)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(Localized.string("message.delete"))
        .accessibilityLabel(Localized.string("message.delete"))
        .accessibilityIdentifier("delete-message-button-\(messageID)")
    }
}

/// Pure row presentation allows SwiftUI's built-in EquatableView to reuse unchanged old content
/// during tail appends, without freezing actions, language changes, or each label's own timeline.
private struct MessageRowContent: View, Equatable {
    let message: GotifyMessage
    let isNew: Bool
    let clientToken: String
    let locale: Locale

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GotifyApplicationIcon(url: message.sourceIconURL, clientToken: clientToken, size: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isNew { Circle().fill(.blue).frame(width: 7, height: 7) }
                    Text(
                        MessageMarkdownParser.plainTextSummary(
                            from: message.title.isEmpty ? message.body : message.title
                        )
                    )
                        .font(isNew ? .headline.weight(.semibold) : .headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    RelativeTimeLabel(date: message.receivedAt)
                        .font(.caption)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(MessageMarkdownParser.summaryAttributedString(from: message.body))
                    .foregroundStyle(.secondary)
                    // Reserve identical summary height for short and long messages to avoid
                    // variable-height remeasurement when the native list appends a page.
                    .compatibleReservedTwoLineLimit()
                Text("\(message.sourceName) · \(MessageAbsoluteTimeFormat.listTime(message.receivedAt, locale: locale))")
                    // A slightly larger native text style keeps the full timestamp readable.
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A visible icon is loaded by Nuke's controlled disk pipeline; the fallback never invents a server image.
private struct GotifyApplicationIcon: View {
    let url: URL?
    let clientToken: String
    let size: CGFloat

    var body: some View {
        let request = authenticatedRequest
        Group {
            if let request, let cached = GotifyIconPipeline.pipeline.cache[request] {
                Image(nsImage: cached.image)
                    .resizable()
                    .scaledToFill()
            } else {
                LazyImage(request: request) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else if let request, let cached = GotifyIconPipeline.pipeline.cache[request] {
                        Image(nsImage: cached.image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "app.fill").foregroundStyle(.secondary)
                    }
                }
                .pipeline(GotifyIconPipeline.pipeline)
                .onDisappear(.lowerPriority)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Gotify serves custom application images behind the same client-token authorization as `/application`.
    private var authenticatedRequest: ImageRequest? {
        guard let url, !clientToken.isEmpty else { return nil }
        var request = URLRequest(url: url)
        request.setValue(clientToken, forHTTPHeaderField: "X-Gotify-Key")
        return ImageRequest(urlRequest: request)
    }
}

/// Detail stays inside the reading canvas so a long message never changes the two-column window geometry.
private struct MessageDetailView: View {
    let message: GotifyMessage
    let deleteMessage: () -> Void
    let dismiss: () -> Void
    @Environment(\.locale) private var locale
    @State private var isDeleteHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Keep navigation separate from message content: the full 48 pt header is the target,
            // so returning remains easy even when the message body is long or densely formatted.
            HStack(spacing: 12) {
                Button(action: dismiss) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.backward")
                            .font(.headline.weight(.semibold))
                        Text(Localized.string("message.detail.back"))
                            .font(.headline)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Localized.string("message.detail.back"))
                .accessibilityHint(Localized.string("message.detail.back.hint"))
                .accessibilityIdentifier("message-detail-back-button")

                Button(role: .destructive, action: deleteMessage) {
                    Label(Localized.string("message.delete"), systemImage: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isDeleteHovered ? Color.red : Color.secondary)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .onHover { hovering in
                    isDeleteHovered = hovering
                }
                .accessibilityIdentifier("message-detail-delete-button")
            }
            .padding(.horizontal, 24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(
                        MessageMarkdownParser.plainTextSummary(
                            from: message.title.isEmpty ? message.body : message.title
                        )
                    )
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    RelativeTimeLabel(date: message.receivedAt)
                        .font(.subheadline)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.sourceName)
                    Text(MessageAbsoluteTimeFormat.detailTime(message.receivedAt, locale: locale))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                Divider()

                MessageMarkdownView(text: message.body)
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
        .accessibilityIdentifier("message-detail")
    }
}

/// Unified empty/error placeholder matching native macOS empty-state typography across macOS 12+.
private struct EmptyStatePlaceholderView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
