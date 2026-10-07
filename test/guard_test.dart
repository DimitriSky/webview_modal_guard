import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_modal_guard/webview_modal_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_modal_guard');
  const guard = WebViewModalGuard();
  final calls = <MethodCall>[];
  var serial = 0;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    serial = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'acquire' ? 'lease-${++serial}' : null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('overlapping scopes release their own tokens exactly once', () async {
    final a = await guard.acquire(), b = await guard.acquire();
    await Future.wait([a.release(), a.release()]);
    await b.release();
    expect(calls.map((e) => e.method), [
      'acquire',
      'acquire',
      'release',
      'release',
    ]);
    expect(calls[2].arguments, {'token': 'lease-1'});
    expect(calls[3].arguments, {'token': 'lease-2'});
  });

  test('throwing custom overlay releases the lease', () async {
    await expectLater(
      guard.protect(() async => throw StateError('overlay failed')),
      throwsStateError,
    );
    expect(calls.map((e) => e.method), ['acquire', 'release']);
  });

  test('unsupported platform never invokes native channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await guard.protect(() async => 42);
    expect(calls, isEmpty);
  });

  test(
    'invalid acquire fails without displaying an unprotected modal',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 42);
      await expectLater(guard.acquire(), throwsFormatException);
    },
  );

  test('failed native release can be retried', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'acquire') return 'retry';
          if (++attempts == 1) throw PlatformException(code: 'TRANSIENT');
          return null;
        });
    final lease = await guard.acquire();
    await expectLater(lease.release(), throwsA(isA<PlatformException>()));
    await lease.release();
    await lease.release();
    expect(attempts, 2);
  });

  testWidgets(
    'context removed while acquiring releases without showing dialog',
    (tester) async {
      final acquired = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'acquire' ? acquired.future : null;
          });
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final result = showWebViewGuardedDialog(
        context: context,
        builder: (_) => const Text('Unreachable'),
      );
      await tester.pumpWidget(const SizedBox());
      acquired.complete('late-lease');
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(calls.map((e) => e.method), ['acquire', 'release']);
      expect(find.text('Unreachable'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('disposing a navigator with an open dialog releases its lease', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final result = showWebViewGuardedDialog(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Modal')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(calls.map((e) => e.method), ['acquire', 'release']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'dialog result waits for removal before releasing native protection',
    (tester) async {
      Future<String?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showWebViewGuardedDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Modal'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop('ok'),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(calls.map((e) => e.method), ['acquire']);
      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(calls.map((e) => e.method), ['acquire']);
      await tester.pumpAndSettle();
      expect(await result, 'ok');
      expect(calls.map((e) => e.method), ['acquire', 'release']);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
