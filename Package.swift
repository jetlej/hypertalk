// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "hypertalk",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // WhisperKit, renamed argmax-oss-swift. 1.1.0 is the first release with
        // argmax-oss-swift#514: before it, any transcription with promptTokens
        // came back empty, which the dictionary's example sentence relies on.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
        // In-app updates (#50). A binary framework: scripts/build-app.sh
        // embeds it in Hypertalk.app/Contents/Frameworks and signs it.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        // Parakeet on the Neural Engine. No traits: ASR only, without the
        // TTS resource bundle and text-normalization binary it would embed.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7", traits: []),
    ],
    targets: [
        // All behaviour: capture, hotkey, transcription, pipeline, settings, UI.
        .target(
            name: "HypertalkCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        // Thin entry point: ArgumentParser commands that call into HypertalkCore.
        .executableTarget(
            name: "hypertalk",
            dependencies: [
                "HypertalkCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Developer benchmarks (#49, #52), not shipped in Hypertalk.app:
        // swift run -c release hypertalk-bench transcription|capture ...
        .executableTarget(
            name: "hypertalk-bench",
            dependencies: [
                "HypertalkCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Unit tests against HypertalkCore.
        .testTarget(
            name: "HypertalkTests",
            dependencies: ["HypertalkCore"]
        ),
        // Unit tests for the benchmarks' pure parts.
        .testTarget(
            name: "HypertalkBenchTests",
            dependencies: ["hypertalk-bench"]
        ),
    ],
    // Tools 6.1 for package traits; the code is still Swift 5 mode.
    swiftLanguageModes: [.v5]
)
