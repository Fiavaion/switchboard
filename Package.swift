// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwitchboardCore", path: "Sources/SwitchboardCore"),
        .executableTarget(
            name: "Switchboard",
            dependencies: ["SwitchboardCore"],
            path: "Sources/Switchboard",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "SwitchboardCoreTests", dependencies: ["SwitchboardCore"], path: "Tests/SwitchboardCoreTests"),
    ]
)
