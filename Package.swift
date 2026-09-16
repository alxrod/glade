// swift-tools-version: 5.9
import PackageDescription

// Model tests run without building or registering a second macOS app bundle.
let package = Package(
    name: "GladeCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GladeCore",
            path: "app/Glade/Glade/Models",
            exclude: ["MarkdownDocument.swift", "MarkdownHeading.swift"],
            sources: ["JSONValue.swift", "JSONLLine.swift", "JSONLDocument.swift", "JSONLColumnOrdering.swift", "JSONLineSearch.swift", "JSONLTimestampDisplay.swift", "UpdateChannel.swift"]
        ),
        .testTarget(name: "GladeCoreTests", dependencies: ["GladeCore"]),
    ]
)
