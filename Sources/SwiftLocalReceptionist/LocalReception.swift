//
//  LocalReception.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import Distributed
import DistributedCluster

/// Namespace for local receptionist keys and registration semantics.
public enum LocalReception {
    /// Strongly typed local registration key.
    ///
    /// Keys are string-identified at runtime and type-checked at compile time.
    /// This prevents accidental cross-type lookups under the same raw key ID.
    public struct Key<Act: DistributedActor>: Sendable, Hashable where Act.ActorSystem == ClusterSystem {
        public let id: String

        public init(_ id: String) {
            self.id = id
        }

        /// Internal key used for storage to prevent cross-type collisions for the same raw id.
        internal var storageID: String {
            "\(id)|\(String(reflecting: Act.self))"
        }
    }
}

public extension LocalReception.Key {
    /// Convenience for human-readable key construction.
    static func name(_ str: String) -> Self {
        .init(str)
    }
}

public extension LocalReception {
    /// Registration strategy when checking an actor into the local receptionist.
    enum CheckInMode: Sendable {
        /// Add this actor under the key, co-existing with existing registrations.
        case append
        /// Require this actor to be the only actor under the key.
        case unique
    }
}
