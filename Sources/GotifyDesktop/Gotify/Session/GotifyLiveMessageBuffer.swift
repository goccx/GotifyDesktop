import Foundation
import GotifyGeneratedClient

/// Keeps a WebSocket burst off the main actor until a bounded batch is ready for presentation.
actor GotifyLiveMessageBuffer {
    private let batchSize: Int
    private let flushDelayNanoseconds: UInt64
    private let consume: @Sendable ([Message]) async -> Void
    private var pendingMessages: [Message] = []
    private var scheduledFlush: Task<Void, Never>?

    init(
        batchSize: Int,
        flushDelayNanoseconds: UInt64,
        consume: @escaping @Sendable ([Message]) async -> Void
    ) {
        self.batchSize = batchSize
        self.flushDelayNanoseconds = flushDelayNanoseconds
        self.consume = consume
    }

    /// Appending is actor-isolated, so Starscream never needs to enqueue one main-actor task per frame.
    func append(_ message: Message) {
        pendingMessages.append(message)
        guard scheduledFlush == nil else { return }
        scheduleFlush(afterNanoseconds: flushDelayNanoseconds)
    }

    /// Ends an explicitly stopped session without allowing its queued frames to enter a later session.
    func discard() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingMessages.removeAll(keepingCapacity: false)
    }

    private func scheduleFlush(afterNanoseconds delayNanoseconds: UInt64) {
        scheduledFlush = Task { [weak self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
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
            scheduleFlush(afterNanoseconds: 0)
        }
    }
}
