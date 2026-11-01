import Collections
import Combine
import Foundation

/// A stable Gotify history identity. The all-feed and each application own independent cursors.
enum MessagePage: Hashable, Sendable {
    case all
    case application(Int64)

    /// A request captures this stable identity before suspension; UI selection may change later.
    var sourceID: Int64? {
        guard case let .application(id) = self else { return nil }
        return id
    }
}

enum MessagePageLoadState: Equatable, Sendable {
    case idle
    case loading(UUID)
    case loaded
    case failed
}

struct GotifyMessagePage: Sendable {
    let messages: [GotifyMessage]
    let next: String?
    let nextSince: Int64?
}

/// Main-actor adapter: SwiftUI reads immutable snapshots while the actor owns history mutation.
@MainActor
final class MessageStore: ObservableObject {
    private enum Configuration {
        /// The visible `999+` policy needs only a bounded set of row-level indicators.
        static let trackedNewMessagesPerSource = 1_000
    }

    private struct NewMessageState {
        var totalCount = 0
        var recentIDs = Set<Int64>()
        var recentOrder: Deque<Int64> = []

        mutating func insert(_ id: Int64) {
            guard recentIDs.insert(id).inserted else { return }
            totalCount += 1
            recentOrder.append(id)
            if recentOrder.count > Configuration.trackedNewMessagesPerSource,
               let expired = recentOrder.popFirst() {
                recentIDs.remove(expired)
            }
        }

        mutating func markViewed(_ id: Int64) -> Bool {
            guard recentIDs.remove(id) != nil else { return false }
            recentOrder.removeAll { $0 == id }
            totalCount -= 1
            return true
        }

        mutating func markAllViewed() {
            totalCount = 0
            recentIDs.removeAll(keepingCapacity: true)
            recentOrder.removeAll(keepingCapacity: true)
        }
    }

    /// The actor is the sole mutable owner of page cursors and payload lifetimes.
    private let pageStore: GotifyMessagePageStore
    /// Prevent an awaited snapshot from repopulating a store cleared for another server.
    private var sessionID: UUID
    @Published private var snapshots: [MessagePage: MessageTimelineSnapshot] = [:]
    private var applicationsByID: [Int64: GotifyApplication] = [:]
    @Published private var newMessagesBySource: [Int64: NewMessageState] = [:]
    @Published private var unexpandedMessagesBySource: [Int64: NewMessageState] = [:]
    @Published private(set) var connectionState: ConnectionState = .notConfigured
    @Published private(set) var sessionVersion = UUID()

    init() {
        let sessionID = UUID()
        self.sessionID = sessionID
        pageStore = GotifyMessagePageStore(sessionID: sessionID)
    }

    var messages: Deque<GotifyMessage> { Deque(messages(for: .all)) }
    var applications: [GotifyApplication] { applicationsByID.values.sorted { $0.name < $1.name } }
    var newMessageCount: Int { newMessagesBySource.values.reduce(0) { $0 + $1.totalCount } }
    var unexpandedMessageCount: Int { unexpandedMessagesBySource.values.reduce(0) { $0 + $1.totalCount } }

    func messages(for page: MessagePage) -> [GotifyMessage] { snapshots[page]?.messages ?? [] }
    func timelineItems(for page: MessagePage) -> [MessageTimelineItem] { snapshots[page]?.items ?? [] }
    func pageLoadState(for page: MessagePage) -> MessagePageLoadState { snapshots[page]?.loadState ?? .idle }
    func findMessage(id: Int64) async -> GotifyMessage? {
        for snapshot in snapshots.values {
            if let message = snapshot.messages.first(where: { $0.id == id }) {
                return message
            }
        }
        return await pageStore.findMessage(id: id)
    }
    func hasPendingLiveMessages(for page: MessagePage) -> Bool {
        snapshots[page]?.hasPendingLiveMessages ?? false
    }

    func hasNextPage(for page: MessagePage) -> Bool {
        snapshots[page]?.nextPageSince != nil
    }

    func scrollAnchorID(for page: MessagePage) -> Int64? {
        snapshots[page]?.scrollAnchorID
    }
    func newMessageCount(for sourceID: Int64) -> Int { newMessagesBySource[sourceID]?.totalCount ?? 0 }

