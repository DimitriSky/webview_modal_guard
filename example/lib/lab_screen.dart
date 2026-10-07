import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_modal_guard/webview_modal_guard.dart';
import 'package:webview_key_guard/webview_key_guard.dart';
import 'lab_dialog.dart';
import 'lab_server.dart';

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  static const native = MethodChannel('modal_lab');
  final guard = const WebViewModalGuard();
  late final server = LabServer(state: snapshot, action: action);
  InAppWebViewController? web;
  bool ready = false, loaded = false, guarded = true, keyGuard = true;
  int dialogs = 0, popupMoves = 0;
  String field = 'https://modal.example', error = '';
  double slider = .4;
  double popupScroll = 0;
  Timer? refresh;
  Map<String, dynamic> latest = {};

  @override
  void initState() {
    super.initState();
    server.start().then((_) {
      if (!mounted) return;
      setState(() => ready = true);
      refresh = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          final value = await snapshot();
          if (mounted) setState(() => latest = value);
        } catch (_) {
          /* The native view may be rebuilding. */
        }
      });
    });
  }

  @override
  void dispose() {
    refresh?.cancel();
    unawaited(server.close());
    super.dispose();
  }

  Future<Map<String, dynamic>> snapshot() async {
    final page = loaded
        ? await web?.evaluateJavascript(
            source: 'JSON.stringify(modalProbe.snapshot())',
          )
        : null;
    return {
      'tag': 'WV-MODAL-GUARD',
      'ready': loaded,
      'guarded': guarded,
      'keyGuard': keyGuard,
      'dialogs': dialogs,
      'popupMoves': popupMoves,
      'field': field,
      'slider': slider,
      'popupScroll': popupScroll,
      'guard': await guard.status(),
      'native': await native.invokeMapMethod<String, dynamic>(
        'state',
        <String, dynamic>{},
      ),
      'page': page is String ? jsonDecode(page) : null,
      'error': error,
    };
  }

  void open(String kind) {
    final protected = guarded;
    setState(() => dialogs++);
    Widget builder(BuildContext context) => LabDialog(
      kind: kind,
      onNested: () => open('Nested'),
      onHover: () => popupMoves++,
      onScroll: (value) => popupScroll = value,
      onChange: (text, value) {
        field = text;
        slider = value;
      },
    );
    Future<void> display() async {
      try {
        if (protected) {
          await showWebViewGuardedDialog(
            context: context,
            builder: builder,
            guard: guard,
          );
        } else {
          await showDialog(context: context, builder: builder);
        }
      } catch (exception) {
        error = exception.toString();
      } finally {
        if (mounted) setState(() => dialogs--);
      }
    }

    unawaited(display());
  }

  Future<Object?> action(Map<String, dynamic> args) async {
    switch (args['action']) {
      case 'mode':
        if (dialogs != 0) {
          throw StateError('Close dialogs before switching modes');
        }
        setState(() => guarded = args['guarded'] as bool);
      case 'open':
        open(args['kind'] as String? ?? 'URL');
      case 'close':
        Navigator.of(context).pop();
      case 'reset':
        await web?.evaluateJavascript(source: 'modalProbe.reset()');
        popupMoves = 0;
      case 'pointer':
        await native.invokeMethod<void>('pointer', args);
      case 'key':
        await native.invokeMethod<void>('key', args);
      case 'nested':
        open('Nested');
      case 'keyGuard':
        keyGuard = args['enabled'] as bool;
        await const WebViewKeyGuard().setEnabled(keyGuard);
      default:
        throw ArgumentError('Unknown action');
    }
    return {'ok': true};
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        SizedBox(
          width: 290,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WebView Modal Lab',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const Text('#WV-MODAL-GUARD'),
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Native protection'),
                  value: guarded,
                  onChanged: dialogs == 0
                      ? (value) => setState(() => guarded = value)
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keyboard guard'),
                  value: keyGuard,
                  onChanged: (value) async {
                    await action({'action': 'keyGuard', 'enabled': value});
                    setState(() {});
                  },
                ),
                FilledButton(
                  onPressed: loaded ? () => open('URL') : null,
                  child: const Text('URL popup'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: loaded ? () => open('Settings') : null,
                  child: const Text('Settings popup'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: loaded ? () => action({'action': 'reset'}) : null,
                  child: const Text('Reset counters'),
                ),
                if (ready)
                  SelectableText(
                    server.baseUrl,
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(latest),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ready
              ? InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri('${server.baseUrl}/probe'),
                  ),
                  initialSettings: InAppWebViewSettings(isInspectable: true),
                  onWebViewCreated: (controller) => web = controller,
                  onLoadStop: (_, _) => setState(() => loaded = true),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    ),
  );
}
