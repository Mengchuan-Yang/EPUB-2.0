import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class LocalServer {
  HttpServer? _server;
  final String baseDir;
  int _port = 0;

  LocalServer(this.baseDir);

  int get port => _port;
  String get baseUrl => 'http://localhost:$_port';

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      print('Local HTTP server started on $baseUrl');

      _server!.listen((HttpRequest request) async {
        // Add CORS headers
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (request.method != 'GET') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }

        // Decode path components to handle percent-encoding (like spaces as %20)
        final decodedPath = Uri.decodeComponent(request.uri.path);
        // Normalize path
        final relPath = decodedPath.startsWith('/') ? decodedPath.substring(1) : decodedPath;
        final fullPath = p.normalize(p.join(baseDir, relPath));

        // Security check: ensure path is within baseDir
        final normalizedBaseDir = p.normalize(baseDir);
        if (!fullPath.startsWith(normalizedBaseDir)) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write('Forbidden');
          await request.response.close();
          return;
        }

        final file = File(fullPath);
        if (await file.exists()) {
          // Identify mime-type
          final mimeType = lookupMimeType(fullPath) ?? 'application/octet-stream';
          request.response.headers.contentType = ContentType.parse(mimeType);

          try {
            await file.openRead().pipe(request.response);
          } catch (e) {
            print('Error piping file: $e');
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('File Not Found');
          await request.response.close();
        }
      }, onError: (e) {
        print('HTTP Server stream error: $e');
      });
    } catch (e) {
      print('Error starting local server: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
