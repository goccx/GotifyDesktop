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
    }
}
