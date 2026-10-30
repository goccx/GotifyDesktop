import Foundation
import GotifyGeneratedClient
import Starscream

/// A narrow event boundary keeps Starscream lifecycle code independent of the SwiftUI session store.
protocol GotifyWebSocketEventSource: Sendable {
    /// Begins the Gotify message stream for an already authenticated endpoint.
    func connect() async throws

    /// Stops the stream before switching servers or terminating the app process.
    func disconnect()
}

/// Starscream owns the WebSocket protocol; this adapter only supplies Gotify's stream URL and DTO decoding.
final class StarscreamGotifyWebSocketEventSource: GotifyWebSocketEventSource, @unchecked Sendable {
    private let streamURL: URL
    private let clientToken: String
    private let onMessage: @Sendable (Message) -> Void
    /// This deliberately reports only an established stream ending; connection failures remain `connect()` errors.
    private let onUnexpectedDisconnection: @Sendable () -> Void
    private var socket: WebSocket?
    /// `disconnect()` is a user/session action and must never start the automatic reconnect path.
    private var wasExplicitlyDisconnected = false

    init(
        serverURL: URL,
        clientToken: String,
        onMessage: @escaping @Sendable (Message) -> Void,
        onUnexpectedDisconnection: @escaping @Sendable () -> Void
    ) {
        self.streamURL = Self.makeStreamURL(from: serverURL)
        self.clientToken = clientToken
        self.onMessage = onMessage
        self.onUnexpectedDisconnection = onUnexpectedDisconnection
    }

    func connect() async throws {
        wasExplicitlyDisconnected = false
        var request = URLRequest(url: streamURL)
        request.setValue(clientToken, forHTTPHeaderField: "X-Gotify-Key")
        // URLSession's native engine handles modern TLS and proxy behavior consistently on macOS.
        let socket = WebSocket(request: request, useCustomEngine: false)
        // Frame decoding and buffering do not need the UI thread; the session explicitly hops to MainActor in batches.
        socket.callbackQueue = DispatchQueue(label: "com.gotify.desktop.websocket")
        self.socket = socket

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasFinishedHandshake = false
            var hasResumedConnection = false
            var hasReportedDisconnection = false
            // WebSocket retains its event closure, so lifecycle callbacks must not retain this adapter in return.
            weak var eventSource = self

            func resumeConnection(_ result: Result<Void, Error>) {
                guard !hasResumedConnection else { return }
                hasResumedConnection = true
                continuation.resume(with: result)
            }

            func reportUnexpectedDisconnection() {
                guard hasFinishedHandshake,
                      !hasReportedDisconnection,
                      eventSource?.wasExplicitlyDisconnected == false
                else { return }
                hasReportedDisconnection = true
                eventSource?.onUnexpectedDisconnection()
            }

            socket.onEvent = { [weak self] event in
                switch event {
                case .connected:
                    hasFinishedHandshake = true
                    resumeConnection(.success(()))
                case let .text(text):
                    self?.deliver(data: Data(text.utf8))
                case let .binary(data):
                    // Gotify-compatible proxies may preserve a binary WebSocket frame for JSON payloads.
                    self?.deliver(data: data)
                case let .error(error):
                    if !hasFinishedHandshake {
                        resumeConnection(.failure(error ?? URLError(.cannotConnectToHost)))
                    } else {
                        reportUnexpectedDisconnection()
                    }
                case .cancelled, .peerClosed, .disconnected:
                    if !hasFinishedHandshake {
                        resumeConnection(.failure(URLError(.networkConnectionLost)))
                    } else {
                        reportUnexpectedDisconnection()
                    }
                default:
                    break
                }
            }
            socket.connect()
        }
    }

    func disconnect() {
        wasExplicitlyDisconnected = true
        socket?.disconnect()
        socket = nil
    }

    private func deliver(data: Data) {
        // Keep the stream decoder identical to REST: Gotify timestamps can contain nanoseconds.
        guard let message = try? GotifyDateCoding.decoder.decode(Message.self, from: data) else { return }
        onMessage(message)
    }

    /// Preserve a configured reverse-proxy subpath while swapping only the transport and endpoint.
    private static func makeStreamURL(from serverURL: URL) -> URL {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/stream"
        if !components.path.hasPrefix("/") { components.path = "/" + components.path }
        components.query = nil
        return components.url!
    }
}
