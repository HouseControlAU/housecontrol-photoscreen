// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HouseControlPhotoScreen",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "housecontrol-photoscreen", targets: ["HouseControlPhotoScreen"])
    ],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "HouseControlPhotoScreen",
            dependencies: [.product(name: "MediaRemoteAdapter", package: "mediaremote-adapter")]
        )
    ]
)
