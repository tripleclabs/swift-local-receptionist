//
//  LocalReceptionist.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import Distributed
import DistributedCluster
import Foundation

/// Errors thrown by `LocalReceptionist` operations.
public enum LocalReceptionistError: Error {
    /// Attempted `.unique` registration for a key that is already occupied.
    case duplicateRegistration(key: String)
    /// Attempted to register an actor whose node does not match this actor system's local node.
    case remoteActorRegistration(id: ClusterSystem.ActorID)
}

/// Node-local actor registry with Erlang-style check-in, lookup, and lifecycle cleanup.
///
/// This actor intentionally stores only actor IDs, then resolves to actor references at lookup time.
/// Doing so avoids retaining actor references and allows dead entries to be naturally cleaned up.
public actor LocalReceptionist {
    public typealias ActorSystem = ClusterSystem
    public typealias ActorID = ClusterSystem.ActorID

    /// Runtime store of key ID -> actor IDs.
    private var storage: [String: Set<ActorID>] = [:]
    /// Subscribers for key listing updates.
    private var observers: [String: [UUID: (Set<ActorID>) -> Void]] = [:]

    public nonisolated let actorSystem: ClusterSystem

    public init(system: ClusterSystem) {
        self.actorSystem = system
    }

    /// Register a local actor under a key.
    ///
    /// - Throws:
    ///   - `LocalReceptionistError.remoteActorRegistration` if actor is not on the local node.
    ///   - `LocalReceptionistError.duplicateRegistration` for conflicting `.unique` check-in.
    public func checkIn<Act>(
        _ actor: Act,
        key: LocalReception.Key<Act>,
        mode: LocalReception.CheckInMode = .append
    ) throws where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        // Enforce strict locality: this registry is only for actors local to this node.
        guard actor.id.node == actorSystem.cluster.node else {
            throw LocalReceptionistError.remoteActorRegistration(id: actor.id)
        }

        let keyID = key.storageID
        var currentIDs = storage[keyID] ?? []

        if mode == .unique, !currentIDs.isEmpty {
            if currentIDs.count > 1 || currentIDs.first != actor.id {
                throw LocalReceptionistError.duplicateRegistration(key: key.id)
            }
        }

        // Idempotent registration of same actor under same key.
        guard !currentIDs.contains(actor.id) else {
            return
        }

        currentIDs.insert(actor.id)
        storage[keyID] = currentIDs
        notifyObservers(for: keyID)
    }

    /// Remove a specific actor from a key.
    public func checkOut<Act>(_ actor: Act, key: LocalReception.Key<Act>)
    where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        let keyID = key.storageID
        guard var ids = storage[keyID], ids.remove(actor.id) != nil else {
            return
        }

        // Prune empty keys to keep storage compact.
        if ids.isEmpty {
            storage.removeValue(forKey: keyID)
        } else {
            storage[keyID] = ids
        }
        notifyObservers(for: keyID)
    }

    /// Resolve and return all live actors currently checked in under `key`.
    public func lookup<Act>(_ key: LocalReception.Key<Act>) -> Set<Act>
    where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        actors(for: key.storageID)
    }

    /// Stream listings with default behavior of immediate initial emission.
    public func listing<Act>(of key: LocalReception.Key<Act>) -> AsyncStream<Set<Act>>
    where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        listing(of: key, emitInitial: true)
    }

    /// Stream listings for `key`, optionally emitting the current snapshot immediately.
    public func listing<Act>(
        of key: LocalReception.Key<Act>,
        emitInitial: Bool
    ) -> AsyncStream<Set<Act>>
    where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        let keyID = key.storageID
        let initialIDs = storage[keyID] ?? []
        return AsyncStream { continuation in
            let token = UUID()

            // Store callbacks that resolve IDs per subscriber's expected actor type.
            observers[keyID, default: [:]][token] = { [actorSystem] ids in
                let resolved = ids.compactMap { id in
                    try? Act.resolve(id: id, using: actorSystem)
                }
                continuation.yield(Set(resolved))
            }

            if emitInitial {
                let resolved = initialIDs.compactMap { id in
                    try? Act.resolve(id: id, using: actorSystem)
                }
                continuation.yield(Set(resolved))
            }

            continuation.onTermination = { [weak self] _ in
                Task {
                    // Cleanup observer registration when the stream ends or is cancelled.
                    await self?.removeObserver(for: keyID, token: token)
                }
            }
        }
    }

    /// Removes a terminated actor ID from all keys.
    ///
    /// This is public so libraries can wire it to their own lifecycle/death-watch integration.
    public func terminated(actor id: ActorID) {
        for (key, ids) in storage {
            guard ids.contains(id) else {
                continue
            }

            var newIDs = ids
            newIDs.remove(id)

            if newIDs.isEmpty {
                storage.removeValue(forKey: key)
            } else {
                storage[key] = newIDs
            }
            notifyObservers(for: key)
        }
    }

    private func removeObserver(for key: String, token: UUID) {
        guard var perKey = observers[key] else {
            return
        }
        perKey.removeValue(forKey: token)
        if perKey.isEmpty {
            observers.removeValue(forKey: key)
        } else {
            observers[key] = perKey
        }
    }

    private func notifyObservers(for key: String) {
        let ids = storage[key] ?? []
        let callbacks = observers[key]?.values
        guard let callbacks else {
            return
        }
        for callback in callbacks {
            callback(ids)
        }
    }

    private func actors<Act>(for key: String) -> Set<Act>
    where Act: DistributedActor, Act.ActorSystem == ClusterSystem {
        guard let ids = storage[key] else {
            return []
        }
        let resolved = ids.compactMap { id in
            try? Act.resolve(id: id, using: actorSystem)
        }
        return Set(resolved)
    }
}
