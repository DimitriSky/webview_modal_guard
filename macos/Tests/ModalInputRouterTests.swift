import Cocoa
import XCTest
@testable import WebViewModalGuardCore

final class ModalInputRouterTests: XCTestCase {
  // CG-created events have no AppKit dispatch window. Supply only the window
  // and local position, delegating type/button queries to the native event.
  private final class ScopedEvent: NSEvent {
    var source: NSEvent!
    weak var scopedWindow: NSWindow?
    var point = NSPoint.zero
    override var type: NSEvent.EventType { source.type }
    override var buttonNumber: Int { source.buttonNumber }
    override var window: NSWindow? { scopedWindow }
    override var locationInWindow: NSPoint { point }
  }
  private final class Receiver: NSResponder {
    var events: [NSEvent.EventType] = []
    override func mouseMoved(with event: NSEvent) { events.append(event.type) }
    override func mouseDown(with event: NSEvent) { events.append(event.type) }
    override func mouseUp(with event: NSEvent) { events.append(event.type) }
    override func mouseDragged(with event: NSEvent) { events.append(event.type) }
    override func rightMouseDown(with event: NSEvent) { events.append(event.type) }
    override func rightMouseUp(with event: NSEvent) { events.append(event.type) }
    override func rightMouseDragged(with event: NSEvent) { events.append(event.type) }
    override func otherMouseDown(with event: NSEvent) { events.append(event.type) }
    override func otherMouseUp(with event: NSEvent) { events.append(event.type) }
    override func otherMouseDragged(with event: NSEvent) { events.append(event.type) }
    override func scrollWheel(with event: NSEvent) { events.append(event.type) }
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

  private func scoped(_ cg: CGEvent, in window: NSWindow,
                      at point: NSPoint = NSPoint(x: 50, y: 50)) -> NSEvent {
    let e = ScopedEvent()
    e.source = NSEvent(cgEvent: cg)!
    e.scopedWindow = window
    e.point = point
    return e
  }

  private func button(_ window: NSWindow, _ type: CGEventType, _ button: CGMouseButton,
                      at point: NSPoint = NSPoint(x: 50, y: 50)) -> NSEvent {
    scoped(CGEvent(mouseEventSource: nil, mouseType: type,
                   mouseCursorPosition: .zero, mouseButton: button)!, in: window, at: point)
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

  func testDifferentButtonsKeepIndependentCaptureOutsideView() {
    let window = window(), receiver = Receiver()
    let flutter = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    window.contentView!.addSubview(flutter)
    let router = ModalInputRouter(view: flutter, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    let outside = NSPoint(x: 200, y: 200)
    XCTAssertNil(router.filter(button(window, .leftMouseDown, .left)))
    XCTAssertNil(router.filter(button(window, .rightMouseDown, .right)))
    XCTAssertNil(router.filter(button(window, .leftMouseUp, .left, at: outside)))
    XCTAssertNil(router.filter(button(window, .rightMouseDragged, .right, at: outside)))
    XCTAssertNil(router.filter(button(window, .rightMouseUp, .right, at: outside)))
    let subsequent = button(window, .rightMouseDragged, .right, at: outside)
    XCTAssertTrue(router.filter(subsequent) === subsequent)
    XCTAssertEqual(receiver.events, [.leftMouseDown, .rightMouseDown, .leftMouseUp,
                                     .rightMouseDragged, .rightMouseUp])
  }

  func testScrollWheelRoutesOnceAndNeverContinuesAButtonDragOutsideView() {
    let window = window(), receiver = Receiver()
    let flutter = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    window.contentView!.addSubview(flutter)
    let router = ModalInputRouter(view: flutter, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                     wheel1: 12, wheel2: 0, wheel3: 0)!
    let e = scoped(cg, in: window)
    XCTAssertTrue(e.window === window)
    XCTAssertNil(router.filter(e))
    XCTAssertEqual(receiver.events, [.scrollWheel])
    XCTAssertNil(router.filter(event(window, .leftMouseDown)))
    let outside = scoped(cg, in: window, at: NSPoint(x: 200, y: 200))
    XCTAssertTrue(router.filter(outside) === outside)
    XCTAssertEqual(receiver.events, [.scrollWheel, .leftMouseDown])
  }

  func testNativeWindowButtonsRemainAvailableWhenFlutterExtendsIntoTitlebar() {
    let window = window(), receiver = Receiver()
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    let view = window.contentView!
    let router = ModalInputRouter(view: view, receiver: receiver)
    let token = router.acquire()
    defer { router.release(token) }
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      let button = window.standardWindowButton(kind)!
      XCTAssertFalse(button.isHidden)
      let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
      XCTAssertTrue(view.bounds.contains(view.convert(point, from: nil)))
      let e = event(window, .leftMouseDown, at: point)
      XCTAssertTrue(router.filter(e) === e)
    }
    XCTAssertTrue(receiver.events.isEmpty)
    XCTAssertEqual(router.routed, 0)
  }
}
