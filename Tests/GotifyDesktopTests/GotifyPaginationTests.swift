import Combine
import Foundation
import Testing
@testable import GotifyDesktop

/// Exercises real session state under pagination/live-response races, without a mock datasource.
/// Layout is still owned by SwiftUI; these tests verify its unchanged-prefix/no-scroll contract.
@MainActor
struct GotifyPaginationTests {
    @Test
    func aQueuedOldSessionClaimCannotCreateLoadingStateAfterSessionReplacement() async throws {
        let oldSessionID = UUID()
        let newSessionID = UUID()
        let datasource = GotifyMessagePageStore(sessionID: oldSessionID)
        await datasource.discardSession(replacingSessionID: newSessionID)
        #expect(await datasource.beginInitialLoad(for: .all, sessionID: oldSessionID) == nil)
        #expect(await datasource.snapshot(for: .all).loadState == .idle)
        let requestID = try #require(await datasource.beginInitialLoad(for: .all, sessionID: newSessionID))
        #expect(await datasource.finishInitialLoad(for: .all, requestID: requestID, result: history([message(10)])))
    }

    @Test
    func anOldLiveBatchCannotPopulateTheNewServersTimeline() async {
        let oldSessionID = UUID()
        let newSessionID = UUID()
        let datasource = GotifyMessagePageStore(sessionID: oldSessionID)
        await datasource.discardSession(replacingSessionID: newSessionID)
        #expect(await datasource.insertLiveMessages([message(3)], sessionID: oldSessionID).isEmpty)
        #expect(await datasource.snapshot(for: .all).items.isEmpty)
        #expect(await datasource.insertLiveMessages([message(10)], sessionID: newSessionID).map(\.id) == [10])
    }

