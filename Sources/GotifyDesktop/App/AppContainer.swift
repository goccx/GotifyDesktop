import Factory

/// The composition root centralizes dependency ownership and enables test replacement.
extension Container {
    /// A singleton is appropriate because it represents only the current process session, never disk data.
    var messageStore: Factory<MessageStore> {
        self { @MainActor in MessageStore() }.singleton
    }
}
