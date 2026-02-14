//
//  LocalReceptionistTests.swift
//  SwiftLocalReceptionist
//
//  Created on 2026-02-14
//  Copyright Triple C Labs GmbH
//

import DistributedCluster
import XCTest
@testable import SwiftLocalReceptionist

/// Core unit tests for registration, lookup, uniqueness, and lifecycle cleanup.
final class LocalReceptionistTests: XCTestCase {
    func testKeyHashAndEquality() {
        let lhs = LocalReception.Key<TestWorker>.name("workers")
        let rhs = LocalReception.Key<TestWorker>.name("workers")
        let other = LocalReception.Key<TestWorker>.name("other")

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, other)
    }

    func testAppendRegistrationAndLookup() async throws {
        let system = await makeTestSystem("append-registration")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: key)
        let result = await receptionist.lookup(key)
        XCTAssertEqual(result, Set([worker]))
    }

    func testAppendRegistrationIsIdempotent() async throws {
        let system = await makeTestSystem("append-idempotent")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: key, mode: .append)
        try await receptionist.checkIn(worker, key: key, mode: .append)
        let result = await receptionist.lookup(key)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result, Set([worker]))
    }

    func testAppendRegistrationAllowsMultipleActors() async throws {
        let system = await makeTestSystem("append-multiple")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let first = TestWorker(actorSystem: system)
        let second = TestWorker(actorSystem: system)

        try await receptionist.checkIn(first, key: key, mode: .append)
        try await receptionist.checkIn(second, key: key, mode: .append)

        let result = await receptionist.lookup(key)
        XCTAssertEqual(result, Set([first, second]))
    }

    func testUniqueRegistrationAllowsSameActorIdempotently() async throws {
        let system = await makeTestSystem("unique-idempotent")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("singleton")
        let worker = TestWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: key, mode: .unique)
        try await receptionist.checkIn(worker, key: key, mode: .unique)
        let result = await receptionist.lookup(key)
        XCTAssertEqual(result, Set([worker]))
    }

    func testUniqueRegistrationRejectsDifferentActor() async throws {
        let system = await makeTestSystem("unique-reject")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("singleton")
        let first = TestWorker(actorSystem: system)
        let second = TestWorker(actorSystem: system)

        try await receptionist.checkIn(first, key: key, mode: .unique)

        do {
            try await receptionist.checkIn(second, key: key, mode: .unique)
            XCTFail("Expected duplicate registration")
        } catch let error as LocalReceptionistError {
            if case .duplicateRegistration(let conflictKey) = error {
                XCTAssertEqual(conflictKey, key.id)
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUniqueRegistrationRejectsWhenMultipleActorsAlreadyRegistered() async throws {
        let system = await makeTestSystem("unique-reject-multiple")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("singleton")
        let first = TestWorker(actorSystem: system)
        let second = TestWorker(actorSystem: system)

        try await receptionist.checkIn(first, key: key, mode: .append)
        try await receptionist.checkIn(second, key: key, mode: .append)

        do {
            try await receptionist.checkIn(first, key: key, mode: .unique)
            XCTFail("Expected duplicate registration")
        } catch let error as LocalReceptionistError {
            if case .duplicateRegistration(let conflictKey) = error {
                XCTAssertEqual(conflictKey, key.id)
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRemoteActorRegistrationRejected() async throws {
        let localSystem = await makeTestSystem("local-system")
        let remoteSystem = await makeTestSystem("remote-system")
        let receptionist = LocalReceptionist(system: localSystem)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let remoteActor = TestWorker(actorSystem: remoteSystem)

        do {
            try await receptionist.checkIn(remoteActor, key: key, mode: .append)
            XCTFail("Expected remote registration rejection")
        } catch let error as LocalReceptionistError {
            switch error {
            case .remoteActorRegistration(let id):
                XCTAssertEqual(id, remoteActor.id)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLookupReturnsEmptyForMissingKey() async throws {
        let system = await makeTestSystem("lookup-empty")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("missing")

        let result = await receptionist.lookup(key)
        XCTAssertTrue(result.isEmpty)
    }

    func testTypeSpecificKeyIsolation() async throws {
        let system = await makeTestSystem("type-isolation")
        let receptionist = LocalReceptionist(system: system)
        let workerKey = LocalReception.Key<TestWorker>.name("shared")
        let anotherKey = LocalReception.Key<AnotherWorker>.name("shared")
        let worker = TestWorker(actorSystem: system)
        let another = AnotherWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: workerKey)
        try await receptionist.checkIn(another, key: anotherKey)

        let workerResult = await receptionist.lookup(workerKey)
        let anotherResult = await receptionist.lookup(anotherKey)
        XCTAssertEqual(workerResult, Set([worker]))
        XCTAssertEqual(anotherResult, Set([another]))
    }

    func testCheckoutRemovesActor() async throws {
        let system = await makeTestSystem("checkout-removes")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: key)
        await receptionist.checkOut(worker, key: key)
        let result = await receptionist.lookup(key)
        XCTAssertTrue(result.isEmpty)
    }

    func testCheckoutMissingActorIsNoop() async throws {
        let system = await makeTestSystem("checkout-noop")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        await receptionist.checkOut(worker, key: key)
        let result = await receptionist.lookup(key)
        XCTAssertTrue(result.isEmpty)
    }

    func testTerminatedRemovesActorFromAllKeys() async throws {
        let system = await makeTestSystem("terminated-cleanup")
        let receptionist = LocalReceptionist(system: system)
        let firstKey = LocalReception.Key<TestWorker>.name("first")
        let secondKey = LocalReception.Key<TestWorker>.name("second")
        let worker = TestWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: firstKey)
        try await receptionist.checkIn(worker, key: secondKey)

        await receptionist.terminated(actor: worker.id)
        let firstResult = await receptionist.lookup(firstKey)
        let secondResult = await receptionist.lookup(secondKey)
        XCTAssertTrue(firstResult.isEmpty)
        XCTAssertTrue(secondResult.isEmpty)
    }

    func testTerminatedUnknownActorIsNoop() async throws {
        let system = await makeTestSystem("terminated-unknown")
        let receptionist = LocalReceptionist(system: system)
        let key = LocalReception.Key<TestWorker>.name("workers")
        let worker = TestWorker(actorSystem: system)

        try await receptionist.checkIn(worker, key: key)
        let unknown = TestWorker(actorSystem: system)
        await receptionist.terminated(actor: unknown.id)

        let result = await receptionist.lookup(key)
        XCTAssertEqual(result, Set([worker]))
    }
}
