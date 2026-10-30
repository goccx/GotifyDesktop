import Foundation
import GotifyGeneratedClient

/// Keeps a WebSocket burst off the main actor until a bounded batch is ready for presentation.
actor GotifyLiveMessageBuffer {
    private let batchSize: Int
    private let flushDelay: Duration
    private let consume: @Sendable ([Message]) async -> Void
    private var pendingMessages: [Message] = []
    private var scheduledFlush: Task<Void, Never>?

    init(
        batchSize: Int,
        flushDelay: Duration,
        consume: @escaping @Sendable ([Message]) async -> Void
    ) {
        self.batchSize = batchSize
        self.flushDelay = flushDelay
        self.consume = consume
    }

    /// Appending is actor-isolated, so Starscream never needs to enqueue one main-actor task per frame.
    func append(_ message: Message) {
        pendingMessages.append(message)
        guard scheduledFlush == nil else { return }
        scheduleFlush(after: flushDelay)
    }

    /// Ends an explicitly stopped session without allowing its queued frames to enter a later session.
    func discard() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingMessages.removeAll(keepingCapacity: false)
    }

    private func scheduleFlush(after delay: Duration) {
        scheduledFlush = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.flushOneBatch()
        }
    }

    private func flushOneBatch() async {
        scheduledFlush = nil
        guard !pendingMessages.isEmpty else { return }

        let count = min(batchSize, pendingMessages.count)
        let batch = Array(pendingMessages.prefix(count))
        pendingMessages.removeFirst(count)
        await consume(batch)

        // Drain remaining burst data in bounded chunks; yielding between chunks lets the main actor render.
        if !pendingMessages.isEmpty, scheduledFlush == nil {
            scheduleFlush(after: .zero)
        }
    }
}
