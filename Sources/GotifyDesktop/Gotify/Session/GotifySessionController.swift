import Foundation
import GotifyGeneratedClient

/// Coordinates one in-memory Gotify session: REST establishes a consistent starting point, then WebSocket adds new messages.
@MainActor
final class GotifySessionController {
    private enum Configuration {
        /// Matches the official Gotify Android client's first-page request size.
        static let pageLimit = 100
        /// Match Android's restrained reconnect cadence while retaining just one cancellable task.
        static let reconnectInitialDelaySeconds: UInt64 = 5
        static let reconnectMaximumDelaySeconds: UInt64 = 20 * 60
        /// Bound main-actor UI invalidations during a busy stream without adding durable queues or timers.
        static let liveMessageBatchSize = 100
        static let liveMessageBatchDelay: Duration = .milliseconds(100)
    }

    /// The token exists only for this active in-memory session and is never copied into reconnect task storage.
    private struct ActiveSession {
        let id = UUID()
        let serverURL: URL
        let clientToken: String
    }

    private let messageStore: MessageStore
    /// Notification delivery is injected so the session owns no AppKit or UserNotifications details.
    private weak var notifier: (any GotifyMessageNotifying)?
    private var stream: (any GotifyWebSocketEventSource)?
    private var applications: [Int64: GotifyApplication] = [:]
    private var activeSession: ActiveSession?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    /// A manual page retry may wake reconnection early, but it must not overlap the in-flight connection attempt.
    private var reconnectAttemptSessionID: UUID?
    private var visiblePage: MessagePage = .all
    private var liveMessageBuffer: GotifyLiveMessageBuffer?

    init(messageStore: MessageStore, notifier: (any GotifyMessageNotifying)? = nil) {
        self.messageStore = messageStore
        self.notifier = notifier
    }

    func start(serverURL: URL, clientToken: String) async throws {
        await stopSession(clearMessages: false, state: .connecting)
        let session = ActiveSession(serverURL: serverURL, clientToken: clientToken)
        activeSession = session
        let sessionID = session.id
        liveMessageBuffer = GotifyLiveMessageBuffer(
            batchSize: Configuration.liveMessageBatchSize,
            flushDelay: Configuration.liveMessageBatchDelay
        ) { [weak self] messages in
            await self?.receiveLiveMessageBatch(messages, for: sessionID)
        }
        messageStore.setConnectionState(.connecting)
        // Claim the first page before starting the stream, so early frames join its pending
        // buffer instead of accidentally making REST think the first page is already loaded.
        let initialRequestID = await messageStore.beginLoading(.all)

        do {
            try await connect(session)
            await loadMessages(page: .all, client: try currentClient(for: session), requestID: initialRequestID)
        } catch {
            // Initial validation must finish in a terminal state, never leave Settings at "connecting".
            guard isActive(session) else { throw error }
            if let initialRequestID { await messageStore.failLoading(.all, requestID: initialRequestID) }
            await stopSession(clearMessages: false, state: .disconnected(reason: ""))
            messageStore.setConnectionState(.disconnected(reason: ""))
            throw error
        }
    }

    /// Page loading is independent from the one global WebSocket: loaded pages reuse memory, idle pages fetch once.
    func loadMessages(for sourceID: Int64?) async {
        visiblePage = sourceID.map(MessagePage.application) ?? .all
        if let restClient = currentRESTClient {
            await loadMessages(page: visiblePage, client: restClient)
            return
        }

        // The retry button is useful even while offline: it promotes the existing delayed reconnect now.
        guard let activeSession, reconnectAttemptSessionID == nil else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnect(sessionID: activeSession.id)
    }

    /// A bounded middle gap is restored in place; it shares the footer's async/error contract.
    func loadMoreMessages(for sourceID: Int64?, gapID: UUID) async throws {
        let page = sourceID.map(MessagePage.application) ?? .all
        guard let session = activeSession else { throw CancellationError() }
        guard let client = currentRESTClient else { throw URLError(.notConnectedToInternet) }
        guard let request = await messageStore.beginLoadingMore(page, gapID: gapID) else { throw CancellationError() }
        try await fetchHistory(request, client: client, session: session,
                               complete: messageStore.finishLoadingMore, fail: messageStore.failLoadingMore)
    }

    /// The terminal sentinel appends Gotify's next page without changing the current list viewport.
    func loadNextPage(for sourceID: Int64?) async throws {
        let page = sourceID.map(MessagePage.application) ?? .all
        guard let session = activeSession else { throw CancellationError() }
        guard let client = currentRESTClient else { throw URLError(.notConnectedToInternet) }
        guard let request = await messageStore.beginLoadingNextPage(page) else { throw CancellationError() }
        try await fetchHistory(request, client: client, session: session,
                               complete: messageStore.finishLoadingNextPage, fail: messageStore.failLoadingNextPage)
    }

    /// Both pagination targets use the same transport lifecycle. Page/cursor are captured in the
    /// claim, and a cancelled or replaced session cannot complete a request into another timeline.
    private func fetchHistory(
        _ request: MessageHistoryRequest,
        client: GeneratedGotifyRESTClient,
        session: ActiveSession,
        complete: (MessageHistoryRequest, GotifyMessagePage) async -> Bool,
        fail: (MessageHistoryRequest) async -> Void
    ) async throws {
        do {
            try Task.checkCancellation()
            guard isActive(session) else { throw CancellationError() }
            let result = try await client.fetchMessages(
                page: request.page,
                limit: Configuration.pageLimit,
                since: request.since,
                applications: applications
            )
            try Task.checkCancellation()
            guard isActive(session), await complete(request, result) else { throw CancellationError() }
        } catch {
            await fail(request)
            throw error
        }
    }

