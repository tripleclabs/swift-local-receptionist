//
//  ClusterSystem+LocalReceptionist.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import DistributedCluster
import Foundation

private let registryLock = NSLock()
private nonisolated(unsafe) var registries: [ObjectIdentifier: LocalReceptionist] = [:]

public extension ClusterSystem {
    /// Node-local receptionist associated with this `ClusterSystem` instance.
    ///
    /// The mapping is per in-process `ClusterSystem` identity.
    var localReceptionist: LocalReceptionist {
        let id = ObjectIdentifier(self)
        registryLock.lock()
        defer { registryLock.unlock() }

        if let existing = registries[id] {
            return existing
        }

        let receptionist = LocalReceptionist(system: self)
        registries[id] = receptionist
        return receptionist
    }
}
