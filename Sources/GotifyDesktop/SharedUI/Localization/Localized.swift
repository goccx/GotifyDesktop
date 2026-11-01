import Foundation

/// Centralizes package-bundle lookup so views never embed a user-facing translation directly in code.
enum Localized {
    /// Kept in sync with Defaults.Keys.language without making this low-level lookup depend on UI state.
    private static let languagePreferenceKey = "language"

    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: selectedBundle, comment: "")
    }

    /// Uses translated format strings for counts while keeping natural-language text out of views.
    static func string(_ key: String, _ value: CVarArg) -> String {
        String.localizedStringWithFormat(string(key), value)
    }

    private final class BundleLocator {}

    /// Resolves the resource bundle inside a packaged macOS `.app` (`Contents/Resources/`) or
    /// relative to the running executable/test bundle without referencing SwiftPM's `Bundle.module`
    /// (which embeds the build machine's absolute directory path into the binary).
    private static let packageBundle: Bundle = {
        let bundleName = "GotifyDesktop_GotifyDesktop.bundle"
        let codeBundle = Bundle(for: BundleLocator.self)
        let directCandidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            codeBundle.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            codeBundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName),
        ]
        for candidate in directCandidates {
            if let url = candidate, let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()

    private static let englishBundle: Bundle = {
        guard let path = packageBundle.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return packageBundle
        }
        return bundle
    }()

    private static let simplifiedChineseBundle: Bundle = {
        guard let path = packageBundle.path(forResource: "zh-hans", ofType: "lproj")
                ?? packageBundle.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return packageBundle
        }
        return bundle
    }()

    private static var selectedBundle: Bundle {
        switch UserDefaults.standard.string(forKey: languagePreferenceKey) {
        case "english": return englishBundle
        case "simplifiedChinese": return simplifiedChineseBundle
        default: return packageBundle
        }
    }
}
