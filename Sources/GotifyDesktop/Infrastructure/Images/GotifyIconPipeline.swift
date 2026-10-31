import Foundation
import Nuke

/// Nuke owns icon loading, request coalescing and disk eviction; this adapter only fixes the permitted cache boundary.
enum GotifyIconPipeline {
    private enum Configuration {
        static let directoryName = "com.gotify.desktop/ApplicationIcons"
        /// A recovery guard only; normal replacement removes the prior app-image entry immediately.
        static let diskLimit = 50 * 1_024 * 1_024
        /// Bounded in-memory LRU cache for decoded application icons so NSTableView cell recycling
        /// on macOS 12+ resolves icons synchronously without flashing the placeholder square.
        static let memoryCostLimit = 16 * 1_024 * 1_024
        static let memoryCountLimit = 128
    }

    static let cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Configuration.directoryName, isDirectory: true)

    static let pipeline: ImagePipeline = {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let session = URLSessionConfiguration.ephemeral
        session.urlCache = nil
        session.httpCookieStorage = nil
        session.urlCredentialStorage = nil

        var configuration = ImagePipeline.Configuration(dataLoader: DataLoader(configuration: session))
        let dataCache = try? DataCache(path: cacheDirectory)
        dataCache?.sizeLimit = Configuration.diskLimit
        configuration.dataCache = dataCache
        configuration.dataCachePolicy = .storeOriginalData
        configuration.imageCache = ImageCache(
            costLimit: Configuration.memoryCostLimit,
            countLimit: Configuration.memoryCountLimit
        )
        return ImagePipeline(configuration: configuration)
    }()

    static func clear() {
        pipeline.cache.removeAll()
    }
}
