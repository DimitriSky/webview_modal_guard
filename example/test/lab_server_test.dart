import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_modal_lab/lab_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'loopback harness serves probe and reports actions without navigation',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (_) async {
            return ByteData.sublistView(
              utf8.encode('<html>owned probe</html>'),
            );
          });
      final received = <Map<String, dynamic>>[];
      final server = LabServer(
        state: () async => {'ready': true},
        action: (args) async {
          received.add(args);
          return {'ok': true};
        },
      );
      // This test owns a real loopback server, so bypass the widget binding's
      // default HTTP stub for the duration of this non-widget test.
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final client = HttpClient();
      try {
        await server.start();
        expect(Uri.parse(server.baseUrl).host, '127.0.0.1');
        final probe = await (await client.getUrl(
          Uri.parse('${server.baseUrl}/probe'),
        )).close();
        expect(
          await utf8.decoder.bind(probe).join(),
          '<html>owned probe</html>',
        );
        final state = await (await client.getUrl(
          Uri.parse('${server.baseUrl}/state'),
        )).close();
        expect(jsonDecode(await utf8.decoder.bind(state).join()), {
          'ready': true,
        });
        final request = await client.postUrl(
          Uri.parse('${server.baseUrl}/action'),
        );
        request.write(jsonEncode({'action': 'reset'}));
        final response = await request.close();
        expect(response.statusCode, 200);
        await response.drain<void>();
        expect(received, [
          {'action': 'reset'},
        ]);
        final oversized = await client.postUrl(
          Uri.parse('${server.baseUrl}/action'),
        );
        oversized.write('x' * 8193);
        final rejected = await oversized.close();
        expect(rejected.statusCode, 400);
        await rejected.drain<void>();
        expect(received.length, 1);
      } finally {
        client.close(force: true);
        HttpOverrides.global = previousHttpOverrides;
        await server.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      }
    },
  );
}
