import Alamofire
import Foundation
import GotifyGeneratedClient

/// Tests a client token through Gotify's generated message-list endpoint.
///
/// This deliberately uses a real authenticated request: URL syntax or a local mock cannot tell
/// whether the supplied token is accepted by the selected Gotify server.
protocol GotifyConnectionTesting: Sendable {
    func test(serverURL: URL, clientToken: String) async throws
}

/// Production connection test backed entirely by the OpenAPI-generated Gotify client.
struct GeneratedGotifyConnectionTester: GotifyConnectionTesting {
    func test(serverURL: URL, clientToken: String) async throws {
        let apiConfiguration = GotifyGeneratedAPI.configuration(serverURL: serverURL, clientToken: clientToken)

        // A limit of one minimizes transfer while still requiring a valid client-token request.
        _ = try await MessageAPI.getMessages(limit: 1, apiConfiguration: apiConfiguration)
    }

}

/// Centralizes the generated client's authenticated, non-persistent transport configuration.
enum GotifyGeneratedAPI {
    static func configuration(serverURL: URL, clientToken: String) -> GotifyGeneratedClientAPIConfiguration {
        let codableHelper = CodableHelper()
        codableHelper.jsonDecoder = GotifyDateCoding.decoder
        return GotifyGeneratedClientAPIConfiguration(
            basePath: normalizedBasePath(serverURL),
            customHeaders: ["X-Gotify-Key": clientToken],
            requestBuilderFactory: EphemeralRequestBuilderFactory(),
            apiResponseQueue: DispatchQueue(label: "com.gotify.desktop.api"),
            codableHelper: codableHelper
        )
    }

    /// Gotify paths in the generated client begin with `/`, so a trailing slash would create `//message`.
    private static func normalizedBasePath(_ url: URL) -> String {
        var path = url.path
        while path.last == "/" {
            path.removeLast()
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.string ?? url.absoluteString
    }
}

/// Gotify 3 emits up to nanosecond precision, while older servers or zero-subsecond timestamps omit fractional seconds.
/// Shared by REST verification and WebSocket frames so both paths accept fractional and whole-second RFC 3339 dates.
enum GotifyDateCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let wholeSecondStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? fractionalStyle.parse(value) {
                return date
            }
            if let date = try? wholeSecondStyle.parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Gotify timestamp")
        }
        return decoder
    }()
}

/// Keeps token verification out of URLSession's persistent cookie, credential, and URL caches.
final class EphemeralRequestBuilderFactory: RequestBuilderFactory, @unchecked Sendable {
    func getNonDecodableBuilder<T>() -> RequestBuilder<T>.Type {
        EphemeralAlamofireRequestBuilder<T>.self
    }

    func getBuilder<T: Decodable>() -> RequestBuilder<T>.Type {
        EphemeralAlamofireDecodableRequestBuilder<T>.self
    }
}

/// Generated request construction is retained; only its documented session customization hook is overridden.
private final class EphemeralAlamofireRequestBuilder<T: Sendable>: AlamofireRequestBuilder<T>, @unchecked Sendable {
    override func createAlamofireSession() -> Alamofire.Session {
        .gotifyEphemeral
    }
}

/// The decodable builder needs the same ephemeral behavior as non-decodable generated requests.
private final class EphemeralAlamofireDecodableRequestBuilder<T: Decodable & Sendable>: AlamofireDecodableRequestBuilder<T>, @unchecked Sendable {
    override func createAlamofireSession() -> Alamofire.Session {
        .gotifyEphemeral
    }
}

private extension Alamofire.Session {
    /// One in-process session is sufficient because every generated request carries its own headers.
    static let gotifyEphemeral: Alamofire.Session = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return Alamofire.Session(configuration: configuration)
    }()
}
