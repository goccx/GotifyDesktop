// swift-tools-version: 6.1
import PackageDescription

// The package is intentionally the single dependency authority for the desktop app.
let package = Package(
    name: "GotifyDesktop",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GotifyDesktop", targets: ["GotifyDesktop"]),
    ],
    dependencies: [
        // Generated from Gotify's official Swagger specification; never hand-edit its contents.
        .package(path: "Tools/OpenAPIGenerator/Generated"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.0"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8"),
        // Nuke 12.8+ declares Swift 6 and currently fails against this SDK's NSImage Sendable annotations.
        // Pin the latest compatible 12.7 release until upstream compatibility is verified in CI.
        .package(url: "https://github.com/kean/Nuke.git", exact: "12.7.0"),
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.0"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.5.0"),
        // Public-AppKit introspection keeps SwiftUI's native sidebar interaction while allowing
        // its otherwise-unconfigurable active selection paint to use our neutral design token.
        .package(url: "https://github.com/siteline/swiftui-introspect.git", exact: "26.0.1"),
        // Apple's stable ring-buffer collection keeps the long-running live message window bounded.
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "GotifyDesktop",
            dependencies: [
                .product(name: "GotifyGeneratedClient", package: "Generated"),
                "Alamofire",
                "Starscream",
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
                "Defaults",
                "Factory",
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "Sources/GotifyDesktop",
            // Packaging copies this notification-only asset into the main App bundle for AppKit notifications.
            exclude: ["SharedUI/Sounds"],
            resources: [
                .process("SharedUI/Localization/Resources"),
            ]
        ),
        .testTarget(
            name: "GotifyDesktopTests",
            dependencies: ["GotifyDesktop"],
            path: "Tests/GotifyDesktopTests"
        ),
    ],
    // Nuke 12 currently exposes an NSImage Sendable incompatibility under strict Swift 6 mode.
    // Keep the app source Swift-6-toolchain compatible while dependencies migrate their annotations.
    swiftLanguageModes: [.v5]
)
