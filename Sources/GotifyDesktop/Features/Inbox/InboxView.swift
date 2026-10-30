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
    @State private var selection: SidebarSelection? = .allMessages

    var body: some View {
        // Async callbacks keep the page that rendered them; a later selection cannot retarget
        // an old footer or disappearance callback to another application.
        let page = selectedPage
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                sources: sourceItems,
                newMessageCount: messageStore.newMessageCount,
                newMessageCountsBySource: newMessageCountsBySource,
                clientToken: serverPreferences.clientToken
            )
                // A navigation column needs enough breathing room for real application names and
                // the transient count. The bounded range keeps the reading canvas dominant.
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 260)
        } detail: {
            ReadingCanvas(
                timelineItems: messageStore.timelineItems(for: page),
                page: page,
                navigationTitle: navigationTitle,
                pageLoadState: messageStore.pageLoadState(for: page),
                hasNextPage: messageStore.hasNextPage(for: page),
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
                consumeScrollAnchor: { id in consumeScrollAnchor(id, for: page) }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConnectionStatusLabel(state: messageStore.connectionState, language: preferences.language)
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
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
        }
        .onChange(of: preferences.language) { _, _ in
            ApplicationMenuLocalization.apply(appName: Localized.string("app.name"))
        }
        .onChange(of: selection) { _, _ in
            loadSelectedPage()
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

    var body: some View {
        List(selection: $selection) {
            NavigationSidebarRow(
                title: Localized.string("sidebar.allMessages"),
                systemImage: "tray.full",
                count: newMessageCount,
                isSelected: selection == .allMessages
            )
            .tag(SidebarSelection.allMessages)
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(SidebarSelectionBackground(isSelected: selection == .allMessages))
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
                .tag(item)
                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                .listRowBackground(SidebarSelectionBackground(isSelected: selection == item))
                .accessibilityIdentifier("source-sidebar-item-\(source.id)")
            }
        }
        .listStyle(.sidebar)
        // SwiftUI does not expose NSTableView.selectionHighlightStyle. This mature adapter uses
        // public AppKit introspection only; native selection, scrolling, keyboard navigation, and
        // accessibility remain owned by the table view.
        .introspect(.list(style: .sidebar), on: .macOS(.v14, .v15, .v26)) { tableView in
            tableView.selectionHighlightStyle = .none
            tableView.usesAlternatingRowBackgroundColors = false
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
    @State private var selectedMessage: GotifyMessage?
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
                        ContentUnavailableView(
                            Localized.string("inbox.loadFailed.title"),
                            systemImage: "exclamationmark.icloud",
                            description: Text(Localized.string("inbox.loadFailed.description"))
                        )
                        Button(Localized.string("inbox.retry"), action: retryLoading)
                            .accessibilityIdentifier("retry-message-page-button")
                    }
                case .idle, .loaded:
                    if timelineItems.isEmpty {
                        ContentUnavailableView(
                            Localized.string("inbox.empty.title"),
                            systemImage: "bell.badge",
                            description: Text(Localized.string("inbox.empty.description"))
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
                            consumeScrollAnchor: consumeScrollAnchor
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
                MessageDetailView(message: selectedMessage) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        self.selectedMessage = nil
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: page) { _, _ in
            selectedMessage = nil
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
    let selectMessage: (GotifyMessage) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // `List` virtualizes rows. A gap loads only when it enters the visible range.
                ForEach(timelineItems) { item in
                    MessageTimelineListRow(
                        item: item,
                        isNewMessage: isNewMessage,
                        clientToken: clientToken,
                        locale: locale,
                        isPresented: isPresented,
                        selectMessage: selectMessage,
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
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .accessibilityIdentifier("message-timeline-list")
            // Only live insertion at the head or explicit "show new" sets an anchor.
            // Completing a tail page or a gap never sends a scroll instruction.
            .onChange(of: scrollAnchorID) { _, anchorID in
                guard let anchorID else { return }
                if isPresented { proxy.scrollTo("message-\(anchorID)", anchor: .top) }
                consumeScrollAnchor(anchorID)
            }
        }
        // An overlay contributes no height to the List. Showing/clearing attention therefore
        // changes neither the viewport bounds nor any existing row's layout or identity.
        .overlay(alignment: .bottomTrailing) {
            if isPresented && (newMessageCount > 0 || hasPendingLiveMessages) {
                newMessagesPrompt
                    .padding()
            }
        }
    }

    /// Compact native-material controls appear only when useful; no invisible header is reserved.
    private var newMessagesPrompt: some View {
        HStack {
            Text(newMessageHeader)
                .foregroundStyle(.secondary)
            Button(Localized.string("message.showNewMessages")) {
                Task { await revealPendingLiveMessages() }
            }
            .accessibilityIdentifier("show-new-messages-button")
            Button(Localized.string("message.markAllViewed"), action: markAllMessagesViewed)
                .disabled(newMessageCount == 0)
                .accessibilityIdentifier("mark-all-messages-viewed-button")
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
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
    let isNewMessage: (GotifyMessage) -> Bool
    let clientToken: String
    let locale: Locale
    let isPresented: Bool
    let selectMessage: (GotifyMessage) -> Void
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
                    select: selectMessage
                )
                .onAppear { setMessageVisibility(message.id, isPresented) }
                .onDisappear { setMessageVisibility(message.id, false) }
                .onChange(of: isPresented) { _, presented in setMessageVisibility(message.id, presented) }
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

    var body: some View {
        Button { select(message) } label: {
            // Only values participate in presentation equality. The button action stays current,
            // while unchanged old image/timestamp content skips parent-driven body recomputation.
            MessageRowContent(message: message, isNew: isNew, clientToken: clientToken, locale: locale)
                .equatable()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("message-row-\(message.id)")
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
                    Text(message.title.isEmpty ? message.body : message.title)
                        .font(isNew ? .headline.weight(.semibold) : .headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    RelativeTimeLabel(date: message.receivedAt)
                        .font(.caption)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(message.body)
                    .foregroundStyle(.secondary)
                    // Reserve identical summary height for short and long messages to avoid
                    // variable-height remeasurement when the native list appends a page.
                    .lineLimit(2, reservesSpace: true)
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
        LazyImage(request: authenticatedRequest) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "app.fill").foregroundStyle(.secondary)
            }
        }
        .pipeline(GotifyIconPipeline.pipeline)
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
    let dismiss: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            // Keep navigation separate from message content: the full 48 pt header is the target,
            // so returning remains easy even when the message body is long or densely formatted.
            Button(action: dismiss) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.backward")
                        .font(.headline.weight(.semibold))
                    Text(Localized.string("message.detail.back"))
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localized.string("message.detail.back"))
            .accessibilityHint(Localized.string("message.detail.back.hint"))
            .accessibilityIdentifier("message-detail-back-button")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(message.title.isEmpty ? message.body : message.title)
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

                Text(message.body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
        .accessibilityIdentifier("message-detail")
    }
}
