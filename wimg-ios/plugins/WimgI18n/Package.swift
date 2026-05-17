// swift-tools-version:5.10
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "WimgI18n",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "WimgI18n", targets: ["WimgI18n"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.0"),
    ],
    targets: [
        // Compiler plugin: parses the literal string passed to #L(...)
        // and emits `__t(...)` at compile time.
        .macro(
            name: "WimgI18nMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // Public API: re-exports the #L macro and bundles the `__t` runtime
        // lookup (generated from en.ts into Translations.swift in the app target).
        .target(
            name: "WimgI18n",
            dependencies: ["WimgI18nMacros"]
        ),
        .testTarget(
            name: "WimgI18nTests",
            dependencies: [
                "WimgI18n",
                "WimgI18nMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
