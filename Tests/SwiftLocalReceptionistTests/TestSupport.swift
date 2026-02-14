//
//  TestSupport.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import DistributedCluster
import Logging

/// Creates a cluster system configured for low-noise test execution.
///
/// - Uses a unique high port per test system to avoid address collisions.
/// - Sets log level to `critical` and disables optional trace/membership logging.
func makeTestSystem(_ name: String) async -> ClusterSystem {
    let port = await TestPortAllocator.shared.next()
    return await ClusterSystem(name) { settings in
        settings.bindPort = port
        settings.logging.logLevel = .critical
        settings.logMembershipChanges = nil
        settings.traceLogLevel = nil
    }
}

private actor TestPortAllocator {
    static let shared = TestPortAllocator()
    private var nextPort = 18000

    func next() -> Int {
        defer { nextPort += 1 }
        return nextPort
    }
}
