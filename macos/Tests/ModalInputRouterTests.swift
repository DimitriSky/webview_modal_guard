import Cocoa
import XCTest
@testable import WebViewModalGuardCore

final class ModalInputRouterTests: XCTestCase {
  private final class Receiver: NSResponder {
    var events: [NSEvent.EventType] = []
    override func mouseMoved(with event: NSEvent) { events.append(event.type) }
    override func mouseDown(with event: NSEvent) { events.append(event.type) }
    override func mouseUp(with event: NSEvent) { events.append(event.type) }
    override func mouseDragged(with event: NSEvent) { events.append(event.type) }
    override func rightMouseDown(with event: NSEvent) { events.append(event.type) }
    override func rightMouseUp(with event: NSEvent) { events.append(event.type) }
    override func otherMouseDown(with event: NSEvent) { events.append(event.type) }
    override func otherMouseUp(with event: NSEvent) { events.append(event.type) }
  }
  private func window() -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    addTeardownBlock { window.close() }
    return window
  }
  private func event(_ window: NSWindow, _ type: NSEvent.EventType = .mouseMoved,
                     at point: NSPoint = NSPoint(x: 50, y: 50)) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
  }

  func testNoLeasePassesOriginalEventUnchanged() {
    let window = window(), receiver = Receiver()
    let router = ModalInputRouter(view: window.contentView!, receiver: receiver)
    let e = event(window)
    XCTAssertTrue(router.filter(e) === e)
    XCTAssertTrue(receiver.events.isEmpty)
  }

  func testNestedLeasesAndUnknownReleaseCannotReenableWebKitEarly() {
    let window = window(), receiver = Receiver()
    let router = ModalInputRouter(view: window.contentView!, receiver: receiver)
    let a = router.acquire(), b = router.acquire()
    router.release("unknown")
    XCTAssertEqual(router.leaseCount, 2)
    router.release(a)
    router.release(a)
    XCTAssertNil(router.filter(event(window)))
    XCTAssertEqual(receiver.events, [.mouseMoved])
    router.release(b)
    let e = event(window)
    XCTAssertTrue(router.filter(e) === e)
  }

  func testOtherWindowAndAreaOutsideFlutterAreUntouched() {
    let window = window(), other = self.window(), receiver = Receiver()
    let flutter = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    window.contentView!.addSubview(flutter)
    let router = ModalInputRouter(view: flutter, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    for e in [event(other), event(window, at: NSPoint(x: 200, y: 200))] {
      XCTAssertTrue(router.filter(e) === e)
    }
    XCTAssertTrue(receiver.events.isEmpty)
  }

  func testMouseSequencesAreForwardedOnceOnlyToFlutter() {
    let window = window(), receiver = Receiver()
    let router = ModalInputRouter(view: window.contentView!, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    let types: [NSEvent.EventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
    for type in types { XCTAssertNil(router.filter(event(window, type))) }
    XCTAssertEqual(receiver.events, types)
    XCTAssertEqual(router.routed, types.count)
  }

  func testDetachedViewDoesNotConsumeEvents() {
    let window = window(), receiver = Receiver()
    let flutter = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    window.contentView!.addSubview(flutter)
    let router = ModalInputRouter(view: flutter, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    flutter.removeFromSuperview()
    let e = event(window)
    XCTAssertTrue(router.filter(e) === e)
  }

  func testDragStartedInFlutterReceivesReleaseOutsideViewThenStopsCapturing() {
    let window = window(), receiver = Receiver()
    let flutter = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    window.contentView!.addSubview(flutter)
    let router = ModalInputRouter(view: flutter, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    XCTAssertNil(router.filter(event(window, .leftMouseDown)))
    let outside = NSPoint(x: 200, y: 200)
    XCTAssertNil(router.filter(event(window, .leftMouseDragged, at: outside)))
    XCTAssertNil(router.filter(event(window, .leftMouseUp, at: outside)))
    let subsequent = event(window, .leftMouseDragged, at: outside)
    XCTAssertTrue(router.filter(subsequent) === subsequent)
    XCTAssertEqual(receiver.events, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
  }

  func testKeyboardEventsStayInExistingResponderPath() {
    let window = window(), receiver = Receiver()
    let router = ModalInputRouter(view: window.contentView!, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    let e = NSEvent.keyEvent(with: .keyDown, location: NSPoint(x: 50, y: 50), modifierFlags: .command,
      timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "a",
      charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
    XCTAssertTrue(router.filter(e) === e)
    XCTAssertTrue(receiver.events.isEmpty)
  }

  func testWebKitTrackingNotificationsDoNotForwardForeignHoverToFlutter() {
    let window = window(), receiver = Receiver()
    let router = ModalInputRouter(view: window.contentView!, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    for type in [NSEvent.EventType.mouseEntered, .mouseExited] {
      let e = NSEvent.enterExitEvent(with: type, location: NSPoint(x: 50, y: 50),
        modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, trackingNumber: 1, userData: nil)!
      XCTAssertNil(router.filter(e))
    }
    XCTAssertTrue(receiver.events.isEmpty)
    XCTAssertEqual(router.routed, 2)
  }
}
