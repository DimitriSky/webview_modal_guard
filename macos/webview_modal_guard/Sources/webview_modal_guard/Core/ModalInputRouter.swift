import Cocoa

/// Uses public AppKit APIs; does not alter WKWebView classes or the SDK.
public final class ModalInputRouter {
  private weak var view: NSView?
  private weak var receiver: NSResponder?
  private var tokens = Set<String>()
  private var monitor: Any?
  private var capturedButtons = Set<Int>()
  public private(set) var routed = 0
  public var leaseCount: Int { tokens.count }

  public init(view: NSView, receiver: NSResponder) {
    self.view = view
    self.receiver = receiver
  }

  deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }

  public func acquire() -> String {
    precondition(Thread.isMainThread)
    let token = UUID().uuidString
    tokens.insert(token)
    if monitor == nil {
      monitor = NSEvent.addLocalMonitorForEvents(matching: Self.eventMask) { [weak self] event in
        guard let self = self else { return event }
        return self.filter(event)
      }
    }
    return token
  }

  public func release(_ token: String) {
    precondition(Thread.isMainThread)
    tokens.remove(token)
    if tokens.isEmpty, let current = monitor {
      NSEvent.removeMonitor(current)
      monitor = nil
      capturedButtons.removeAll()
    }
  }

  /// The monitor and isolated native tests use the same decision path.
  public func filter(_ event: NSEvent) -> NSEvent? {
    guard !tokens.isEmpty, let view = view, let receiver = receiver,
          let window = view.window, event.window === window,
          Self.eventMask.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)) else { return event }
    let isDown = Self.downTypes.contains(event.type)
    let isUp = Self.upTypes.contains(event.type)
    let continuingDrag = capturedButtons.contains(event.buttonNumber) &&
      (isUp || Self.dragTypes.contains(event.type))
    let inside = view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    guard inside || continuingDrag else { return event }
    // Preserve native window buttons when Flutter extends into the title bar.
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      if let button = window.standardWindowButton(kind), !button.isHidden,
         !continuingDrag, button.bounds.contains(button.convert(event.locationInWindow, from: nil)) { return event }
    }
    if isDown { capturedButtons.insert(event.buttonNumber) }
    if isUp { capturedButtons.remove(event.buttonNumber) }
    route(event, to: receiver)
    routed += 1
    return nil // AppKit must not also dispatch to WebKit's tracking areas.
  }

  private func route(_ event: NSEvent, to receiver: NSResponder) {
    switch event.type {
    case .mouseMoved: receiver.mouseMoved(with: event)
    case .mouseEntered, .mouseExited:
      // WebView tracking notifications cannot drive Flutter's add/remove state.
      if let owner = event.trackingArea?.owner as? NSResponder, owner === receiver {
        if event.type == .mouseEntered { receiver.mouseEntered(with: event) }
        else { receiver.mouseExited(with: event) }
      }
    case .leftMouseDown: receiver.mouseDown(with: event)
    case .leftMouseUp: receiver.mouseUp(with: event)
    case .leftMouseDragged: receiver.mouseDragged(with: event)
    case .rightMouseDown: receiver.rightMouseDown(with: event)
    case .rightMouseUp: receiver.rightMouseUp(with: event)
    case .rightMouseDragged: receiver.rightMouseDragged(with: event)
    case .otherMouseDown: receiver.otherMouseDown(with: event)
    case .otherMouseUp: receiver.otherMouseUp(with: event)
    case .otherMouseDragged: receiver.otherMouseDragged(with: event)
    case .scrollWheel: receiver.scrollWheel(with: event)
    case .magnify: receiver.magnify(with: event)
    case .rotate: receiver.rotate(with: event)
    case .swipe: receiver.swipe(with: event)
    default: break
    }
  }

  public static let eventMask: NSEvent.EventTypeMask = [
    .mouseMoved, .mouseEntered, .mouseExited,
    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    .scrollWheel, .magnify, .rotate, .swipe,
  ]
  private static let downTypes: Set<NSEvent.EventType> = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
  private static let upTypes: Set<NSEvent.EventType> = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
  private static let dragTypes: Set<NSEvent.EventType> = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
}
