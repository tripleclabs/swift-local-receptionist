//
//  Package.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-local-receptionist",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftLocalReceptionist",
            targets: ["SwiftLocalReceptionist"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-distributed-actors.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftLocalReceptionist",
            dependencies: [
                .product(name: "DistributedCluster", package: "swift-distributed-actors")
            ]
        ),
        .testTarget(
            name: "SwiftLocalReceptionistTests",
            dependencies: [
                "SwiftLocalReceptionist",
                .product(name: "DistributedCluster", package: "swift-distributed-actors")
            ]
        )
    ]
)