    @Test
    func aNewerRESTHeadCannotBePrefixedWithOlderBufferedFrames() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        let requestID = try #require(await store.beginLoading(page))
        _ = await store.insertCurrentSessionMessages(messages(21...1_121))
        let serverMessages = messages(1_101...1_200)
        await store.finishLoading(page, requestID: requestID, result: history(serverMessages, nextSince: 1_101))
        #expect(store.messages(for: page) == serverMessages)
        #expect(gaps(in: store.timelineItems(for: page)).isEmpty)
        #expect(!store.hasPendingLiveMessages(for: page))
        #expect(store.newMessageCount(for: 7) == 1_101)
    }

    @Test
    func bufferedOverflowAlreadyCoveredByRESTDoesNotCreateAnUnnecessaryGap() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        let requestID = try #require(await store.beginLoading(page))
        _ = await store.insertCurrentSessionMessages(messages(21...1_221))
        await store.finishLoading(page, requestID: requestID, result: history(messages(122...221), nextSince: 122))
        #expect(store.messages(for: page).map(\.id) == (122...1_221).reversed().map(Int64.init))
        #expect(gaps(in: store.timelineItems(for: page)).isEmpty)
        let request = try #require(await store.beginLoadingNextPage(page))
        #expect(request.since == 122)
    }

    @Test
    func aLiveArrivalDuringTailLoadingLeavesPreviouslyRenderedRowsUntouched() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        let initial = messages(101...200)
        try await load(initial, into: page, store: store, nextSince: 101)
        await store.setMessageVisibility(109, visible: true, for: page)
        let oldItems = store.timelineItems(for: page)
        let request = try #require(await store.beginLoadingNextPage(page))

        #expect(await store.insertCurrentSessionMessage(message(201)))
        #expect(store.timelineItems(for: page) == oldItems)
        #expect(store.scrollAnchorID(for: page) == nil)
        #expect(store.hasPendingLiveMessages(for: page))
        #expect(store.newMessageCount(for: 7) == 1)
        #expect(await store.finishLoadingNextPage(request, result: history(messages(1...100))))
        #expect(Array(store.timelineItems(for: page).prefix(oldItems.count)) == oldItems)
        #expect(store.scrollAnchorID(for: page) == nil)

        await store.revealPendingLiveMessages(for: page)
        #expect(store.messages(for: page).first?.id == 201)
        #expect(store.scrollAnchorID(for: page) == 201)
        #expect(store.newMessageCount(for: 7) == 1)
    }

    @Test
    func evenAtTheHeadAnInFlightHistoryRequestDefersLiveInsertion() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load(messages(101...200), into: page, store: store, nextSince: 101)
        await store.setMessageVisibility(200, visible: true, for: page)
        let oldItems = store.timelineItems(for: page)
        let request = try #require(await store.beginLoadingNextPage(page))

        _ = await store.insertCurrentSessionMessage(message(201))
        #expect(store.timelineItems(for: page) == oldItems)
        #expect(await store.finishLoadingNextPage(request, result: history(messages(1...100))))
        #expect(Array(store.timelineItems(for: page).prefix(oldItems.count)) == oldItems)
        #expect(store.scrollAnchorID(for: page) == nil)
    }

    @Test
    func anOldResponseOrFailureCannotCompleteOrUnlockANewerTailRequest() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load([message(200)], into: page, store: store, nextSince: 200)
        let oldRequest = try #require(await store.beginLoadingNextPage(page))
        await store.failLoadingNextPage(oldRequest)
        let newRequest = try #require(await store.beginLoadingNextPage(page))
        var invalidations = 0
        let observation = store.objectWillChange.sink { invalidations += 1 }
        defer { observation.cancel() }

        #expect(await !store.finishLoadingNextPage(oldRequest, result: history([message(199)])))
        await store.failLoadingNextPage(oldRequest)
        #expect(invalidations == 0)
        #expect(await store.beginLoadingNextPage(page) == nil)
        #expect(await store.finishLoadingNextPage(newRequest, result: history([message(198)])))
        #expect(store.messages(for: page).map(\.id) == [200, 198])
        #expect(invalidations == 1)
    }

    @Test
    func simultaneousFooterAppearancesClaimOnlyOneRESTPage() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load([message(200)], into: page, store: store, nextSince: 200)
        let requests = await withTaskGroup(of: MessageHistoryRequest?.self) { group in
            for _ in 0..<20 { group.addTask { await store.beginLoadingNextPage(page) } }
            var claims: [MessageHistoryRequest] = []
            for await claim in group { if let claim { claims.append(claim) } }
            return claims
        }
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(await store.finishLoadingNextPage(request, result: history([message(199)])))
        #expect(store.messages(for: page).map(\.id) == [200, 199])
    }

    @Test
    func anOldServerResponseCannotWriteIntoAReopenedSession() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load([message(200)], into: page, store: store, nextSince: 200)
        let oldRequest = try #require(await store.beginLoadingNextPage(page))
        await store.discardCurrentSession()
        try await load([message(500)], into: page, store: store, nextSince: 500)
        let newRequest = try #require(await store.beginLoadingNextPage(page))

        #expect(oldRequest.sessionID != newRequest.sessionID)
        #expect(await !store.finishLoadingNextPage(oldRequest, result: history([message(199)])))
        #expect(store.messages(for: page).map(\.id) == [500])
        #expect(await store.beginLoadingNextPage(page) == nil)
        #expect(await store.finishLoadingNextPage(newRequest, result: history([message(400)])))
        #expect(store.messages(for: page).map(\.id) == [500, 400])
    }

    @Test
    func aBackgroundBurstFromTwoApplicationsKeepsHistoryStableAndPendingBodiesBounded() async throws {
        let store = MessageStore()
        let firstPage = MessagePage.application(7)
        let secondPage = MessagePage.application(9)
        try await load(messages(101...200), into: firstPage, store: store)
        try await load(messages(1...100, sourceID: 9), into: secondPage, store: store)
        let firstItems = store.timelineItems(for: firstPage)
        let secondItems = store.timelineItems(for: secondPage)
        for start in stride(from: 201, through: 10_101, by: 100) {
            let batch = (start..<(start + 100)).map { message($0, sourceID: $0.isMultiple(of: 2) ? 7 : 9) }
            _ = await store.insertCurrentSessionMessages(batch)
        }

        #expect(store.timelineItems(for: firstPage) == firstItems)
        #expect(store.timelineItems(for: secondPage) == secondItems)
        #expect(store.newMessageCount(for: 7) == 5_000)
        #expect(store.newMessageCount(for: 9) == 5_000)
        for page in [firstPage, secondPage, .all] {
            await store.revealPendingLiveMessages(for: page)
            // Existing history plus the latest 1,000 buffered entities; no per-frame body growth.
            #expect(store.messages(for: page).count <= 1_100)
            #expect(Set(store.messages(for: page).map(\.id)).count == store.messages(for: page).count)
            #expect(!store.hasPendingLiveMessages(for: page))
        }
        #expect(store.newMessageCount == 10_000)
    }

    @Test
    func aGapResponseStopsAtItsLowerBoundaryWithoutDuplicatingTheFollowingBlock() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load([message(20), message(10)], into: page, store: store, nextSince: 10)
        _ = await store.insertCurrentSessionMessages(messages(21...1_021))
        await store.revealPendingLiveMessages(for: page)
        let gap = try #require(gaps(in: store.timelineItems(for: page)).first)
        #expect(gap.since == 22)
        #expect(gap.through == 20)
        let prefix = Array(store.timelineItems(for: page).prefix(1_000))
        let request = try #require(await store.beginLoadingMore(page, gapID: gap.id))

        #expect(await store.finishLoadingMore(request, result: history([message(21), message(20), message(10)], nextSince: 10)))
        #expect(gaps(in: store.timelineItems(for: page)).isEmpty)
        #expect(Array(store.timelineItems(for: page).prefix(prefix.count)) == prefix)
        #expect(Array(store.messages(for: page).suffix(3)).map(\.id) == [21, 20, 10])
        #expect(Set(store.messages(for: page).map(\.id)).count == store.messages(for: page).count)
        #expect(store.newMessageCount(for: 7) == 1_001)
        let tailRequest = try #require(await store.beginLoadingNextPage(page))
        #expect(tailRequest.since == 10)
    }

    @Test
    func successiveGapPagesReplaceOnlyTheMissingRange() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load([message(200), message(199)], into: page, store: store)
        _ = await store.insertCurrentSessionMessages(messages(201...2_200))
        await store.revealPendingLiveMessages(for: page)
        let gap = try #require(gaps(in: store.timelineItems(for: page)).first)
        let prefix = Array(store.timelineItems(for: page).prefix(1_000))
        let request = try #require(await store.beginLoadingMore(page, gapID: gap.id))
        #expect(await store.finishLoadingMore(request, result: history(messages(1_101...1_200), nextSince: 1_101)))
        let nextGap = try #require(gaps(in: store.timelineItems(for: page)).first)

        #expect(nextGap.id != gap.id)
        #expect(nextGap.since == 1_101)
        #expect(nextGap.through == 200)
        #expect(Array(store.timelineItems(for: page).prefix(prefix.count)) == prefix)
        let secondRequest = try #require(await store.beginLoadingMore(page, gapID: nextGap.id))
        #expect(await store.finishLoadingMore(secondRequest, result: history(messages(1_001...1_100), nextSince: 1_001)))
        #expect(Array(store.timelineItems(for: page).prefix(prefix.count)) == prefix)
        #expect(Array(store.messages(for: page).suffix(2)).map(\.id) == [200, 199])
        #expect(store.messages(for: page).count == 1_202)
    }

    @Test
    func independentGapsCannotBlockEachOtherOrBeUnlockedByAnOldFailure() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load([message(200)], into: page, store: store)
        _ = await store.insertCurrentSessionMessages(messages(201...2_200))
        await store.revealPendingLiveMessages(for: page)
        _ = await store.insertCurrentSessionMessages(messages(2_201...4_200))
        await store.revealPendingLiveMessages(for: page)
        let missingRanges = gaps(in: store.timelineItems(for: page))
        #expect(missingRanges.count == 2)
        let first = try #require(await store.beginLoadingMore(page, gapID: missingRanges[0].id))
        let second = try #require(await store.beginLoadingMore(page, gapID: missingRanges[1].id))
        #expect(await store.beginLoadingMore(page, gapID: missingRanges[0].id) == nil)
        await store.failLoadingMore(first)
        let retry = try #require(await store.beginLoadingMore(page, gapID: missingRanges[0].id))
        await store.failLoadingMore(first)
        #expect(await store.beginLoadingMore(page, gapID: missingRanges[0].id) == nil)
        #expect(await store.beginLoadingMore(page, gapID: missingRanges[1].id) == nil)
        #expect(await !store.finishLoadingMore(first, result: history([])))
        #expect(await store.finishLoadingMore(retry, result: history([])))
        #expect(await store.finishLoadingMore(second, result: history([])))
    }

    @Test
    func reclaimingTheTailPreservesVisibleRowsAndResumesTheOrdinaryTailCursor() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load(messages(101...200), into: page, store: store, nextSince: 101)
        // Appearance callbacks need not arrive in spatial order. Reclamation uses timeline order.
        for id in [Int64(198), 200, 199] { await store.setMessageVisibility(id, visible: true, for: page) }
        _ = await store.insertCurrentSessionMessage(message(201))
        #expect(store.messages(for: page).map(\.id) == (184...201).reversed().map(Int64.init))
        #expect(gaps(in: store.timelineItems(for: page)).isEmpty)
        #expect(store.scrollAnchorID(for: page) == 200)
        await store.consumeScrollAnchor(200, for: page)
        let prefix = store.timelineItems(for: page)
        let request = try #require(await store.beginLoadingNextPage(page))
        #expect(request.since == 184)
        #expect(await store.finishLoadingNextPage(request, result: history(messages(84...183), nextSince: 84)))
        #expect(Array(store.timelineItems(for: page).prefix(prefix.count)) == prefix)
        #expect(store.scrollAnchorID(for: page) == nil)
    }

    @Test
    func consumingAnOlderAnchorCannotClearTheNextLiveInsertionAnchor() async throws {
        let store = MessageStore()
        let page = MessagePage.application(7)
        try await load(messages(1...3), into: page, store: store)
        await store.setMessageVisibility(3, visible: true, for: page)
        _ = await store.insertCurrentSessionMessage(message(4))
        await store.setMessageVisibility(4, visible: true, for: page)
        _ = await store.insertCurrentSessionMessage(message(5))
        #expect(store.scrollAnchorID(for: page) == 4)
        await store.consumeScrollAnchor(3, for: page)
        #expect(store.scrollAnchorID(for: page) == 4)
        await store.consumeScrollAnchor(4, for: page)
        #expect(store.scrollAnchorID(for: page) == nil)
    }

    // Fixtures use real page-store operations; no simplified pagination implementation is tested.
    private func message(_ id: Int, sourceID: Int64 = 7) -> GotifyMessage {
        GotifyMessage(id: Int64(id), title: "Message \(id)", body: "Summary", sourceID: sourceID, sourceName: "Application \(sourceID)", priority: 5, receivedAt: Date(timeIntervalSince1970: Double(id)), url: nil)
    }

    private func messages(_ range: ClosedRange<Int>, sourceID: Int64 = 7) -> [GotifyMessage] {
        range.reversed().map { message($0, sourceID: sourceID) }
    }

    private func history(_ messages: [GotifyMessage], nextSince: Int64? = nil) -> GotifyMessagePage {
        GotifyMessagePage(messages: messages, next: nextSince.map { "/message?since=\($0)" }, nextSince: nextSince)
    }

    private func load(_ messages: [GotifyMessage], into page: MessagePage, store: MessageStore, nextSince: Int64? = nil) async throws {
        let requestID = try #require(await store.beginLoading(page))
        await store.finishLoading(page, requestID: requestID, result: history(messages, nextSince: nextSince))
    }

    private func gaps(in items: [MessageTimelineItem]) -> [MessageTimelineGap] {
        items.compactMap { guard case let .gap(gap) = $0 else { return nil }; return gap }
    }
}
