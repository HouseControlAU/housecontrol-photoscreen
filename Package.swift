// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HouseControlPhotoScreen",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "housecontrol-photoscreen", targets: ["HouseControlPhotoScreen"])
    ],
    targets: [
        .executableTarget(name: "HouseControlPhotoScreen")
    ]
)
