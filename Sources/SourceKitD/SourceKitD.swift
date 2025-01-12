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

@_exported import Csourcekitd
import Dispatch
import Foundation
import SKSupport

/// Access to sourcekitd API, taking care of initialization, shutdown, and notification handler
/// multiplexing.
///
/// *Users* of this protocol should not call the api functions `initialize`, `shutdown`, or
/// `set_notification_handler`, which are global state managed internally by this class.
///
/// *Implementors* are expected to handle initialization and shutdown, e.g. during `init` and
/// `deinit` or by wrapping an existing sourcekitd session that outlives this object.
public protocol SourceKitD: AnyObject {
  /// The sourcekitd API functions.
  var api: sourcekitd_api_functions_t { get }

  /// Convenience for accessing known keys.
  var keys: sourcekitd_api_keys { get }

  /// Convenience for accessing known keys.
  var requests: sourcekitd_api_requests { get }

  /// Convenience for accessing known keys.
  var values: sourcekitd_api_values { get }

  /// Adds a new notification handler, which will be weakly referenced.
  func addNotificationHandler(_ handler: SKDNotificationHandler)

  /// Removes a previously registered notification handler.
  func removeNotificationHandler(_ handler: SKDNotificationHandler)

  /// Log the given request.
  ///
  /// This log call is issued during normal operation. It is acceptable for the logger to truncate the log message
  /// to achieve good performance.
  func log(request: SKDRequestDictionary)

  /// Log the given request and file contents, ensuring they do not get truncated.
  ///
  /// This log call is used when a request has crashed. In this case we want the log to contain the entire request to be
  /// able to reproduce it.
  func log(crashedRequest: SKDRequestDictionary, fileContents: String?)

  /// Log the given response.
  ///
  /// This log call is issued during normal operation. It is acceptable for the logger to truncate the log message
  /// to achieve good performance.
  func log(response: SKDResponse)
}

public enum SKDError: Error, Equatable {
  /// The service has crashed.
  case connectionInterrupted

  /// The request was unknown or had an invalid or missing parameter.
  case requestInvalid(String)

  /// The request failed.
  case requestFailed(String)

  /// The request was cancelled.
  case requestCancelled

  /// Loading a required symbol from the sourcekitd library failed.
  case missingRequiredSymbol(String)
}

extension SourceKitD {

  // MARK: - Convenience API for requests.

  /// - Parameters:
  ///   - req: The request to send to sourcekitd.
  ///   - fileContents: The contents of the file that the request operates on. If sourcekitd crashes, the file contents
  ///     will be logged.
  public func send(_ req: SKDRequestDictionary, fileContents: String?) async throws -> SKDResponseDictionary {
    log(request: req)

    let sourcekitdResponse: SKDResponse = try await withCancellableCheckedThrowingContinuation { continuation in
      var handle: sourcekitd_api_request_handle_t? = nil
      api.send_request(req.dict, &handle) { response in
        continuation.resume(returning: SKDResponse(response!, sourcekitd: self))
      }
      return handle
    } cancel: { handle in
      if let handle {
        api.cancel_request(handle)
      }
    }

    log(response: sourcekitdResponse)

    guard let dict = sourcekitdResponse.value else {
      if sourcekitdResponse.error == .connectionInterrupted {
        log(crashedRequest: req, fileContents: fileContents)
      }
      throw sourcekitdResponse.error!
    }

    return dict
  }
}

/// A sourcekitd notification handler in a class to allow it to be uniquely referenced.
public protocol SKDNotificationHandler: AnyObject {
  func notification(_: SKDResponse) -> Void
}
