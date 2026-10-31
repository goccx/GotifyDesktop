import Foundation
import Combine
import Testing
@testable import GotifyDesktop

/// This test records the privacy boundary: session replacement never persists messages.
@MainActor
struct GotifyDesktopTests {
    @Test
    func localizedStringsFollowExplicitLanguagePreference() {
        let previousValue = UserDefaults.standard.object(forKey: "language")
        defer {
            UserDefaults.standard.set(previousValue, forKey: "language")
        }

        UserDefaults.standard.set("english", forKey: "language")
        #expect(Localized.string("sidebar.allMessages") == "All Messages")
        #expect(Localized.string("connection.notConfigured") == "No server configured")
        #expect(Localized.string("message.markAllRead") == "Mark All as Read")

        UserDefaults.standard.set("simplifiedChinese", forKey: "language")
        #expect(Localized.string("sidebar.allMessages") == "所有消息")
        #expect(Localized.string("connection.notConfigured") == "尚未配置服务端")
        #expect(Localized.string("message.markAllRead") == "全部标记已读")
    }

    @Test
    func languagePreferenceImmediatelyUpdatesLocalizedLookup() {
        let previousValue = UserDefaults.standard.object(forKey: "language")
        defer {
            UserDefaults.standard.set(previousValue, forKey: "language")
        }

        let preferences = AppPreferences()
        preferences.language = .english
        #expect(Localized.string("sidebar.allMessages") == "All Messages")

        preferences.language = .simplifiedChinese
        #expect(Localized.string("sidebar.allMessages") == "所有消息")
    }

    @Test
    func sessionMessageReplacementPreservesServerOrder() async {
        let store = MessageStore()
        let older = GotifyMessage(id: 1, title: "Older", body: "", sourceName: "backend", priority: 5, receivedAt: .distantPast, url: nil)
        let newer = GotifyMessage(id: 2, title: "Newer", body: "", sourceName: "backend", priority: 5, receivedAt: .now, url: nil)

        await store.replaceCurrentSessionMessages([newer, older])

        #expect(store.messages.map(\.id) == [newer.id, older.id])
    }

    @Test
    func liveMessagesRetainAttentionCountIndependentlyOfHistory() async {
        let store = MessageStore()
        let baseDate = Date(timeIntervalSince1970: 0)

        for id in 1...101 {
            _ = await store.insertCurrentSessionMessage(
                GotifyMessage(
                    id: Int64(id),
                    title: "Message \(id)",
                    body: "",
                    sourceName: "backend",
                    priority: 5,
                    receivedAt: baseDate.addingTimeInterval(TimeInterval(id)),
                    url: nil
                )
            )
        }
        await store.revealPendingLiveMessages(for: .all)

        #expect(store.messages.map(\.id).prefix(3) == [101, 100, 99])
        #expect(store.messages.count == 101)
        #expect(store.newMessageCount == 101)
    }

    @Test
    func duplicateLiveDeliveryIsRejectedBeforeItCanProduceAnotherAlert() async {
        let store = MessageStore()
        let message = GotifyMessage(
            id: 42,
            title: "One delivery",
            body: "",
            sourceName: "backend",
            priority: 5,
            receivedAt: .now,
            url: nil
        )

        #expect(await store.insertCurrentSessionMessage(message))
        // The session coordinator uses this result as the notification gate for a WebSocket retry.
        #expect(await !store.insertCurrentSessionMessage(message))
        #expect(store.messages.map(\.id) == [message.id])
    }

    @Test
    func aBurstBatchKeepsOnlyDistinctMessagesAndMaintainsDateOrder() async {
        let store = MessageStore()
        let reference = Date(timeIntervalSince1970: 1_000)
        let newer = GotifyMessage(id: 2, title: "Newer", body: "", sourceName: "backend", priority: 5, receivedAt: reference.addingTimeInterval(1), url: nil)
        let older = GotifyMessage(id: 1, title: "Older", body: "", sourceName: "backend", priority: 5, receivedAt: reference, url: nil)

        let inserted = await store.insertCurrentSessionMessages([older, newer, older])

        #expect(inserted.map(\.id) == [older.id, newer.id])
        #expect(store.messages.map(\.id) == [newer.id, older.id])
        #expect(store.newMessageCount == 2)
    }