    func newMessageCount(for page: MessagePage) -> Int {
        if case let .application(id) = page {
            return newMessageCount(for: id)
        }
        return newMessageCount
    }

    func unexpandedMessageCount(for sourceID: Int64) -> Int {
        unexpandedMessagesBySource[sourceID]?.totalCount ?? 0
    }

    func unexpandedMessageCount(for page: MessagePage) -> Int {
        if case let .application(id) = page {
            return unexpandedMessageCount(for: id)
        }
        return unexpandedMessageCount
    }

    func beginLoading(_ page: MessagePage) async -> UUID? {
        let expectedSessionID = sessionID
        let requestID = await pageStore.beginInitialLoad(for: page, sessionID: expectedSessionID)
        guard expectedSessionID == sessionID else { return nil }
        if requestID != nil { await publish(page) }
        return requestID
    }

    func finishLoading(_ page: MessagePage, requestID: UUID, result: GotifyMessagePage) async {
        let expectedSessionID = sessionID
        if await pageStore.finishInitialLoad(for: page, requestID: requestID, result: result), expectedSessionID == sessionID {
            markPageExpanded(for: page)
            await publish(page)
        }
    }

    func failLoading(_ page: MessagePage, requestID: UUID) async {
        if await pageStore.failInitialLoad(for: page, requestID: requestID) { await publish(page) }
    }

    func beginLoadingNextPage(_ page: MessagePage) async -> MessageHistoryRequest? {
        // The sentinel owns loading feedback. Claiming the actor's request gate changes no
        // renderable snapshot field, so publishing here would refresh all loaded rows for nothing.
        let expectedSessionID = sessionID
        let request = await pageStore.beginNextPageLoad(for: page, sessionID: expectedSessionID)
        return expectedSessionID == sessionID ? request : nil
    }

    @discardableResult
    func finishLoadingNextPage(_ request: MessageHistoryRequest, result: GotifyMessagePage) async -> Bool {
        guard request.sessionID == sessionID,
              await pageStore.finishNextPageLoad(request, result: result), request.sessionID == sessionID
        else { return false }
        await publish(request.page)
        return true
    }

    func failLoadingNextPage(_ request: MessageHistoryRequest) async {
        // The error returns to the sentinel's retry state; history and cursor remain unchanged.
        await pageStore.failNextPageLoad(request)
    }

    func beginLoadingMore(_ page: MessagePage, gapID: UUID) async -> MessageHistoryRequest? {
        let expectedSessionID = sessionID
        let request = await pageStore.beginGapLoad(for: page, gapID: gapID, sessionID: expectedSessionID)
        return expectedSessionID == sessionID ? request : nil
    }

    @discardableResult
    func finishLoadingMore(_ request: MessageHistoryRequest, result: GotifyMessagePage) async -> Bool {
        guard request.sessionID == sessionID,
              await pageStore.finishGapLoad(request, result: result), request.sessionID == sessionID
        else { return false }
        await publish(request.page)
        return true
    }

    func failLoadingMore(_ request: MessageHistoryRequest) async {
        await pageStore.failGapLoad(request)
    }

    func setMessageVisibility(_ messageID: Int64, visible: Bool, for page: MessagePage) async {
        await pageStore.setMessageVisibility(messageID, visible: visible, for: page)
    }

    func consumeScrollAnchor(_ anchorID: Int64, for page: MessagePage) async {
        if await pageStore.consumeScrollAnchor(anchorID, for: page) { await publish(page) }
    }

    func revealPendingLiveMessages(for page: MessagePage) async {
        markPageExpanded(for: page)
        let affected = await pageStore.revealPendingLiveMessages(for: page)
        for affectedPage in affected {
            await publish(affectedPage)
        }
    }

    func markPageExpanded(for page: MessagePage) {
        var unexpanded = unexpandedMessagesBySource
        switch page {
        case .all:
            for id in unexpanded.keys {
                unexpanded[id]?.markAllViewed()
            }
        case let .application(id):
            unexpanded[id]?.markAllViewed()
        }
        unexpandedMessagesBySource = unexpanded
    }

    func invalidate(_ page: MessagePage) async {
        await pageStore.invalidate(page)
        await publish(page)
    }