    func stop(clearMessages: Bool) async {
        await stopSession(clearMessages: clearMessages, state: .disconnected(reason: ""))
    }

    private func stopSession(clearMessages: Bool, state: MessageStore.ConnectionState) async {
        activeSession = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        reconnectAttemptSessionID = nil
        if let liveMessageBuffer {
            Task { await liveMessageBuffer.discard() }
        }
        liveMessageBuffer = nil
        stream?.disconnect()
        stream = nil
        currentRESTClient = nil
        messageStore.setConnectionState(state)
        if clearMessages { await messageStore.discardCurrentSession() }
    }

    /// Runs only when an established Starscream stream ends without an explicit Settings/user stop.
    private func streamEndedUnexpectedly(for sessionID: UUID) {
        guard activeSession?.id == sessionID else { return }
        stream = nil
        currentRESTClient = nil
        messageStore.setConnectionState(.disconnected(reason: ""))
        scheduleReconnect(for: sessionID)
    }

    /// One task owns all retry timing. Closing receiving cancels it before its next wake-up.
    private func scheduleReconnect(for sessionID: UUID) {
        guard reconnectTask == nil, activeSession?.id == sessionID else { return }
        let delay = reconnectDelay(forAttempt: reconnectAttempt)
        reconnectAttempt += 1
        reconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.reconnect(sessionID: sessionID)
        }
    }

    private func reconnect(sessionID: UUID) {
        reconnectTask = nil
        guard reconnectAttemptSessionID == nil,
              let session = activeSession,
              session.id == sessionID
        else { return }
        reconnectAttemptSessionID = session.id
        messageStore.setConnectionState(.connecting)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // An earlier session finishing after a server switch must not unlock a newer attempt.
                if self.reconnectAttemptSessionID == session.id {
                    self.reconnectAttemptSessionID = nil
                }
            }
            do {
                try await self.connect(session)
                guard self.isActive(session) else { return }
                await self.messageStore.invalidate(self.visiblePage)
                await self.loadMessages(page: self.visiblePage, client: try self.currentClient(for: session))
            } catch {
                guard self.isActive(session) else { return }
                self.stream = nil
                self.currentRESTClient = nil
                self.messageStore.setConnectionState(.disconnected(reason: ""))
                self.scheduleReconnect(for: sessionID)
            }
        }
    }

    /// A buffer consumes frames off-main and hands the main actor only a bounded ready-to-render group.
    private func receiveLiveMessageBatch(_ incomingMessages: [Message], for sessionID: UUID) async {
        guard activeSession?.id == sessionID else { return }
        guard !incomingMessages.isEmpty else { return }

        let liveMessages = incomingMessages.map { message in
            GotifyMessage(
                id: message.id,
                title: message.title ?? "",
                body: message.message,
                sourceID: message.appid,
                sourceName: applications[message.appid]?.name ?? String(message.appid),
                sourceIconURL: applications[message.appid]?.iconURL,
                priority: Int(message.priority ?? 0),
                receivedAt: message.date,
                url: nil
            )
        }
        // REST snapshots never enter this path; only distinct live WebSocket messages produce notifications.
        (await messageStore.insertCurrentSessionMessages(liveMessages)).forEach { notifier?.notifyAboutLiveMessage($0) }
    }

    /// Retained only for page requests in this process; it never serializes its token.
    private var currentRESTClient: GeneratedGotifyRESTClient?

    /// REST and WebSocket are rebuilt together so a reconnection never uses a stale session's token or endpoint.
    private func connect(_ session: ActiveSession) async throws {
        let restClient = GeneratedGotifyRESTClient(serverURL: session.serverURL, clientToken: session.clientToken)
        let loadedApplications = try await restClient.fetchApplications()
        guard isActive(session) else { throw CancellationError() }

        applications = Dictionary(uniqueKeysWithValues: loadedApplications.map { ($0.id, $0) })
        messageStore.replaceApplications(loadedApplications)
        currentRESTClient = restClient
        guard let liveMessageBuffer else { throw CancellationError() }

        let newStream = StarscreamGotifyWebSocketEventSource(
            serverURL: session.serverURL,
            clientToken: session.clientToken,
            onMessage: { message in
                Task { await liveMessageBuffer.append(message) }
            },
            onUnexpectedDisconnection: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.streamEndedUnexpectedly(for: session.id)
                }
            }
        )
        stream = newStream
        try await newStream.connect()
        guard isActive(session), stream != nil else { throw CancellationError() }
        reconnectAttempt = 0
        messageStore.setConnectionState(.connected)
    }

    private func currentClient(for session: ActiveSession) throws -> GeneratedGotifyRESTClient {
        guard isActive(session), let currentRESTClient else { throw CancellationError() }
        return currentRESTClient
    }

    private func isActive(_ session: ActiveSession) -> Bool {
        activeSession?.id == session.id
    }

    private func reconnectDelay(forAttempt attempt: Int) -> UInt64 {
        let multiplier = UInt64(1) << min(attempt, 63)
        return min(Configuration.reconnectInitialDelaySeconds.multipliedReportingOverflow(by: multiplier).partialValue, Configuration.reconnectMaximumDelaySeconds)
    }

    private func loadMessages(page: MessagePage, client: GeneratedGotifyRESTClient, requestID: UUID? = nil) async {
        let claimedID: UUID?
        if let requestID { claimedID = requestID } else { claimedID = await messageStore.beginLoading(page) }
        guard let claimedID else { return }
        do {
            let result = try await client.fetchMessages(
                page: page,
                limit: Configuration.pageLimit,
                since: nil,
                applications: applications
            )
            await messageStore.finishLoading(page, requestID: claimedID, result: result)
        } catch {
            await messageStore.failLoading(page, requestID: claimedID)
        }
    }
}
