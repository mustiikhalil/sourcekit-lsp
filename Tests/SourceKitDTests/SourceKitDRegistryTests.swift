//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKitD
import TSCBasic
import XCTest

final class SourceKitDRegistryTests: XCTestCase {

  func testAdd() throws {
    let registry = SourceKitDRegistry()

    let a = try FakeSourceKitD.getOrCreate(AbsolutePath(validating: "/a"), in: registry)
    let b = try FakeSourceKitD.getOrCreate(AbsolutePath(validating: "/b"), in: registry)
    let a2 = try FakeSourceKitD.getOrCreate(AbsolutePath(validating: "/a"), in: registry)

    XCTAssert(a === a2)
    XCTAssert(a !== b)
  }

  func testRemove() throws {
    let registry = SourceKitDRegistry()

    let a = FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry)
    XCTAssert(registry.remove(try AbsolutePath(validating: "/a")) === a)
    XCTAssertNil(registry.remove(try AbsolutePath(validating: "/a")))
  }

  func testRemoveResurrect() throws {
    let registry = SourceKitDRegistry()

    @inline(never)
    func scope(registry: SourceKitDRegistry) throws -> Int {
      let a = FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry)

      XCTAssert(a === FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry))
      XCTAssert(registry.remove(try AbsolutePath(validating: "/a")) === a)
      // Resurrected.
      XCTAssert(a === FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry))
      // Remove again.
      XCTAssert(registry.remove(try AbsolutePath(validating: "/a")) === a)
      return (a as! FakeSourceKitD).token
    }

    let id = try scope(registry: registry)
    let a2 = FakeSourceKitD.getOrCreate(try AbsolutePath(validating: "/a"), in: registry)
    XCTAssertNotEqual(id, (a2 as! FakeSourceKitD).token)
  }
}

private var nextToken = 0

final class FakeSourceKitD: SourceKitD {
  let token: Int
  var api: sourcekitd_api_functions_t { fatalError() }
  var keys: sourcekitd_api_keys { fatalError() }
  var requests: sourcekitd_api_requests { fatalError() }
  var values: sourcekitd_api_values { fatalError() }
  func addNotificationHandler(_ handler: SKDNotificationHandler) { fatalError() }
  func removeNotificationHandler(_ handler: SKDNotificationHandler) { fatalError() }
  private init() {
    token = nextToken
    nextToken += 1
  }

  static func getOrCreate(_ path: AbsolutePath, in registry: SourceKitDRegistry) -> SourceKitD {
    return registry.getOrAdd(path, create: { Self.init() })
  }

  public func log(request: SKDRequestDictionary) {}
  public func log(response: SKDResponse) {}
  public func log(crashedRequest: SKDRequestDictionary, fileContents: String?) {}
}
