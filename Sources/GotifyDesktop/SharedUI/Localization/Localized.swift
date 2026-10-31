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

    /// Resolves the resource bundle inside a packaged macOS `.app` (`Contents/Resources/`) first
    /// because SwiftPM's generated `Bundle.module` checks `Bundle.main.bundleURL` (the `.app` root,
    /// where `codesign` forbids placing loose bundles) and the build machine's absolute path.
    private static let packageBundle: Bundle = {
        let bundleName = "GotifyDesktop_GotifyDesktop.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName)
        ]
        for candidate in candidates {
            if let url = candidate, let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.module
    }()

    private static var selectedBundle: Bundle {
        let language = UserDefaults.standard.string(forKey: languagePreferenceKey)
        let resourceName: String?

        switch language {
        case "english": resourceName = "en"
        case "simplifiedChinese": resourceName = "zh-Hans"
        default: resourceName = nil
        }

        guard let resourceName,
              let path = packageBundle.path(forResource: resourceName.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return packageBundle
        }

        return bundle
    }
}
