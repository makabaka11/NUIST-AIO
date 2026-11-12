import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update_model.dart';

/// A separate client keeps campus cookies and credentials out of update requests.
class UpdateDownload {
  UpdateDownload({HttpClient Function()? clientFactory, this.directory})
    : clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() clientFactory;
  final Future<Directory> Function()? directory;
  HttpClient? _client;
  bool _cancelled = false;
  Completer<void>? _cancellation;

  void cancel() {
    _cancelled = true;
    if (!(_cancellation?.isCompleted ?? true)) _cancellation!.complete();
    _client?.close(force: true);
  }

  Future<File> download(
    ReleaseAsset asset, {
    required void Function(int received, int? total) onProgress,
  }) async {
    _cancelled = false;
    final cancellation = _cancellation = Completer<void>();
    final client = _client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    File? partial;
    IOSink? sink;
    StreamIterator<List<int>>? iterator;
    try {
      final root = await (directory?.call() ?? _directory());
      await root.create(recursive: true);
      final name = asset.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      if (name.isEmpty || name == '.' || name == '..') {
        throw const FormatException('安装包文件名无效。');
      }
      final file = File('${root.path}/$name');
      partial = File('${file.path}.part');
      var url = githubUpdateMirror(asset.url);
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (_cancelled) throw const FormatException('下载已取消。');
        if (url.scheme != 'https' || url.userInfo.isNotEmpty) {
          throw const FormatException('下载地址不安全。');
        }
        final request = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 30));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'NUIST-AIO-Update');
        response = await request.close().timeout(const Duration(seconds: 30));
        if (url.host == 'gh-proxy.org' && response.statusCode >= 400) {
          // A mirror outage must not prevent downloading from the official source.
          await response.drain<void>().timeout(const Duration(seconds: 30));
          url = asset.url;
          continue;
        }
        if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) {
          throw const FormatException('下载地址重定向异常。');
        }
        url = url.resolve(location);
        await response.drain<void>().timeout(const Duration(seconds: 30));
      }
      if (response == null || response.statusCode != 200) {
        throw const FormatException('安装包下载失败，请稍后重试或切换下载源。');
      }
      final type = response.headers.contentType?.mimeType ?? '';
      if (type.contains('html') ||
          type.contains('json') ||
          type.startsWith('text/')) {
        throw const FormatException('下载源返回的不是安装包，请切换下载源。');
      }
      final total = response.contentLength > 0 ? response.contentLength : null;
      var received = 0;
      onProgress(0, total);
      sink = partial.openWrite();
      final chunks = StreamIterator(
        response.timeout(const Duration(seconds: 30)),
      );
      iterator = chunks;
      Future<void> receive() async {
        while (await chunks.moveNext()) {
          if (_cancelled) throw const FormatException('下载已取消。');
          final bytes = chunks.current;
          sink!.add(bytes);
          received += bytes.length;
          onProgress(received, total);
        }
      }

      await Future.any<void>([
        receive(),
        cancellation.future.then<void>(
          (_) => throw const FormatException('下载已取消。'),
        ),
      ]);
      await sink.flush();
      await sink.close();
      sink = null;
      if (_cancelled) throw const FormatException('下载已取消。');
      if (received == 0 || (total != null && received != total)) {
        throw const FormatException('安装包下载不完整，请重试。');
      }
      return await partial.rename(file.path);
    } finally {
      client.close(force: true);
      if (iterator != null) unawaited(iterator.cancel());
      _client = null;
      try {
        await sink?.close();
      } finally {
        if (partial != null && await partial.exists()) await partial.delete();
      }
    }
  }

  static Future<Directory> _directory() async {
    final root = Platform.isAndroid
        ? await getTemporaryDirectory()
        : await getDownloadsDirectory() ??
              await getApplicationSupportDirectory();
    return Directory('${root.path}/updates');
  }
}

Future<String> installUpdate(File file) async =>
    await const MethodChannel('nuistaio/updates')
        .invokeMethod<String>('installApk', file.path) ??
    'requested';
