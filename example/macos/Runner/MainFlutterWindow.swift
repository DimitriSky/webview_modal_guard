import Cocoa
import FlutterMacOS
import WebKit
import webview_key_guard

class MainFlutterWindow: WebViewKeyGuardWindow {
  private var diagnostics: LabDiagnostics?
  override func awakeFromNib() {
    let controller = WebViewKeyGuardFlutterViewController()
    contentViewController = keyGuardHost(for: controller)
    setContentSize(NSSize(width: 1180, height: 800))
    minSize = NSSize(width: 850, height: 580)
    center()
    acceptsMouseMovedEvents = true
    RegisterGeneratedPlugins(registry: controller)
    diagnostics = LabDiagnostics(controller: controller, window: self)
    super.awakeFromNib()
  }
}

/// Self-contained test input: posts NSEvents only to this lab's native window.
/// No CGEvent posting, accessibility permissions, or OS-wide event injection.
private final class LabDiagnostics {
  private weak var window: NSWindow?
  private weak var controller: FlutterViewController?
  private var eventNumber = 100
  private let channel: FlutterMethodChannel

  init(controller: FlutterViewController, window: NSWindow) {
    self.controller = controller
    self.window = window
    channel = FlutterMethodChannel(name: "modal_lab", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "ARGS", message: "Missing test arguments", details: nil)); return
      }
      do {
        switch call.method {
        case "pointer": try self.pointer(args)
        case "key": try self.key(args)
        case "state":
          result(["firstResponder": self.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none"])
          return
        default: result(FlutterMethodNotImplemented); return
        }
        result(nil)
      } catch {
        result(FlutterError(code: "INPUT", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func pointer(_ args: [String: Any]) throws {
    guard let window = window, let view = controller?.view,
          let x = args["x"] as? Double, let y = args["y"] as? Double,
          (0...1).contains(x), (0...1).contains(y) else { throw LabError.invalid }
    let local = NSPoint(x: view.bounds.minX + view.bounds.width * x,
                        y: view.bounds.minY + view.bounds.height * (view.isFlipped ? y : 1-y))
    let point = view.convert(local, to: nil)
    let types: [String: NSEvent.EventType] = [
      "move": .mouseMoved, "down": .leftMouseDown, "up": .leftMouseUp, "drag": .leftMouseDragged,
      "rightDown": .rightMouseDown, "rightUp": .rightMouseUp,
    ]
    guard let type = types[args["type"] as? String ?? "move"] else { throw LabError.invalid }
    eventNumber += 1
    guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, eventNumber: eventNumber, clickCount: type == .mouseMoved ? 0 : 1,
      pressure: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0) else { throw LabError.invalid }
    NSApp.postEvent(event, atStart: false)
  }

  private func key(_ args: [String: Any]) throws {
    guard let window = window, let text = args["text"] as? String, text.count <= 32 else { throw LabError.invalid }
    let command = args["command"] as? Bool ?? false
    let code: UInt16 = text == "escape" ? 53 : (text == "a" ? 0 : 7)
    let characters = text == "escape" ? "\u{1b}" : text
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      guard let event = NSEvent.keyEvent(with: type, location: .zero,
        modifierFlags: command ? [.command] : [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw LabError.invalid }
      NSApp.postEvent(event, atStart: false)
    }
  }
  private enum LabError: Error { case invalid }
}
