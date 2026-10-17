import WinSDK
import XCTest
import test_component
import Foundation
import WindowsFoundation

extension Array where Element == Disposable {
  mutating func dispose() {
    for item in self {
      item.dispose()
    }
    self.removeAll(keepingCapacity: true)
  }
}

// Event handlers are @Sendable (they fire on arbitrary threads), so tests use these
// boxes to keep mutable expectations readable from the handlers.
private final class MutableCounter: @unchecked Sendable {
  var value = 0
}

private final class MutableBox<T>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}

class EventTests : XCTestCase {
  public func testEventsOnInstance() throws {
    let simple = Simple()
    let count = MutableCounter()

    var disposable = [Disposable]()

    disposable.append(simple.signalEvent.addHandler {
      count.value += 1
    })

    try simple.fireEvent()
    XCTAssertEqual(count.value, 1)

    try simple.fireEvent()
    XCTAssertEqual(count.value, 2)

    // dispose of the handlers and make sure we
    // aren't getting more events
    disposable.dispose()

    try simple.fireEvent()
    XCTAssertEqual(count.value, 2)

    // hookup the handlers again and make sure it works, just to be safe
    simple.signalEvent.addHandler {
      count.value += 1
    }

    try simple.fireEvent()
    XCTAssertEqual(count.value, 3)
  }

  public func testStaticEvent() throws {
    let static_count = MutableCounter()

    var disposable = [Disposable]()

    disposable.append(Simple.staticEvent.addHandler { (_,_) in
      static_count.value += 1
    })

    try Simple.fireStaticEvent()
    XCTAssertEqual(static_count.value, 1)
    try Simple.fireStaticEvent()
    XCTAssertEqual(static_count.value, 2)

    // dispose of the handlers and make sure we
    // aren't getting more events
    disposable.dispose()

    try Simple.fireStaticEvent()
    XCTAssertEqual(static_count.value, 2)

    disposable.append(Simple.staticEvent.addHandler { (_,_) in
      static_count.value += 1
    })

    try Simple.fireStaticEvent()
    XCTAssertEqual(static_count.value, 3)
  }

  public func testSwiftImplementedEventWithWinRTListener() throws {
    let delegate = MyImplementableDelegate()
    let tester = EventTester(delegate)
    try tester.subscribe()
    var expectedResult = "fired once"
    delegate.fireEvent(expectedResult)
    XCTAssertEqual(tester.count, 1)
    XCTAssertEqual(try tester.getResult(), expectedResult)

    expectedResult = "fired twice"
    delegate.fireEvent(expectedResult)
    XCTAssertEqual(tester.count, 2)
    XCTAssertEqual(try tester.getResult(), expectedResult)

    try tester.unsubscribe()
    delegate.fireEvent("unexpected shouldn't get this")
    XCTAssertEqual(tester.count, 2)
    XCTAssertEqual(try tester.getResult(), expectedResult)

    try tester.subscribe()
    expectedResult = "fired trice"
    delegate.fireEvent(expectedResult)
    XCTAssertEqual(tester.count, 3)
    XCTAssertEqual(try tester.getResult(), expectedResult)
  }

public func testSwiftImplementedEventWithSwiftListener() throws {
    let delegate = MyImplementableDelegate()
    let count = MutableCounter()
    let expectedResult = MutableBox("fired once")
    let disposer = delegate.implementableEvent.addHandler{
      count.value += 1
      XCTAssertEqual($0, expectedResult.value)
    }

    delegate.fireEvent(expectedResult.value)
    XCTAssertEqual(count.value, 1)
    expectedResult.value = "fired twice"
    delegate.fireEvent(expectedResult.value)
    XCTAssertEqual(count.value, 2)

    disposer.dispose()
    delegate.fireEvent("unexpected shouldn't get this")
    XCTAssertEqual(count.value, 2)

    delegate.implementableEvent.addHandler{
      count.value += 1
      XCTAssertEqual($0, expectedResult.value)
    }
    expectedResult.value = "fired trice"
    delegate.fireEvent(expectedResult.value)
    XCTAssertEqual(count.value, 3)
  }
}

nonisolated(unsafe) var eventTests: [XCTestCaseEntry] = [
  testCase([
    ("EventsOnInstance", EventTests.testEventsOnInstance),
    ("StaticEvent", EventTests.testStaticEvent),
    ("SwiftImplementedEventWithWinRTListener", EventTests.testSwiftImplementedEventWithWinRTListener),
    ("SwiftImplementedEventWithSwiftListener", EventTests.testSwiftImplementedEventWithSwiftListener),
  ])
]
