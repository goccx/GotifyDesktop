import Foundation

/// A view-safe message representation; REST DTO generation will map into this domain model.
struct GotifyMessage: Identifiable, Hashable, Sendable {
    let id: Int64
    let title: String
    let body: String
    let sourceID: Int64
    let sourceName: String
    /// The service returns a versioned relative image path; resolving it here keeps UI free of URL rules.
    let sourceIconURL: URL?
    let priority: Int
    let receivedAt: Date
    let url: URL?
    /// Precomputed once at message creation so list rows never re-parse Markdown on the main thread during switches.
    let listTitle: String
    let listSummary: AttributedString

    /// Defaults keep non-network fixtures focused on the message behavior they exercise.
    init(
        id: Int64,
        title: String,
        body: String,
        sourceID: Int64 = 0,
        sourceName: String,
        sourceIconURL: URL? = nil,
        priority: Int,
        receivedAt: Date,
        url: URL?
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.sourceIconURL = sourceIconURL
        self.priority = priority
        self.receivedAt = receivedAt
        self.url = url
        self.listTitle = MessageMarkdownParser.plainTextSummary(
            from: title.isEmpty ? body : title
        )
        self.listSummary = MessageMarkdownParser.summaryAttributedString(from: body)
    }

    static func == (lhs: GotifyMessage, rhs: GotifyMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.body == rhs.body
            && lhs.sourceID == rhs.sourceID
            && lhs.sourceName == rhs.sourceName
            && lhs.sourceIconURL == rhs.sourceIconURL
            && lhs.priority == rhs.priority
            && lhs.receivedAt == rhs.receivedAt
            && lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(body)
        hasher.combine(sourceID)
        hasher.combine(sourceName)
        hasher.combine(sourceIconURL)
        hasher.combine(priority)
        hasher.combine(receivedAt)
        hasher.combine(url)
    }
}
