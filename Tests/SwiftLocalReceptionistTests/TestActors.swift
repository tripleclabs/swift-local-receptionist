//
//  TestActors.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import Distributed
import DistributedCluster

/// Test-only distributed actor used across receptionist test cases.
distributed actor TestWorker {
    typealias ActorSystem = ClusterSystem
}

/// Alternate actor type used to validate key/type isolation behavior.
distributed actor AnotherWorker {
    typealias ActorSystem = ClusterSystem
}
