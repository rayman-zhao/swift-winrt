import WinSDK
import XCTest
import test_component
import Foundation
import WindowsFoundation

class AsyncTests : XCTestCase {
  public func testAwaitAlreadyCompleted() throws {
    let asyncOperation = try AsyncMethods.getCompletedAsync(42)!
    XCTAssertEqual(asyncOperation.status, .completed)
    let result = try asyncBlock(timeout: 1) { try await asyncOperation.get() }
    XCTAssertEqual(result, 42)
  }

  public func testAwaitAlreadyFailed() throws {
    let asyncOperation = try AsyncMethods.getCompletedWithErrorAsync(E_LAYOUTCYCLE)!
    XCTAssertEqual(asyncOperation.status, .error)
    do {
      _ = try asyncBlock(timeout: 1) { try await asyncOperation.get() }
      XCTFail("Expected an error to be thrown")
    } catch let error as WindowsFoundation.Error {
      XCTAssertEqual(error.hr, E_LAYOUTCYCLE)
    }
  }

  public func testAwaitCompletionWithSuspension() throws {
    let asyncOperation = try AsyncMethods.getPendingAsync()!
    runAfter(delay: 0.05) { try? asyncOperation.complete(42) }
    let result = try asyncBlock(timeout: 1) { try await asyncOperation.get() }
    XCTAssertEqual(asyncOperation.status, .completed)
    XCTAssertEqual(result, 42)
  }

  public func testAwaitFailureWithSuspension() throws {
    let asyncOperation = try AsyncMethods.getPendingAsync()!
    runAfter(delay: 0.05) { try? asyncOperation.completeWithError(E_LAYOUTCYCLE) }
    do {
      _ = try asyncBlock(timeout: 1) { try await asyncOperation.get() }
      XCTFail("Expected an error to be thrown")
    } catch let error as WindowsFoundation.Error {
      XCTAssertEqual(error.hr, E_LAYOUTCYCLE)
    }
  }

  /// Runs a block asynchronously after a delay has elapsed
  private func runAfter(delay: TimeInterval, body: @escaping @Sendable () -> Void) {
    Task {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      body()
    }
  }

  // written by the async task and read after WaitForSingleObject succeeds, so the
  // Win32 event provides the necessary ordering
  private final class BoxedResult<T>: @unchecked Sendable {
    var result: Result<T, any Swift.Error>? = nil
  }

  /// Synchronously runs an async block with a timeout
    // HANDLE is a raw pointer, which isn't Sendable; box it so the task can signal it
    private struct EventHandleBox: @unchecked Sendable { let handle: WinSDK.HANDLE? }

    private func asyncBlock<Result>(timeout: TimeInterval, body: @escaping @Sendable () async throws -> Result) throws -> Result {
    guard let event = WinSDK.CreateEventA(nil, false, false, nil) else {
      XCTFail("Failed to create event")
      throw WindowsFoundation.Error(hr: E_FAIL)
    }
    defer { WinSDK.CloseHandle(event) }

    let asyncResult = BoxedResult<Result>()
    let eventBox = EventHandleBox(handle: event)
    Task { @Sendable in
      do {
        asyncResult.result = .success(try await body())
      } catch {
        asyncResult.result = .failure(error)
      }
      WinSDK.SetEvent(eventBox.handle)
    }

    switch WinSDK.WaitForSingleObject(event, /* dwMilliseconds: */ DWORD(timeout * 1000)) {
      case WAIT_OBJECT_0: break
      case DWORD(WAIT_TIMEOUT):
        XCTFail("Timed out waiting for async task to complete")
        throw WindowsFoundation.Error(hr: E_FAIL)
      default:
        XCTFail("Failed to wait for async task to complete")
        throw WindowsFoundation.Error(hr: E_FAIL)
    }

    return try asyncResult.result!.get()
  }
}

nonisolated(unsafe) var asyncTests: [XCTestCaseEntry] = [
  testCase([
    ("testAwaitAlreadyCompleted", AsyncTests.testAwaitAlreadyCompleted),
    ("testAwaitAlreadyFailed", AsyncTests.testAwaitAlreadyFailed),
    ("testAwaitCompletionWithSuspension", AsyncTests.testAwaitCompletionWithSuspension),
    ("testAwaitFailureWithSuspension", AsyncTests.testAwaitFailureWithSuspension),
  ])
]
