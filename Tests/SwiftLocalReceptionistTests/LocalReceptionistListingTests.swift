//
//  LocalReceptionistListingTests.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import DistributedCluster
import XCTest
@testable import SwiftLocalReceptionist

/// Async stream tests for listing semantics.
final class LocalReceptionistListingTests: XCTestCase {
    func testListingEmitsInitialEmptySet() async throws {
        let system = await makeTestSystem("listing-initial")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")

        let stream = await receptionist.listing(of: key)
        var iterator = stream.makeAsyncIterator()
        let first = try await requireValue(iterator.next())
        XCTAssertTrue(first.isEmpty)
    }

    func testListingEmitsOnCheckInAndCheckOut() async throws {
        let system = await makeTestSystem("listing-mutations")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        let stream = await receptionist.listing(of: key)
        var iterator = stream.makeAsyncIterator()

        _ = try await requireValue(iterator.next())
        try await receptionist.checkIn(worker, key: key)
        let afterCheckIn = try await requireValue(iterator.next())
        XCTAssertEqual(afterCheckIn, Set([worker]))

        await receptionist.checkOut(worker, key: key)
        let afterCheckOut = try await requireValue(iterator.next())
        XCTAssertTrue(afterCheckOut.isEmpty)
    }

    func testListingEmitsOnTerminationCleanup() async throws {
        let system = await makeTestSystem("listing-termination")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        let stream = await receptionist.listing(of: key)
        var iterator = stream.makeAsyncIterator()
        _ = try await requireValue(iterator.next())

        try await receptionist.checkIn(worker, key: key)
        _ = try await requireValue(iterator.next())

        await receptionist.terminated(actor: worker.id)
        let afterTermination = try await requireValue(iterator.next())
        XCTAssertTrue(afterTermination.isEmpty)
    }

    func testListingSkipsInitialWhenConfigured() async throws {
        let system = await makeTestSystem("listing-no-initial")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        let stream = await receptionist.listing(of: key, emitInitial: false)
        var iterator = stream.makeAsyncIterator()
        try await receptionist.checkIn(worker, key: key)
        let first = try await requireValue(iterator.next())
        XCTAssertEqual(first, Set([worker]))
    }

    func testListingIgnoresUnrelatedKeyMutations() async throws {
        let system = await makeTestSystem("listing-unrelated")
        let receptionist = LocalReceptionist(system: system)
        let watched = LocalReception.Key<TestWorker>.name("watched")
        let other = LocalReception.Key<TestWorker>.name("other")
        let worker = TestWorker(actorSystem: system)

        let stream = await receptionist.listing(of: watched)
        var iterator = stream.makeAsyncIterator()
        _ = try await requireValue(iterator.next())

        try await receptionist.checkIn(worker, key: other)

        let pending = Task { await iterator.next() }
        try? await Task.sleep(for: .milliseconds(50))
        pending.cancel()
        let value = await pending.value
        XCTAssertNil(value)
    }

    private func requireValue<T>(_ value: T?) async throws -> T {
        guard let value else {
            XCTFail("Expected value but stream ended")
            throw CancellationError()
        }
        return value
    }
}
