import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// A loopback-only diagnostic API; the lab owns all test pages and actions.
class LabServer {
  LabServer({required this.state, required this.action});
  final Future<Map<String, dynamic>> Function() state;
  final Future<Object?> Function(Map<String, dynamic>) action;
  HttpServer? _server;
  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    final html = await rootBundle.loadString('assets/pointer.html');
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final response = request.response;
      response.headers.set('Cache-Control', 'no-store');
      try {
        switch ((request.method, request.uri.path)) {
          case ('GET', '/probe'):
            response.headers.contentType = ContentType.html;
            response.write(html);
          case ('GET', '/state'):
            response.headers.contentType = ContentType.json;
            response.write(jsonEncode(await state()));
          case ('POST', '/action'):
            final bytes = <int>[];
            await for (final chunk in request) {
              bytes.addAll(chunk);
              if (bytes.length > 8192) {
                throw const FormatException('Request too large');
              }
            }
            response.headers.contentType = ContentType.json;
            response.write(
              jsonEncode(
                await action(
                  jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
                ),
              ),
            );
          default:
            response.statusCode = HttpStatus.notFound;
        }
      } catch (error) {
        response.statusCode = HttpStatus.badRequest;
        response.write(jsonEncode({'error': error.toString()}));
      } finally {
        await response.close();
      }
    });
    // stdout is the discovery contract used by tool/qualify.py.
    // ignore: avoid_print
    print('MODAL_LAB_URL=$baseUrl');
  }

  Future<void> close() async => _server?.close(force: true);
}
