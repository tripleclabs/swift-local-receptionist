<!--
  README.md
  SwiftLocalReceptionist

  Created on 2026-02-14
  Copyright Triple C Labs GmbH
-->

# SwiftLocalReceptionist

Node-local receptionist for `swift-distributed-actors` that provides Erlang-style registration and lookup for local distributed actors, with lifecycle cleanup and async listings.

## Why This Exists

`DistributedReceptionist` is cluster-wide and CRDT/gossip-based.  
`SwiftLocalReceptionist` is intentionally local:

- no network overhead
- explicit local-node scoping
- singleton (`.unique`) and pool (`.append`) registration modes
- typed keys for safer lookup

This is useful for "service per node" patterns (config actor, local cache actor, sidecar bridge actor) where each node has one local implementation but your app still uses distributed actors for calling.

## Package

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-distributed-actors.git", branch: "main")
]
```

Then add this library target (`SwiftLocalReceptionist`) as a dependency in your package.

## Public API

- `LocalReception.Key<Act>`
- `LocalReception.CheckInMode` (`.append`, `.unique`)
- `LocalReceptionistError`
- `LocalReceptionist`
  - `checkIn(_:key:mode:)`
  - `checkOut(_:key:)`
  - `lookup(_:)`
  - `listing(of:)`
  - `listing(of:emitInitial:)`
- `ClusterSystem.localReceptionist`

## Quick Start

### 1. Define keys

```swift
import DistributedCluster
import SwiftLocalReceptionist

extension LocalReception.Key where Act == NodeConfigActor {
    static let nodeConfig = Self.name("my-lib.node-config")
}
```

Use namespaced IDs (`my-lib.*`) to avoid collisions with host app or other libraries.

### 2. Register local actor

```swift
distributed actor NodeConfigActor {
    typealias ActorSystem = ClusterSystem
}

func bootstrap(system: ClusterSystem) async throws {
    let actor = NodeConfigActor(actorSystem: system)
    try await system.localReceptionist.checkIn(actor, key: .nodeConfig, mode: .unique)
}
```

### 3. Lookup from app/library

```swift
func resolveConfig(system: ClusterSystem) async -> NodeConfigActor? {
    await system.localReceptionist.lookup(.nodeConfig).first
}
```

## Semantics

### Locality

`checkIn` validates that actor node == `system.cluster.node`.  
Remote actors are rejected with `LocalReceptionistError.remoteActorRegistration`.

### Unique mode

`.unique` allows one actor per key:

- succeeds if key empty
- succeeds if same actor already registered (idempotent)
- throws `duplicateRegistration` for conflicting registrations

### Lookup behavior

Registry stores actor IDs and resolves at lookup/listing time, so it does not strongly retain actor references.

### Lifecycle cleanup

`LocalReceptionist` exposes `terminated(actor:)` so libraries can wire actor death events from their own lifecycle integration.  
When invoked, IDs are removed from all affected keys and listing observers are notified.

### Listing streams

- `listing(of:)` emits initial snapshot immediately, then emits on every key mutation
- `listing(of:emitInitial: false)` emits only after the first mutation
- stream termination removes observer registration

## BYO `ClusterSystem` Integration

This library works well when a host app owns the cluster system:

1. host app creates `ClusterSystem`
2. library receives that system and registers local actors under well-known keys
3. host app and library both resolve via `system.localReceptionist`

Important: both sides must use the same `ClusterSystem` instance identity.

## Collision and Ownership Guidelines

If host app and multiple libraries all use local receptionist on the same system:

- namespace keys (`com.myapp.*`, `com.otherlib.*`)
- publish key constants in library public API
- document ownership for `.unique` keys
- treat registrations as part of bootstrap lifecycle contract

## Testing

Current test suite covers:

- key equality/hashing
- append and unique registration semantics
- idempotency paths
- remote actor rejection
- lookup and type isolation
- checkout behavior
- termination cleanup
- listing stream semantics
- per-system receptionist caching behavior

Run:

```bash
swift test
swift test --enable-code-coverage
```

## CI and Coverage

CI workflow is at:

- `/Users/johnmaxwell/src/3clabs/swift-local-receptionist/.github/workflows/ci.yml`

It:

- runs tests with coverage
- enforces minimum 85%
- prints per-file coverage summary for library source files

## Maintainer Notes

### Concurrency model

- `LocalReceptionist` is an actor; mutable registry state is isolated.
- global map in `ClusterSystem+LocalReceptionist.swift` is protected by `NSLock`.

### Evolution guidance

When extending API:

- prefer additive overloads
- keep typed key model intact
- avoid exposing mutable internals

When changing stream behavior:

- preserve deterministic ordering (initial snapshot, then mutations)
- keep cancellation cleanup strict to avoid observer leaks

### Versioning

- breaking public API changes should be major version bumps
- behavioral changes to uniqueness/listing semantics should be explicitly documented in changelog
