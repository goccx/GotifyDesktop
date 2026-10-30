import Foundation

/// An in-memory replacement for the persistent timeline metadata used by richer clients.
/// The cursor is sufficient to ask Gotify for the released, older part of this one-way feed.
struct MessageTimelineGap: Hashable, Sendable, Identifiable {
    let id: UUID
    /// Gotify returns IDs below `since`; `through` is already rendered below the missing range.
    let since: Int64
    let through: Int64
}

/// One ordered runtime timeline: rendered messages and the gaps between loaded ranges.
enum MessageTimelineItem: Hashable, Sendable, Identifiable {
    case message(GotifyMessage)
    case gap(MessageTimelineGap)

    var id: String {
        switch self {
        case let .message(message): return "message-\(message.id)"
        case let .gap(gap): return "history-gap-\(gap.id.uuidString)"
        }
    }
}

/// Immutable projection for SwiftUI; no timeline metadata leaves process memory.
struct MessageTimelineSnapshot: Equatable, Sendable {
    let items: [MessageTimelineItem]
    let loadState: MessagePageLoadState
    let nextPageSince: Int64?
    let scrollAnchorID: Int64?
    let hasPendingLiveMessages: Bool

    var messages: [GotifyMessage] {
        items.compactMap { guard case let .message(message) = $0 else { return nil }; return message }
    }
}

/// Request identity belongs to the domain, not a view's lifetime. Old responses must not change
/// a new session, a newly claimed cursor, or a gap that was removed while the request was running.
struct MessageHistoryRequest: Equatable, Sendable {
    enum Target: Hashable, Sendable {
        case tail
        case gap(UUID)
    }

    let id: UUID
    let sessionID: UUID
    let page: MessagePage
    let since: Int64
    let target: Target
}

