import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'src/guarded_dialog.dart';

/// Automatically registered by Flutter once per isolate.
/// Native plugins survive hot restart, while Dart leases and routes do not.
class WebViewModalGuardPlugin {
  static Future<void>? _startup;

  static void registerWith() {
    // Background-isolate registration must not clear the UI's live leases.
    if (ui.RootIsolateToken.instance == null || _startup != null) return;
    const codec = StandardMethodCodec();
    final ready = Completer<void>();
    _startup = ready.future;
    // Registration can run before an app selects its WidgetsBinding.
    // Use the public dispatcher without initializing a binding on its behalf.
    ui.PlatformDispatcher.instance.sendPlatformMessage(
      'webview_modal_guard',
      codec.encodeMethodCall(const MethodCall('reset')),
      (reply) {
        try {
          if (reply == null) throw MissingPluginException('Modal guard reset');
          codec.decodeEnvelope(reply);
          ready.complete();
        } catch (error, stack) {
          ready.completeError(error, stack);
        }
      },
    );
    // A startup error is surfaced when the app first uses the guard.
    // Keep it handled while no caller has awaited acquisition/status yet.
    unawaited(ready.future.catchError((Object _) {}));
  }
}

/// Each engine owns a guard scoped to its Flutter view and native window.
class WebViewModalGuard {
  const WebViewModalGuard({
    this.channel = const MethodChannel('webview_modal_guard'),
  });
  final MethodChannel channel;
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Acquire before displaying an overlay. Release after it is fully removed.
  Future<WebViewModalLease> acquire() async {
    if (!supported) return WebViewModalLease._(null, null);
    await WebViewModalGuardPlugin._startup;
    final token = await channel.invokeMethod<Object?>('acquire');
    if (token is! String || token.isEmpty) {
      throw const FormatException('Invalid modal guard lease');
    }
    return WebViewModalLease._(channel, token);
  }

  /// For custom overlays; operation must include their exit animation.
  Future<T> protect<T>(Future<T> Function() operation) async {
    final lease = await acquire();
    try {
      return await operation();
    } finally {
      await lease.release();
    }
  }

  /// Diagnostics contain counts only, never page content or input text.
  Future<Map<String, dynamic>> status() async {
    if (!supported) return {'supported': false, 'leases': 0, 'routed': 0};
    await WebViewModalGuardPlugin._startup;
    return Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('status') ?? {},
    );
  }
}

/// Overlapping leases keep protection active until the last lease is released.
class WebViewModalLease {
  WebViewModalLease._(this._channel, this._token);
  final MethodChannel? _channel;
  final String? _token;
  Future<void>? _release;

  /// Repeated/concurrent calls share one native release. Failed calls may retry.
  Future<void> release() => _release ??= _releaseNative();

  Future<void> _releaseNative() async {
    try {
      await _channel?.invokeMethod<void>('release', {'token': _token});
    } catch (_) {
      _release = null;
      rethrow;
    }
  }
}
