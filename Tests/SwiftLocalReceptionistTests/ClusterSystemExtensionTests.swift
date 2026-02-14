//
//  ClusterSystemExtensionTests.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import DistributedCluster
import XCTest
@testable import SwiftLocalReceptionist

/// Verifies per-system receptionist caching behavior.
final class ClusterSystemExtensionTests: XCTestCase {
    func testLocalReceptionistReturnsStableInstanceForSystem() async {
        let system = await makeTestSystem("extension-stable")
        let first = system.localReceptionist
        let second = system.localReceptionist

        XCTAssertTrue(first === second)
    }

    func testLocalReceptionistIsDistinctAcrossSystems() async {
        let firstSystem = await makeTestSystem("extension-distinct-a")
        let secondSystem = await makeTestSystem("extension-distinct-b")
        let first = firstSystem.localReceptionist
        let second = secondSystem.localReceptionist

        XCTAssertFalse(first === second)
    }
}