/// Owns the ephemeral equivalent of a timeline datasource.
///
/// The state deliberately follows the proven `items + visibleItems + scrollAnchor + safeOffset`
/// flow. Tail reclamation resumes the ordinary tail cursor, while bounded gaps are reserved for
/// missing ranges between two retained blocks. History readers receive a pending-message prompt
/// rather than insertion above the viewport. Every state value remains in process memory.
actor GotifyMessagePageStore {
    private enum Configuration {
        static let visibleSafetyOffset = 15
        /// Matches the agreed recent-message window; this bounds background live payloads,
        /// not REST page size or the amount of history a user can deliberately load.
        static let pendingLiveMessageLimit = 1_000
    }

    private struct TimelineState: Sendable {
        var items: [MessageTimelineItem] = []
        var loadState: MessagePageLoadState = .idle
        /// Tail pagination is deliberately separate from in-list history gaps.
        var nextPageSince: Int64?
        var tailRequest: MessageHistoryRequest?
        var gapRequests: [UUID: MessageHistoryRequest] = [:]
        var pendingLiveMessages: [GotifyMessage] = []
        /// A single ID records whether discarded live payloads lie above the retained REST head.
        var newestDroppedPendingMessageID: Int64?
        /// Appearance order mirrors the reference timeline model: newest visible item first.
        var visibleMessageIDs: [Int64] = []
        var scrollAnchorID: Int64?
    }

    private var timelines: [MessagePage: TimelineState] = [:]
    private var sessionID: UUID
    private var lastReceivedLiveMessageID: Int64 = -1

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func snapshot(for page: MessagePage) -> MessageTimelineSnapshot {
        let state = timelines[page] ?? TimelineState()
        return MessageTimelineSnapshot(
            items: state.items,
            loadState: state.loadState,
            nextPageSince: state.nextPageSince,
            scrollAnchorID: state.scrollAnchorID,
            hasPendingLiveMessages: !state.pendingLiveMessages.isEmpty
        )
    }

    func beginInitialLoad(for page: MessagePage, sessionID expectedSessionID: UUID) -> UUID? {
        guard expectedSessionID == sessionID else { return nil }
        var state = timelines[page] ?? TimelineState()
        guard state.loadState == .idle || state.loadState == .failed else { return nil }
        let requestID = UUID()
        state.loadState = .loading(requestID)
        timelines[page] = state
        return requestID
    }

    func finishInitialLoad(for page: MessagePage, requestID: UUID, result: GotifyMessagePage) -> Bool {
        guard var state = timelines[page], state.loadState == .loading(requestID) else { return false }
        state.items = orderedUniqueMessages(result.messages).map(MessageTimelineItem.message)
        state.nextPageSince = result.next == nil ? nil : result.nextSince
        integratePendingMessages(in: &state)
        state.loadState = .loaded
        timelines[page] = state
        return true
    }

    func failInitialLoad(for page: MessagePage, requestID: UUID) -> Bool {
        guard var state = timelines[page], state.loadState == .loading(requestID) else { return false }
        state.loadState = .failed
        timelines[page] = state
        return true
    }

    /// Claims the independent tail cursor used by the automatic list sentinel.
    func beginNextPageLoad(for page: MessagePage, sessionID expectedSessionID: UUID) -> MessageHistoryRequest? {
        guard expectedSessionID == sessionID else { return nil }
        guard var state = timelines[page],
              state.loadState == .loaded,
              state.tailRequest == nil,
              let since = state.nextPageSince
        else { return nil }
        let request = MessageHistoryRequest(id: UUID(), sessionID: sessionID, page: page, since: since, target: .tail)
        state.tailRequest = request
        timelines[page] = state
        return request
    }

    /// Appends the next REST page. Unlike a gap load, this is intentionally a tail operation.
    func finishNextPageLoad(_ request: MessageHistoryRequest, result: GotifyMessagePage) -> Bool {
        guard request.sessionID == sessionID,
              var state = timelines[request.page], state.tailRequest == request
        else { return false }
        let knownIDs = Set(state.items.compactMap(\.messageID))
        let appended = orderedUniqueMessages(result.messages).filter { !knownIDs.contains($0.id) }
        state.items.append(contentsOf: appended.map(MessageTimelineItem.message))
        state.nextPageSince = result.next == nil ? nil : result.nextSince
        state.tailRequest = nil
        timelines[request.page] = state
        return true
    }

    func failNextPageLoad(_ request: MessageHistoryRequest) {
        guard request.sessionID == sessionID,
              var state = timelines[request.page], state.tailRequest == request
        else { return }
        state.tailRequest = nil
        timelines[request.page] = state
    }

    /// Claims a concrete gap; its cursor is never inferred from the scrollbar.
    func beginGapLoad(for page: MessagePage, gapID: UUID, sessionID expectedSessionID: UUID) -> MessageHistoryRequest? {
        guard expectedSessionID == sessionID else { return nil }
        guard var state = timelines[page],
              state.loadState == .loaded,
              state.gapRequests[gapID] == nil,
              let gap = gap(with: gapID, in: state.items)
        else { return nil }
        let request = MessageHistoryRequest(id: UUID(), sessionID: sessionID, page: page, since: gap.since, target: .gap(gapID))
        state.gapRequests[gapID] = request
        timelines[page] = state
        return request
    }

    /// Replaces precisely the requested gap with its response and the response's next gap.
    func finishGapLoad(_ request: MessageHistoryRequest, result: GotifyMessagePage) -> Bool {
        guard request.sessionID == sessionID,
              case let .gap(gapID) = request.target,
              var state = timelines[request.page],
              state.gapRequests[gapID] == request,
              let gapIndex = gapIndex(with: gapID, in: state.items)
        else { return false }
        guard case let .gap(gap) = state.items[gapIndex] else { return false }
        let knownIDs = Set(state.items.compactMap(\.messageID))
        var replacement = orderedUniqueMessages(result.messages)
            .filter { $0.id < request.since && $0.id > gap.through && !knownIDs.contains($0.id) }
            .map(MessageTimelineItem.message)
        // REST can cross the lower boundary of this gap. Such messages already belong to the
        // following block and must neither be inserted again nor generate an unbounded next gap.
        if !result.messages.contains(where: { $0.id <= gap.through }),
           result.next != nil, let nextSince = result.nextSince, nextSince > gap.through {
            replacement.append(.gap(MessageTimelineGap(id: UUID(), since: nextSince, through: gap.through)))
        }
        state.items.replaceSubrange(gapIndex ... gapIndex, with: replacement)
        state.gapRequests.removeValue(forKey: gapID)
        timelines[request.page] = state
        return true
    }

    func failGapLoad(_ request: MessageHistoryRequest) {
        guard request.sessionID == sessionID,
              case let .gap(gapID) = request.target,
              var state = timelines[request.page], state.gapRequests[gapID] == request
        else { return }
        state.gapRequests.removeValue(forKey: gapID)
        timelines[request.page] = state
    }

    /// Updates the ordered visible window reported by `List`, matching appearance/disappearance.
    func setMessageVisibility(_ messageID: Int64, visible: Bool, for page: MessagePage) {
        guard var state = timelines[page] else { return }
        state.visibleMessageIDs.removeAll { $0 == messageID }
        if visible { state.visibleMessageIDs.insert(messageID, at: 0) }
        timelines[page] = state
    }

    func consumeScrollAnchor(_ anchorID: Int64, for page: MessagePage) -> Bool {
        guard var state = timelines[page], state.scrollAnchorID == anchorID else { return false }
        state.scrollAnchorID = nil
        timelines[page] = state
        return true
    }

    func invalidate(_ page: MessagePage) {
        guard timelines[page] != nil else { return }
        timelines[page] = TimelineState()
    }

    func discardSession(replacingSessionID newSessionID: UUID) {
        sessionID = newSessionID
        timelines.removeAll(keepingCapacity: true)
        lastReceivedLiveMessageID = -1
    }

    func replaceAllMessages(_ messages: [GotifyMessage]) {
        timelines[.all] = TimelineState(items: messages.map(MessageTimelineItem.message), loadState: .loaded)
    }

    func insertLiveMessages(_ messages: [GotifyMessage], sessionID expectedSessionID: UUID) -> [GotifyMessage] {
        guard expectedSessionID == sessionID else { return [] }
        // A batched delivery may contain frames out of order; advance the monotonic watermark
        // in ID order rather than dropping an earlier ID merely because its frame came second.
        let unique = messages.sorted { $0.id < $1.id }.filter { message in
            guard message.id > lastReceivedLiveMessageID else { return false }
            lastReceivedLiveMessageID = message.id
            return true
        }
        guard !unique.isEmpty else { return [] }
        let bySource = Dictionary(grouping: unique) { $0.sourceID }
        for (sourceID, sourceMessages) in bySource { insertLive(sourceMessages, into: .application(sourceID)) }
        insertLive(unique, into: .all)
        return unique
    }

    /// Reading history is stable: live arrivals update bounded pending payloads and independent
    /// attention counts, but cannot insert rows above a reader or an in-flight history footer.
    private func insertLive(_ incoming: [GotifyMessage], into page: MessagePage) {
        guard var state = timelines[page] else {
            guard page == .all else { return }
            let ordered = orderedUniqueMessages(incoming)
            let retained = Array(ordered.prefix(Configuration.pendingLiveMessageLimit))
            timelines[page] = TimelineState(
                items: retained.map(MessageTimelineItem.message),
                loadState: .loaded,
                nextPageSince: ordered.count > retained.count ? retained.last?.id : nil
            )
            return
        }
        queuePendingMessages(incoming, in: &state)
        let priorTopID = state.items.compactMap(\.messageID).first
        if state.loadState == .loaded,
           state.tailRequest == nil, state.gapRequests.isEmpty,
           let priorTopID, state.visibleMessageIDs.contains(priorTopID) {
            integratePendingMessages(in: &state)
            state.scrollAnchorID = priorTopID
            releaseTail(afterLastVisibleItemIn: &state)
        }
        timelines[page] = state
    }

    /// Explicit navigation to latest content is the only history-reading action that may move
    /// the viewport. It does not mark any message viewed or change source attention counters.
    func revealPendingLiveMessages(for page: MessagePage) -> Bool {
        guard var state = timelines[page], state.loadState == .loaded else { return false }
        if !state.pendingLiveMessages.isEmpty {
            state.tailRequest = nil
            state.gapRequests.removeAll(keepingCapacity: true)
            integratePendingMessages(in: &state)
        }
        guard !state.items.isEmpty else { return false }
        state.scrollAnchorID = state.items.compactMap(\.messageID).first
        timelines[page] = state
        return true
    }

    private func queuePendingMessages(_ incoming: [GotifyMessage], in state: inout TimelineState) {
        let messages = orderedUniqueMessages(incoming + state.pendingLiveMessages)
        if messages.count > Configuration.pendingLiveMessageLimit {
            let droppedID = messages[Configuration.pendingLiveMessageLimit].id
            state.newestDroppedPendingMessageID = max(state.newestDroppedPendingMessageID ?? droppedID, droppedID)
        }
        state.pendingLiveMessages = Array(messages.prefix(Configuration.pendingLiveMessageLimit))
    }

    /// Only overflow creates a middle gap. Released tail history keeps the ordinary tail cursor.
    private func integratePendingMessages(in state: inout TimelineState) {
        let knownIDs = Set(state.items.compactMap(\.messageID))
        let oldTopID = state.items.compactMap(\.messageID).first
        // A fresh REST response can already be newer than the buffered stream frames. Older
        // buffered messages are history, not a new prefix to insert ahead of the REST head.
        let messages = state.pendingLiveMessages.filter { message in
            !knownIDs.contains(message.id) && (oldTopID.map { message.id > $0 } ?? true)
        }
        var prefix = messages.map(MessageTimelineItem.message)
        if let droppedID = state.newestDroppedPendingMessageID, let oldTopID, droppedID > oldTopID,
           let oldestNewID = messages.last?.id {
            prefix.append(.gap(MessageTimelineGap(id: UUID(), since: oldestNewID, through: oldTopID)))
        }
        state.items.insert(contentsOf: prefix, at: 0)
        state.pendingLiveMessages.removeAll(keepingCapacity: true)
        state.newestDroppedPendingMessageID = nil
    }

    private func releaseTail(afterLastVisibleItemIn state: inout TimelineState) {
        let visibleIDs = Set(state.visibleMessageIDs)
        guard let visibleIndex = state.items.lastIndex(where: { item in
            item.messageID.map(visibleIDs.contains) ?? false
        })
        else { return }
        let releaseIndex = visibleIndex + Configuration.visibleSafetyOffset
        guard releaseIndex < state.items.endIndex else { return }
        state.items.removeSubrange(releaseIndex...)
        if case let .gap(gap)? = state.items.last {
            // With no following retained block this is tail history, not a bounded middle gap.
            state.items.removeLast()
            state.nextPageSince = gap.since
        } else {
            state.nextPageSince = state.items.compactMap(\.messageID).last
        }
        state.tailRequest = nil
        let retainedIDs = Set(state.items.compactMap(\.messageID))
        state.visibleMessageIDs.removeAll { !retainedIDs.contains($0) }
        state.gapRequests = state.gapRequests.filter { gapIndex(with: $0.key, in: state.items) != nil }
    }

    private func gap(with id: UUID, in items: [MessageTimelineItem]) -> MessageTimelineGap? {
        guard let index = gapIndex(with: id, in: items), case let .gap(gap) = items[index] else { return nil }
        return gap
    }

    private func gapIndex(with id: UUID, in items: [MessageTimelineItem]) -> Int? {
        items.firstIndex { if case let .gap(gap) = $0 { return gap.id == id }; return false }
    }

    private func orderedUniqueMessages(_ messages: [GotifyMessage]) -> [GotifyMessage] {
        Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { newer, _ in newer }).values.sorted {
            $0.receivedAt == $1.receivedAt ? $0.id > $1.id : $0.receivedAt > $1.receivedAt
        }
    }
}

private extension MessageTimelineItem {
    var messageID: Int64? {
        guard case let .message(message) = self else { return nil }
        return message.id
    }
}
