# webview_modal_guard · #WV-MODAL-GUARD

macOS Flutter plugin that isolates a **full-window Flutter modal** from native WebView mouse delivery. It uses public AppKit event monitors and the Flutter view controller's public responder methods. No WebKit subclass, method swizzling, JavaScript event blockers, patched Flutter SDK, or WebView replacement.

## Use

For an application consuming the package from GitHub, pin an immutable commit:

```yaml
dependencies:
  webview_modal_guard:
    git:
      url: https://github.com/DimitriSky/webview_modal_guard.git
      ref: 3a765df1519ec9bc767106e3bbfdea44f0113231
```

Replace a full-window Material `showDialog` call:

```dart
import 'package:webview_modal_guard/webview_modal_guard.dart';

await showWebViewGuardedDialog<void>(
  context: context,
  builder: (_) => const AlertDialog(title: Text('Settings')),
);
```

The guard is acquired before the route is pushed, and released **after the exit animation and route removal**. Navigator disposal and a context disappearing during acquisition also release it. Native acquisition errors propagate instead of silently showing an unprotected dialog. Nested dialogs acquire independent tokens; closing the child leaves the parent protected.

For a custom overlay:

```dart
await const WebViewModalGuard().protect(() async {
  // Show your overlay and wait until its exit animation/removal completes.
});
```

Or use `acquire()` and release its lease in `finally`. Release is idempotent and retryable after a method-channel error. An operation that only waits for `Navigator.pop` does not include the exit animation; use the supplied dialog helper or explicitly await route removal.

## Mechanism and scope

During an active lease, a local `NSEvent` monitor takes mouse movement, buttons, dragging, scrolling and gestures inside that engine's Flutter view in that view's native window. It calls the matching public `FlutterViewController` responder method once, then returns `nil` so AppKit does not also deliver the event to WebKit tracking areas. Flutter's own hit testing handles the popup and its barrier.

Keyboard events keep their existing responder path. This package can coexist with `webview_key_guard`; it does not depend on it. A drag begun inside Flutter retains its matching drag/release delivery if it exits the view bounds, preventing stuck Flutter buttons. Native window controls and events in other windows/outside the Flutter view are preserved. No page is reloaded or detached. The monitor is removed after the final lease is released and on router disposal. Diagnostics expose only lease/routing counts.

This is for modals covering the **whole Flutter content area**. A partial popover that permits interacting with the rest of the WebView needs a different policy. Non-macOS platforms use a no-op lease. Acquire on the main UI isolate after the Flutter view is mounted in a window.

Existing CSS hover state is not explicitly cleared on acquisition; the package suppresses subsequent delivery, rather than rewriting DOM state. AppKit local monitors do not run inside every native tracking loop (native menus/window drags); those loops are outside the Flutter modal qualification. See [Apple event-monitor documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html). Flutter's engine documents tracking areas ignoring occluding views in [FlutterMutatorView.mm](https://github.com/flutter/flutter/blob/ee80f08bbf97172ec030b8751ceab557177a34a6/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterMutatorView.mm#L55).

## Verification

```sh
flutter pub get
flutter analyze
flutter test
swift test
```

Dart tests cover lease overlap, retry, error cleanup, late acquisition after context removal, Navigator disposal, and protection through reverse animation. Standalone AppKit tests cover window/view bounds, detached views, nested tokens, exact mouse dispatch and keyboard pass-through. These are policy/lifecycle tests, not proof of physical WebKit hover isolation.

Native reproduction and qualification live in the [example app](example/README.md). Its [evidence](example/evidence/) distinguishes observed native DOM leakage, routing smoke checks, and physical-input qualification. Current test stack: Flutter 3.44.6 / Dart 3.12.2, macOS, `flutter_inappwebview` 6.1.5 (`flutter_inappwebview_macos` 1.1.2). Protected Settings passed a user-driven physical hover check in the lab, with 595 additional native events and zero DOM input; the full physical popup/gesture matrix has not been run. Recheck the relevant scenarios when integrating into the target application.

The example is a standalone Flutter application with its own native runner and test harness. It uses `path: ..` to exercise the package source in the same checkout:

```sh
cd example
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## Repository and integration

The package and example share the [webview_modal_guard repository](https://github.com/DimitriSky/webview_modal_guard). The example's local dependency keeps reproduction and implementation together; consuming applications use the Git URL with a pinned commit. The installation snippet above pins the initial published implementation. SimpleWebBrowser integration is a separate subsequent step. The existing proprietary license is unchanged.
