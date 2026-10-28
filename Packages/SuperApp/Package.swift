// swift-tools-version:5.9
// Superapp: as abas "Buscar" (TorrentSearch) e "Legenda" ficam neste pacote local,
// em módulos próprios, para não misturar nomes com o código do iTorrent.
import PackageDescription

let package = Package(
    name: "SuperApp",
    defaultLocalization: "pt-BR",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "TorrentSearchKit", targets: ["TorrentSearchKit"]),
        .library(name: "LegendasKit", targets: ["LegendasKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "TorrentSearchKit",
            dependencies: ["SwiftSoup"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LegendasKit",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "LegendasKitTests", dependencies: ["LegendasKit"]),
    ]
)