    @Test
    func aLoadedApplicationPageIsReusedWithoutStartingAnotherRequest() async {
        let store = MessageStore()
        let page = MessagePage.application(12)
        let requestID = try! #require(await store.beginLoading(page))
        #expect(await store.beginLoading(page) == nil)

        let message = GotifyMessage(
            id: 12,
            title: "Cached page",
            body: "",
            sourceID: 12,
            sourceName: "backend",
            priority: 5,
            receivedAt: .now,
            url: nil
        )
        await store.finishLoading(page, requestID: requestID, result: GotifyMessagePage(messages: [message], next: nil, nextSince: nil))

        #expect(store.pageLoadState(for: page) == .loaded)
        #expect(store.messages(for: page).map(\.id) == [message.id])
        #expect(await store.beginLoading(page) == nil)
    }

    @Test
    func olderHistoryUsesOnlyTheSelectedPagesCursorAndAppendsToTheReadingCanvas() async {
        let store = MessageStore()
        let page = MessagePage.application(7)
        let firstRequest = try! #require(await store.beginLoading(page))
        let newest = GotifyMessage(id: 30, title: "Newest", body: "", sourceID: 7, sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        await store.finishLoading(
            page,
            requestID: firstRequest,
            result: GotifyMessagePage(messages: [newest], next: "/application/7/message?limit=100&since=30", nextSince: 30)
        )

        let request = try! #require(await store.beginLoadingNextPage(page))
        #expect(request.since == 30)
        let older = GotifyMessage(id: 20, title: "Older", body: "", sourceID: 7, sourceName: "backend", priority: 5, receivedAt: .distantPast, url: nil)
        await store.finishLoadingNextPage(
            request,
            result: GotifyMessagePage(messages: [older], next: nil, nextSince: nil)
        )

        #expect(store.messages(for: page).map(\.id) == [newest.id, older.id])
        #expect(!store.hasNextPage(for: page))
        #expect(await store.beginLoadingNextPage(page) == nil)
    }

    @Test
    func consecutiveTailRequestsFollowEveryServerNextCursor() async {
        let store = MessageStore()
        let page = MessagePage.application(9)
        let initialRequest = try! #require(await store.beginLoading(page))
        let first = GotifyMessage(id: 300, title: "First", body: "", sourceID: 9, sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        await store.finishLoading(page, requestID: initialRequest, result: GotifyMessagePage(messages: [first], next: "/application/9/message?limit=100&since=300", nextSince: 300))

        let secondSince = try! #require(await store.beginLoadingNextPage(page))
        #expect(secondSince.since == 300)
        let second = GotifyMessage(id: 200, title: "Second", body: "", sourceID: 9, sourceName: "backend", priority: 5, receivedAt: .distantPast, url: nil)
        await store.finishLoadingNextPage(secondSince, result: GotifyMessagePage(messages: [second], next: "/application/9/message?limit=100&since=200", nextSince: 200))

        let thirdSince = try! #require(await store.beginLoadingNextPage(page))
        #expect(thirdSince.since == 200)
        let third = GotifyMessage(id: 100, title: "Third", body: "", sourceID: 9, sourceName: "backend", priority: 5, receivedAt: .distantPast.addingTimeInterval(-1), url: nil)
        await store.finishLoadingNextPage(thirdSince, result: GotifyMessagePage(messages: [third], next: nil, nextSince: nil))

        #expect(store.messages(for: page).map(\.id) == [first.id, second.id, third.id])
        #expect(!store.hasNextPage(for: page))
    }

    /// A footer request must not invalidate existing rows until there is actual appended history.
    /// Failure/retry preserves both the old payload prefix and its stable row identities.
    @Test
    func tailRequestPublishesOnlyTheAppendAndPreservesExistingRows() async throws {
        let store = MessageStore()
        let page = MessagePage.application(9)
        let initialRequest = try #require(await store.beginLoading(page))
        let initial = (101...200).reversed().map { id in
            GotifyMessage(id: Int64(id), title: "Message \(id)", body: "Summary", sourceID: 9, sourceName: "backend", priority: 5, receivedAt: Date(timeIntervalSince1970: Double(id)), url: nil)
        }
        await store.finishLoading(page, requestID: initialRequest, result: GotifyMessagePage(messages: initial, next: "/application/9/message?since=101", nextSince: 101))
        let oldItems = store.timelineItems(for: page)
        var invalidations = 0
        let observation = store.objectWillChange.sink { invalidations += 1 }
        defer { observation.cancel() }

        let firstRequest = try #require(await store.beginLoadingNextPage(page))
        #expect(firstRequest.since == 101)
        #expect(await store.beginLoadingNextPage(page) == nil)
        #expect(invalidations == 0)
        await store.failLoadingNextPage(firstRequest)
        #expect(invalidations == 0)
        #expect(store.timelineItems(for: page) == oldItems)
        #expect(store.hasNextPage(for: page))
        let retryRequest = try #require(await store.beginLoadingNextPage(page))
        #expect(retryRequest.since == 101)

        let older = (1...100).reversed().map { id in
            GotifyMessage(id: Int64(id), title: "Message \(id)", body: "Summary", sourceID: 9, sourceName: "backend", priority: 5, receivedAt: Date(timeIntervalSince1970: Double(id)), url: nil)
        }
        // The duplicate deliberately exercises the REST/live overlap without replacing old rows.
        await store.finishLoadingNextPage(retryRequest, result: GotifyMessagePage(messages: [initial.last!] + older, next: nil, nextSince: nil))
        #expect(invalidations == 1)
        #expect(Array(store.timelineItems(for: page).prefix(oldItems.count)) == oldItems)
        #expect(store.messages(for: page).map(\.id) == (1...200).reversed().map(Int64.init))
        #expect(store.scrollAnchorID(for: page) == nil)
        #expect(store.pageLoadState(for: page) == .loaded)
        #expect(store.newMessageCount == 0)
        #expect(!store.hasNextPage(for: page))
    }

    @Test
    func sourceAttentionSurvivesAHistoryPageAndCapsOnlyRowLevelIDs() async {
        let store = MessageStore()
        let date = Date(timeIntervalSince1970: 1_000)
        for id in 1...1_001 {
            _ = await store.insertCurrentSessionMessage(
                GotifyMessage(id: Int64(id), title: "Live", body: "", sourceID: 4, sourceName: "backend", priority: 5, receivedAt: date.addingTimeInterval(TimeInterval(id)), url: nil)
            )
        }

        #expect(store.newMessageCount(for: 4) == 1_001)
        #expect(store.isNewMessage(1_001, sourceID: 4))
        #expect(!store.isNewMessage(1, sourceID: 4))
        store.markAllMessagesViewed(for: .application(4))
        #expect(store.newMessageCount(for: 4) == 0)
    }

    @Test
    func liveMessageArrivingDuringPageLoadRemainsVisibleAfterTheRESTSnapshot() async {
        let store = MessageStore()
        let page = MessagePage.application(7)
        let requestID = try! #require(await store.beginLoading(page))
        let live = GotifyMessage(
            id: 2,
            title: "Live",
            body: "",
            sourceID: 7,
            sourceName: "backend",
            priority: 5,
            receivedAt: .now,
            url: nil
        )
        let history = GotifyMessage(
            id: 1,
            title: "History",
            body: "",
            sourceID: 7,
            sourceName: "backend",
            priority: 5,
            receivedAt: .distantPast,
            url: nil
        )

        #expect(await store.insertCurrentSessionMessage(live))
        await store.finishLoading(page, requestID: requestID, result: GotifyMessagePage(messages: [history], next: nil, nextSince: nil))

        #expect(store.messages(for: page).map(\.id) == [live.id, history.id])
    }

    @Test
    func loadingAnotherApplicationDoesNotEvictTheCurrentTimeline() async {
        let store = MessageStore()
        let now = Date.now
        let recentMessages = (1...101).map { id in
            GotifyMessage(id: Int64(id), title: "Recent", body: "", sourceID: 1, sourceName: "codex", priority: 5, receivedAt: now.addingTimeInterval(TimeInterval(id)), url: nil)
        }
        for message in recentMessages { _ = await store.insertCurrentSessionMessage(message) }
        await store.revealPendingLiveMessages(for: .all)

        let selectedPage = MessagePage.application(2)
        let requestID = try! #require(await store.beginLoading(selectedPage))
        let oldSourceMessage = GotifyMessage(id: 1_000, title: "Older source", body: "", sourceID: 2, sourceName: "opai", priority: 5, receivedAt: now.addingTimeInterval(-100), url: nil)
        await store.finishLoading(selectedPage, requestID: requestID, result: GotifyMessagePage(messages: [oldSourceMessage], next: nil, nextSince: nil))

        #expect(store.pageLoadState(for: selectedPage) == .loaded)
        #expect(store.messages(for: selectedPage).map(\.id) == [oldSourceMessage.id])
        #expect(store.messages.count == 101)
    }

    @Test
    func discardingASessionClearsSourcesPagesAndAttentionState() async {
        let store = MessageStore()
        store.replaceApplications([GotifyApplication(id: 1, name: "Old server", iconURL: nil)])
        let oldMessage = GotifyMessage(id: 1, title: "Old", body: "", sourceID: 1, sourceName: "Old server", priority: 5, receivedAt: .now, url: nil)
        #expect(await store.insertCurrentSessionMessage(oldMessage))

        await store.discardCurrentSession()

        #expect(store.messages.isEmpty)
        #expect(store.applications.isEmpty)
        #expect(store.newMessageCount == 0)
        #expect(store.pageLoadState(for: .all) == .idle)
    }

    @Test
    func applicationIconsCannotSendTheClientTokenToAnotherOrigin() throws {
        let serverURL = try #require(URL(string: "https://gotify.example/proxy"))

        #expect(
            GeneratedGotifyRESTClient.authenticatedIconURL(from: "/image/7", serverURL: serverURL)?.absoluteString
                == "https://gotify.example/image/7"
        )
        #expect(GeneratedGotifyRESTClient.authenticatedIconURL(from: "https://other.example/image/7", serverURL: serverURL) == nil)
        #expect(GeneratedGotifyRESTClient.authenticatedIconURL(from: "", serverURL: serverURL) == nil)
    }

    @Test
    func encryptedClientTokenNeverPersistsAsPlaintext() throws {
        let token = "gtfyc.example-token-for-test-only"

        let encrypted = try EncryptedClientTokenStore.encrypt(token)

        #expect(encrypted != token)
        #expect(!encrypted.contains(token))
        #expect(EncryptedClientTokenStore.decrypt(encrypted) == token)
        #expect(EncryptedClientTokenStore.decrypt(token) == nil)
    }

    @Test
    func viewingAndMarkingAllMessagesOnlyChangeSessionAttentionState() async {
        let store = MessageStore()
        let message = GotifyMessage(id: 1, title: "Message", body: "", sourceName: "backend", priority: 5, receivedAt: .now, url: nil)

        _ = await store.insertCurrentSessionMessage(message)
        store.markMessageViewed(message.id, sourceID: message.sourceID)
        #expect(store.newMessageCount == 0)
        #expect(store.messages.map(\.id) == [message.id])

        _ = await store.insertCurrentSessionMessage(
            GotifyMessage(id: 2, title: "Another", body: "", sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        )
        store.markAllMessagesViewed(for: .all)
        #expect(store.newMessageCount == 0)
        // Clearing attention is not navigation and must not insert pending rows into history.
        #expect(store.messages.count == 1)
        await store.revealPendingLiveMessages(for: .all)
        #expect(store.messages.count == 2)
    }

    @Test
    func dateDecoderAcceptsBothFractionalAndWholeSecondTimestamps() throws {
        struct Sample: Decodable {
            let date: Date
        }

        let fractional = Data(#"{"date":"2026-09-17T10:00:00.123456789Z"}"#.utf8)
        let wholeSecond = Data(#"{"date":"2026-09-17T10:00:00Z"}"#.utf8)

        _ = try GotifyDateCoding.decoder.decode(Sample.self, from: fractional)
        _ = try GotifyDateCoding.decoder.decode(Sample.self, from: wholeSecond)
    }

    @Test
    func deletingASingleMessageUpdatesBothAllAndApplicationPagesAndClearsAttention() async throws {
        let store = MessageStore()
        let first = GotifyMessage(id: 10, title: "First", body: "", sourceID: 7, sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        let second = GotifyMessage(id: 11, title: "Second", body: "", sourceID: 7, sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        let otherSource = GotifyMessage(id: 12, title: "Other", body: "", sourceID: 9, sourceName: "worker", priority: 5, receivedAt: .now, url: nil)

        let appRequestID = try #require(await store.beginLoading(.application(7)))
        await store.finishLoading(.application(7), requestID: appRequestID, result: GotifyMessagePage(messages: [], next: nil, nextSince: nil))

        _ = await store.insertCurrentSessionMessages([first, second, otherSource])
        await store.revealPendingLiveMessages(for: .all)
        await store.revealPendingLiveMessages(for: .application(7))
        #expect(store.newMessageCount == 3)
        #expect(store.newMessageCount(for: 7) == 2)

        await store.removeCurrentSessionMessage(id: 11, sourceID: 7)

        #expect(store.messages(for: .all).map(\.id) == [12, 10])
        #expect(store.messages(for: .application(7)).map(\.id) == [10])
        #expect(store.newMessageCount == 2)
        #expect(store.newMessageCount(for: 7) == 1)
        #expect(!store.isNewMessage(11, sourceID: 7))
    }

    @Test
    func deletingAllMessagesForASourceOrAllSourcesUpdatesLoadedSnapshotsAndAttention() async throws {
        let store = MessageStore()
        let sourceSevenA = GotifyMessage(id: 21, title: "A", body: "", sourceID: 7, sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        let sourceSevenB = GotifyMessage(id: 22, title: "B", body: "", sourceID: 7, sourceName: "backend", priority: 5, receivedAt: .now, url: nil)
        let sourceNine = GotifyMessage(id: 23, title: "C", body: "", sourceID: 9, sourceName: "worker", priority: 5, receivedAt: .now, url: nil)

        let req7 = try #require(await store.beginLoading(.application(7)))
        await store.finishLoading(.application(7), requestID: req7, result: GotifyMessagePage(messages: [], next: nil, nextSince: nil))
        let req9 = try #require(await store.beginLoading(.application(9)))
        await store.finishLoading(.application(9), requestID: req9, result: GotifyMessagePage(messages: [], next: nil, nextSince: nil))

        _ = await store.insertCurrentSessionMessages([sourceSevenA, sourceSevenB, sourceNine])
        await store.revealPendingLiveMessages(for: .all)
        await store.revealPendingLiveMessages(for: .application(7))
        await store.revealPendingLiveMessages(for: .application(9))

        await store.removeCurrentSessionMessages(for: .application(7))

        #expect(store.messages(for: .application(7)).isEmpty)
        #expect(store.messages(for: .all).map(\.id) == [23])
        #expect(store.newMessageCount(for: 7) == 0)
        #expect(store.newMessageCount == 1)

        await store.removeCurrentSessionMessages(for: .all)

        #expect(store.messages(for: .all).isEmpty)
        #expect(store.messages(for: .application(9)).isEmpty)
        #expect(store.newMessageCount == 0)
        #expect(store.newMessageCount(for: 9) == 0)
    }

    @Test
    func deleteResponseSerializerAcceptsEmpty200BodyReturnedByGotifyDeleteEndpoints() throws {
        let serverURL = try #require(URL(string: "https://gotify.example"))
        let config = GotifyGeneratedAPI.configuration(serverURL: serverURL, clientToken: "test-token")
        let response = try #require(
            HTTPURLResponse(
                url: serverURL.appendingPathComponent("message/42"),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "0"]
            )
        )

        let serialized = try config.dataResponseSerializer.serialize(
            request: nil,
            response: response,
            data: Data(),
            error: nil
        )
        #expect(serialized.isEmpty)
    }

    @Test
    func markdownParserBuildsStructuredBlocksForHeadingsListsCodeDividersAndTables() {
        let sample = """
        ### 1. [`AgentNotify/README.zh-CN.md`](file:///Users/testm/gitwork/GotifyDesk/AgentNotify/README.zh-CN.md) 里的配置

        1. **Antigravity (`antigravity-notify.sh`)**：
           - `PreToolUse`：自动判断审批

        > 原始消息精致处理

        ```json
        {
          "decision": "allow"
        }
        ```

        | 事件 | 行为 |
        | --- | --- |
        | Stop | 完成通知 |

        ---
        Prompt: 继续迭代
        """

        let blocks = MessageMarkdownParser.parseBlocks(from: sample)
        #expect(blocks == [
            .heading(
                level: 3,
                text: "1. [`AgentNotify/README.zh-CN.md`](file:///Users/testm/gitwork/GotifyDesk/AgentNotify/README.zh-CN.md) 里的配置"
            ),
            .orderedListItem(
                indent: 0,
                marker: "1.",
                text: "**Antigravity (`antigravity-notify.sh`)**："
            ),
            .unorderedListItem(
                indent: 1,
                text: "`PreToolUse`：自动判断审批"
            ),
            .blockquote(text: "原始消息精致处理"),
            .codeBlock(language: "json", code: "{\n  \"decision\": \"allow\"\n}"),
            .table(headers: ["事件", "行为"], rows: [["Stop", "完成通知"]]),
            .horizontalRule,
            .paragraph(text: "Prompt: 继续迭代"),
        ])
    }

    @Test
    func markdownInlineParserStripsLocalFileLinksPreservesWebLinksAndHandlesCJKBold() throws {
        let raw = "查看 [`AgentNotify/README.zh-CN.md`](file:///Users/testm/gitwork/GotifyDesk/AgentNotify/README.zh-CN.md) 与 [Gotify 文档](https://gotify.net/docs)，都是**唯一且最佳的无误报方案**：且 **Antigravity (`hooks.json`)**是最佳。"
        let attributed = MessageMarkdownParser.inlineAttributedString(from: raw)
        let plainText = String(attributed.characters)

        #expect(plainText == "查看 AgentNotify/README.zh-CN.md 与 Gotify 文档，都是唯一且最佳的无误报方案：且 Antigravity (hooks.json)是最佳。")
        #expect(!plainText.contains("file://"))
        #expect(!plainText.contains("**"))

        let links = attributed.runs.compactMap(\.link)
        #expect(links == [try #require(URL(string: "https://gotify.net/docs"))])

        let boldText = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(attributed[$0.range].characters) }
            .joined()
        #expect(boldText.contains("唯一且最佳的无误报方案"))
        #expect(boldText.contains("Antigravity ("))
    }

    @Test
    func plainTextSummaryCollapsesMarkdownBlocksForListRowsAndBanners() {
        let raw = """
        ### 1. [`AgentNotify/README.zh-CN.md`](file:///Users/testm/gitwork/GotifyDesk/AgentNotify/README.zh-CN.md)
        里的配置，都是**唯一且最佳的无误报方案**：
        ---
        Prompt: 继续迭代
        """

        let summary = MessageMarkdownParser.plainTextSummary(from: raw)
        #expect(summary == "1. AgentNotify/README.zh-CN.md 里的配置，都是唯一且最佳的无误报方案： Prompt: 继续迭代")
    }

    @Test
    func findMessageLocatesMessageAcrossAllAndPendingBuffersForNotificationActivation() async {
        let store = MessageStore()
        let message = GotifyMessage(
            id: 88,
            title: "Task Completed",
            body: "Done",
            sourceID: 5,
            sourceName: "antigravity",
            priority: 5,
            receivedAt: .now,
            url: nil
        )

        #expect(await store.insertCurrentSessionMessage(message))
        let located = await store.findMessage(id: 88)
        #expect(located == message)
    }
}