    func discardCurrentSession() async {
        sessionID = UUID()
        sessionVersion = sessionID
        await pageStore.discardSession(replacingSessionID: sessionID)
        snapshots.removeAll(keepingCapacity: true)
        applicationsByID.removeAll(keepingCapacity: true)
        newMessagesBySource.removeAll(keepingCapacity: true)
        unexpandedMessagesBySource.removeAll(keepingCapacity: true)
    }

    func replaceApplications(_ applications: [GotifyApplication]) {
        applicationsByID = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
    }

    func replaceCurrentSessionMessages(_ messages: [GotifyMessage]) async {
        await pageStore.replaceAllMessages(messages)
        await publish(.all)
    }

    func insertCurrentSessionMessage(_ message: GotifyMessage) async -> Bool {
        !(await insertCurrentSessionMessages([message])).isEmpty
    }

    func insertCurrentSessionMessages(_ messages: [GotifyMessage]) async -> [GotifyMessage] {
        let expectedSessionID = sessionID
        let inserted = await pageStore.insertLiveMessages(messages, sessionID: expectedSessionID)
        guard expectedSessionID == sessionID, !inserted.isEmpty else { return [] }
        // Commit attention once per WebSocket batch instead of invalidating the UI per message.
        var attentionBySource = newMessagesBySource
        var unexpandedBySource = unexpandedMessagesBySource
        for message in inserted {
            var attention = attentionBySource[message.sourceID] ?? NewMessageState()
            attention.insert(message.id)
            attentionBySource[message.sourceID] = attention

            var unexpanded = unexpandedBySource[message.sourceID] ?? NewMessageState()
            unexpanded.insert(message.id)
            unexpandedBySource[message.sourceID] = unexpanded
        }
        newMessagesBySource = attentionBySource
        unexpandedMessagesBySource = unexpandedBySource
        await publish(.all)
        for sourceID in Set(inserted.map(\.sourceID)) {
            await publish(.application(sourceID))
        }
        return inserted
    }

    func isNewMessage(_ messageID: Int64, sourceID: Int64) -> Bool {
        newMessagesBySource[sourceID]?.recentIDs.contains(messageID) ?? false
    }

    func markMessageViewed(_ messageID: Int64, sourceID: Int64) {
        if var unexpanded = unexpandedMessagesBySource[sourceID], unexpanded.markViewed(messageID) {
            unexpandedMessagesBySource[sourceID] = unexpanded
        }
        guard var state = newMessagesBySource[sourceID], state.markViewed(messageID) else { return }
        newMessagesBySource[sourceID] = state
    }

    func markAllMessagesViewed(for page: MessagePage) {
        markPageExpanded(for: page)
        var attentionBySource = newMessagesBySource
        switch page {
        case .all:
            for id in attentionBySource.keys {
                attentionBySource[id]?.markAllViewed()
            }
        case let .application(id):
            attentionBySource[id]?.markAllViewed()
        }
        newMessagesBySource = attentionBySource
    }

    func removeCurrentSessionMessage(id: Int64, sourceID: Int64) async {
        let expectedSessionID = sessionID
        markMessageViewed(id, sourceID: sourceID)
        let affected = await pageStore.removeMessage(id: id, sourceID: sourceID, sessionID: expectedSessionID)
        guard expectedSessionID == sessionID else { return }
        for page in affected {
            await publish(page)
        }
    }

    func removeCurrentSessionMessages(for page: MessagePage) async {
        let expectedSessionID = sessionID
        markAllMessagesViewed(for: page)
        let affected = await pageStore.removeAllMessages(for: page, sessionID: expectedSessionID)
        guard expectedSessionID == sessionID else { return }
        for affectedPage in affected {
            await publish(affectedPage)
        }
    }

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    private func publish(_ page: MessagePage) async {
        let expectedSessionID = sessionID
        let snapshot = await pageStore.snapshot(for: page)
        guard expectedSessionID == sessionID, snapshots[page] != snapshot else { return }
        snapshots[page] = snapshot
    }
    enum ConnectionState: Equatable {
        case notConfigured
        case connecting
        case connected
        case disconnected(reason: String)
    }
}
