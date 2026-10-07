import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'src/guarded_dialog.dart';

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
