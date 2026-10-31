import Defaults
import Foundation

/// Owns the small amount of connection configuration permitted to outlive the current process.
@MainActor
final class ServerPreferences: ObservableObject {
    @Published var serverURL: String
    @Published var clientToken: String
    @Published private(set) var receivesMessages: Bool
    @Published private(set) var isTestingConnection = false
    @Published private(set) var feedbackKey: String?

    private let connectionTester: any GotifyConnectionTesting
    private let sessionController: GotifySessionController?
    /// Invalidating this identifier prevents an in-flight verification from re-enabling a switch the user turned off.
    private var activeVerificationID: UUID?
    /// Startup restoration runs once per process; repeated scene creation must not open parallel WebSockets.
    private var hasAttemptedSessionRestoration = false

    init(connectionTester: any GotifyConnectionTesting = GeneratedGotifyConnectionTester(), sessionController: GotifySessionController? = nil) {
        self.connectionTester = connectionTester
        self.sessionController = sessionController
        let storedServerURL = Defaults[.serverURL]
        let storedToken = EncryptedClientTokenStore.decrypt(Defaults[.encryptedClientToken]) ?? ""
        serverURL = storedServerURL
        clientToken = storedToken
        // A persisted opt-in is meaningful only when both parts of the retained configuration exist.
        receivesMessages = Defaults[.receivesMessages] && !storedServerURL.isEmpty && !storedToken.isEmpty
        if !receivesMessages {
            Defaults[.receivesMessages] = false
        }
    }

    /// Restores an already verified opt-in without re-validating or changing the user's receiving preference.
    func restoreReceivingSessionIfNeeded() async {
        guard !hasAttemptedSessionRestoration else { return }
        hasAttemptedSessionRestoration = true
        guard receivesMessages,
              let url = validatedServerURL(serverURL),
              !clientToken.isEmpty,
              let sessionController
        else { return }

        do {
            try await sessionController.start(serverURL: url, clientToken: clientToken)
            feedbackKey = nil
        } catch {
            // An unavailable server is not an instruction to forget an explicitly saved connection.
            feedbackKey = "settings.connectionRestoreFailed"
        }
    }

    /// Enables receiving only after Gotify accepts the entered client token once.
    func setReceivesMessages(_ enabled: Bool) async {
        guard enabled else {
            activeVerificationID = nil
            isTestingConnection = false
            // Turning this off never erases the saved URL or encrypted token; it only opts out of receiving.
            Defaults[.receivesMessages] = false
            receivesMessages = false
            hasAttemptedSessionRestoration = false
            await sessionController?.stop(clearMessages: true)
            feedbackKey = "settings.receivingStopped"
            return
        }

        // The switch remains available to cancel; only a second enable request is ignored.
        guard !isTestingConnection else { return }

        // Snapshot both editable fields at the user action boundary. Editing while the request is
        // in flight must neither block the fields nor accidentally persist unverified new values.
        let submittedServerURL = serverURL
        guard let url = validatedServerURL(submittedServerURL) else {
            feedbackKey = "settings.serverURLRequired"
            return
        }

        let trimmedToken = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            feedbackKey = "settings.clientTokenRequired"
            return
        }

        isTestingConnection = true
        feedbackKey = nil
        let verificationID = UUID()
        activeVerificationID = verificationID
        defer {
            if activeVerificationID == verificationID {
                isTestingConnection = false
            }
        }

        do {
            try await connectionTester.test(serverURL: url, clientToken: trimmedToken)
            guard activeVerificationID == verificationID else { return }
            try await sessionController?.start(serverURL: url, clientToken: trimmedToken)
            guard activeVerificationID == verificationID else { return }
            guard persistConfiguration(serverURL: submittedServerURL, token: trimmedToken) else {
                Defaults[.receivesMessages] = false
                receivesMessages = false
                await sessionController?.stop(clearMessages: true)
                feedbackKey = "settings.connectionFailed"
                return
            }
            Defaults[.receivesMessages] = true
            receivesMessages = true
            feedbackKey = "settings.connectionVerified"
        } catch {
            guard activeVerificationID == verificationID else { return }
            // Do not log request details: they can include the server address and secret-bearing headers.
            Defaults[.receivesMessages] = false
            receivesMessages = false
            hasAttemptedSessionRestoration = false
            await sessionController?.stop(clearMessages: true)
            feedbackKey = "settings.connectionFailed"
        }
    }

    /// Inbox navigation requests only an in-memory page transition; the server configuration remains unchanged.
    func loadMessages(for sourceID: Int64?) async {
        await sessionController?.loadMessages(for: sourceID)
    }

    /// The inbox reaches older server history only from its right-hand pagination sentinel.
    func loadMoreMessages(for sourceID: Int64?, gapID: UUID) async throws {
        guard let sessionController else { throw CancellationError() }
        try await sessionController.loadMoreMessages(for: sourceID, gapID: gapID)
    }

    /// The automatic terminal sentinel uses this independent cursor path.
    func loadNextPage(for sourceID: Int64?) async throws {
        guard let sessionController else { throw CancellationError() }
        try await sessionController.loadNextPage(for: sourceID)
    }

    /// Deletes a single message on the server (`DELETE /message/{id}`) and removes it from process memory.
    func deleteMessage(_ message: GotifyMessage) async throws {
        guard let sessionController else { throw CancellationError() }
        try await sessionController.deleteMessage(message)
    }

    /// Deletes all messages (`DELETE /message`) or an application's messages (`DELETE /application/{id}/message`).
    func deleteMessages(for sourceID: Int64?) async throws {
        guard let sessionController else { throw CancellationError() }
        try await sessionController.deleteMessages(for: sourceID)
    }

    /// A verified configuration is retained automatically; the token reaches the preferences file only as AES-GCM ciphertext.
    private func persistConfiguration(serverURL: String, token: String) -> Bool {
        do {
            Defaults[.encryptedClientToken] = try EncryptedClientTokenStore.encrypt(token)
            Defaults[.serverURL] = serverURL
            return true
        } catch {
            // Do not retain a plaintext fallback when encryption unexpectedly fails.
            return false
        }
    }

    /// URL validation happens before any live request, avoiding accidental requests to malformed addresses.
    private func validatedServerURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url
        else { return nil }
        return url
    }

    var usesUnencryptedHTTP: Bool {
        URLComponents(string: serverURL)?.scheme?.lowercased() == "http"
    }
}
