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

    private static var selectedBundle: Bundle {
        let language = UserDefaults.standard.string(forKey: languagePreferenceKey)
        let resourceName: String?

        switch language {
        case "english": resourceName = "en"
        case "simplifiedChinese": resourceName = "zh-Hans"
        default: resourceName = nil
        }

        guard let resourceName,
              let path = Bundle.module.path(forResource: resourceName.lowercased(), ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .module
        }

        return bundle
    }
}
