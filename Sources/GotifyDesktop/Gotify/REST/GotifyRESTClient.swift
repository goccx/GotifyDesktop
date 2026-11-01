import Foundation
import GotifyGeneratedClient

/// The hand-written boundary deliberately contains no REST paths or DTOs; those come from OpenAPI output.
protocol GotifyRESTClient: Sendable {
    func fetchApplications() async throws -> [GotifyApplication]
    func fetchMessages(page: MessagePage, limit: Int, since: Int64?, applications: [Int64: GotifyApplication]) async throws -> GotifyMessagePage
    func deleteMessage(id: Int64) async throws
    func deleteMessages(for page: MessagePage) async throws
}

/// Live application metadata is sourced from `/application`; it contains no token or message content.
struct GotifyApplication: Sendable {
    let id: Int64
    let name: String
    let iconURL: URL?
}

/// Maps generated wire DTOs to the small, view-safe message model used only for this process session.
struct GeneratedGotifyRESTClient: GotifyRESTClient {
    let serverURL: URL
    let clientToken: String

    func fetchApplications() async throws -> [GotifyApplication] {
        let configuration = GotifyGeneratedAPI.configuration(serverURL: serverURL, clientToken: clientToken)
        return try await ApplicationAPI.getApps(apiConfiguration: configuration).map { application in
            let iconURL = Self.authenticatedIconURL(from: application.image, serverURL: serverURL)
            return GotifyApplication(id: application.id, name: application.name, iconURL: iconURL)
        }
    }

    func fetchMessages(
        page: MessagePage,
        limit: Int,
        since: Int64?,
        applications: [Int64: GotifyApplication]
    ) async throws -> GotifyMessagePage {
        let configuration = GotifyGeneratedAPI.configuration(serverURL: serverURL, clientToken: clientToken)
        let response = switch page {
        case .all:
            try await MessageAPI.getMessages(limit: limit, since: since, apiConfiguration: configuration)
        case let .application(id):
            try await MessageAPI.getAppMessages(id: id, limit: limit, since: since, apiConfiguration: configuration)
        }
        // Build `GotifyMessage` summaries (`AttributedString(markdown:)`) off the main actor so
        // first-time category loads never block UI responsiveness on macOS 12+.
        return await Task.detached(priority: .userInitiated) {
            GotifyMessagePage(
                messages: response.messages.map { message in
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
                },
                next: response.paging.next,
                nextSince: response.paging.next == nil ? nil : response.paging.since
            )
        }.value
    }

    func deleteMessage(id: Int64) async throws {
        let configuration = GotifyGeneratedAPI.configuration(serverURL: serverURL, clientToken: clientToken)
        try await MessageAPI.deleteMessage(id: id, apiConfiguration: configuration)
    }

    func deleteMessages(for page: MessagePage) async throws {
        let configuration = GotifyGeneratedAPI.configuration(serverURL: serverURL, clientToken: clientToken)
        switch page {
        case .all:
            try await MessageAPI.deleteMessages(apiConfiguration: configuration)
        case let .application(id):
            try await MessageAPI.deleteAppMessages(id: id, apiConfiguration: configuration)
        }
    }

    /// Application images are authenticated with the client token, so an application must never redirect it to another origin.
    /// Internal for a focused security regression test; callers still access it only through application mapping.
    static func authenticatedIconURL(from imagePath: String, serverURL: URL) -> URL? {
        guard !imagePath.isEmpty,
              let iconURL = URL(string: imagePath, relativeTo: serverURL)?.absoluteURL,
              let iconComponents = URLComponents(url: iconURL, resolvingAgainstBaseURL: false),
              let serverComponents = URLComponents(url: serverURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(iconComponents.scheme?.lowercased() ?? ""),
              iconComponents.scheme?.lowercased() == serverComponents.scheme?.lowercased(),
              iconComponents.host?.lowercased() == serverComponents.host?.lowercased(),
              iconComponents.port == serverComponents.port
        else { return nil }
        return iconURL
    }
}
