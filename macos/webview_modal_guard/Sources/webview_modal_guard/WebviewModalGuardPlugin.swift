import Cocoa
import FlutterMacOS

public final class WebviewModalGuardPlugin: NSObject, FlutterPlugin {
  private weak var view: NSView?
  private var router: ModalInputRouter?
  init(view: NSView?) { self.view = view }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "webview_modal_guard", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(WebviewModalGuardPlugin(view: registrar.view), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "acquire":
      guard let view = view, view.window != nil, let receiver = controller(for: view) else {
        result(FlutterError(code: "NO_WINDOW", message: "A mounted Flutter window is required.", details: nil))
        return
      }
      if router == nil { router = ModalInputRouter(view: view, receiver: receiver) }
      result(router!.acquire())
    case "release":
      guard let args = call.arguments as? [String: Any], let token = args["token"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Expected lease token.", details: nil))
        return
      }
      router?.release(token)
      result(nil)
    case "status":
      result(["supported": true, "leases": router?.leaseCount ?? 0, "routed": router?.routed ?? 0])
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func controller(for view: NSView) -> FlutterViewController? {
    var responder: NSResponder? = view.nextResponder
    while let current = responder {
      if let controller = current as? FlutterViewController { return controller }
      responder = current.nextResponder
    }
    return nil
  }
}
