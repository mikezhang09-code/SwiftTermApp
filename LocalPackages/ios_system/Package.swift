// swift-tools-version:5.3

// A slim mirror of https://github.com/holzschu/ios_system's package manifest
// (v3.0.5): same binary frameworks, same checksums, but only the modern
// v3.0.4-built targets.  The upstream product also bundles perl and mandoc,
// which are old 2.7-era builds without a simulator slice and break simulator
// builds — and referencing upstream via git also drags in a wasm3 submodule
// pinned to an SSH URL.  Binary targets sidestep both problems.

import PackageDescription

let package = Package(
    name: "ios_system",
    products: [
        // curl_ios is deliberately absent: it dynamically links libssh2.framework and
        // openssl.framework, which are not shipped anywhere we can pull from, and the
        // missing libraries abort the whole app at launch (dyld halt -> white screen)
        .library(name: "ios_system", targets: ["ios_system", "awk", "files", "shell", "tar", "text"])
    ],
    targets: [
        .binaryTarget(
            name: "ios_system",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.4/ios_system.xcframework.zip",
            checksum: "6973c1c14a66cdc110a5be7d62991af4546124bd0d9773b5391694b3a93a5be0"
        ),
        .binaryTarget(
            name: "awk",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.4/awk.xcframework.zip",
            checksum: "6898b01913261eee194edcb464212d4af6bc33355b1e286bbbd17f3f878c1706"
        ),
        .binaryTarget(
            name: "files",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.4/files.xcframework.zip",
            checksum: "02d6522f5e1adc3b472f7aaa53910f049e6c5829e07c7e3005cf2a0d5f9f423a"
        ),
        .binaryTarget(
            name: "shell",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.4/shell.xcframework.zip",
            checksum: "78d71828b89c83741a8f7e857f0d065da72952558fd7deb806f5748c3801fd95"
        ),
        .binaryTarget(
            name: "tar",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.4/tar.xcframework.zip",
            checksum: "9bf482b29ea95bc643bfaa06b249394afed188e40482db055625f4928ffedc48"
        ),
        .binaryTarget(
            name: "text",
            url: "https://github.com/holzschu/ios_system/releases/download/v3.0.4/text.xcframework.zip",
            checksum: "2450f309d0793490136a24f9af02c42fb712b327571cb44312fe330e87a156f2"
        )
    ]
)
