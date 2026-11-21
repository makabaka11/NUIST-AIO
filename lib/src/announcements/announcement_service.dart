import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/site_registry.dart';
import 'announcement.dart';

/// Reads the public announcement file without touching any campus session.
class AnnouncementRepository {
  AnnouncementRepository({
    HttpClient Function()? clientFactory,
    List<Uri>? candidates,
    Uri? canonicalSource,
  }) : clientFactory = clientFactory ?? HttpClient.new,
       candidates = candidates ?? AppAnnouncementSource.candidates,
       canonicalSource = canonicalSource ?? AppAnnouncementSource.raw;

  final HttpClient Function() clientFactory;
  final List<Uri> candidates;
  final Uri canonicalSource;

  static const maxBytes = 512 * 1024;

  Future<Announcement> fetch() async {
    Object? lastError;
    for (final source in candidates) {
      try {
        final text = await _read(source);
        return parseAnnouncement(text, source: canonicalSource);
      } on FormatException catch (error) {
        lastError = error;
      } catch (_) {
        lastError = const FormatException('公告读取失败，请检查网络后重试。');
      }
    }
    if (lastError is FormatException) throw lastError;
    throw const FormatException('公告读取失败，请检查网络后重试。');
  }

  Future<String> _read(Uri source) async {
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      return await _download(
        client,
        source,
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const FormatException('公告读取超时，请稍后重试。');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('公告暂时无法连接，请稍后重试。');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _download(
    HttpClient client,
    Uri source, {
    int redirects = 0,
  }) async {
    final request = await client.getUrl(source);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/plain, text/markdown;q=0.9, */*;q=0.1',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'NUIST-AIO-Announcement');
    final response = await request.close();

    // The GitHub mirror and CDN normally answer directly; follow only HTTPS
    // redirects to avoid an accidental downgrade.
    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain();
      if (redirects >= 3 || location == null) {
        throw const FormatException('公告地址跳转次数过多。');
      }
      final next = Uri.tryParse(location);
      final resolved = next == null ? null : source.resolveUri(next);
      if (resolved == null || resolved.scheme != 'https') {
        throw const FormatException('公告地址跳转未通过 HTTPS 校验。');
      }
      return _download(client, resolved, redirects: redirects + 1);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain();
      throw const FormatException('公告文件暂时不可用，请稍后重试。');
    }
    final contentType = response.headers.contentType;
    if (contentType?.mimeType == 'text/html') {
      await response.drain();
      throw const FormatException('公告地址返回了网页而不是 Markdown 文件。');
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('公告文件过大，请缩小后再发布。');
      }
    }
    final String text;
    try {
      text = utf8.decode(bytes.takeBytes());
    } on FormatException {
      throw const FormatException('公告文件不是有效的 UTF-8 编码。');
    }
    if (text.trim().isEmpty) {
      throw const FormatException('公告文件为空。');
    }
    if (RegExp(
      r'^\s*<(?:!doctype|html)',
      caseSensitive: false,
    ).hasMatch(text)) {
      throw const FormatException('公告地址返回了网页而不是 Markdown 文件。');
    }
    return text;
  }
}

enum AnnouncementStatus { idle, loading, ready, failed }

/// Holds the current public notice and its offline cache.
class AnnouncementController extends ChangeNotifier {
  AnnouncementController({
    Future<Announcement> Function()? fetch,
    SharedPreferencesAsync? preferences,
  }) : _fetch = fetch ?? AnnouncementRepository().fetch,
       _prefs = preferences ?? SharedPreferencesAsync();

  static const cacheKey = 'announcement.cache.v1';

  final Future<Announcement> Function() _fetch;
  final SharedPreferencesAsync _prefs;

  Announcement? announcement;
  AnnouncementStatus status = AnnouncementStatus.idle;
  String? error;
  bool fromCache = false;
  bool dismissed = false;

  bool _disposed = false;
  bool _startupClaimed = false;
  String? _shownSignature;
  Future<void>? _pending;

  bool get loading => status == AnnouncementStatus.loading;

  /// Restores the last successful copy before the first frame. A failed
  /// network refresh keeps this copy visible and reports [error] separately.
  Future<void> restoreCache() async {
    if (_disposed) return;
    try {
      final raw = await _prefs.getString(cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final savedAt = decoded['savedAt'];
      final savedAtValue = savedAt is String
          ? DateTime.tryParse(savedAt)
          : null;
      if (savedAtValue != null &&
          DateTime.now().toUtc().difference(savedAtValue.toUtc()) >
              const Duration(days: 90)) {
        return;
      }
      final cached = Announcement.fromCacheJson(decoded['announcement']);
      if (cached == null ||
          cached.source.toString() != AppAnnouncementSource.raw.toString()) {
        return;
      }
      if (_disposed) return;
      announcement = cached;
      _shownSignature = cached.signature;
      fromCache = true;
      status = AnnouncementStatus.ready;
      notifyListeners();
    } catch (_) {
      // A corrupt cache is never allowed to block startup.
    }
  }

  /// Fetches once per app launch. The homepage banner calls this after its
  /// first frame so startup and onboarding are not delayed by the network.
  void refreshOnStartup() {
    if (_startupClaimed || _disposed) return;
    _startupClaimed = true;
    unawaited(refresh());
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    status = AnnouncementStatus.loading;
    error = null;
    notifyListeners();

    final future = () async {
      try {
        final value = await _fetch().timeout(const Duration(seconds: 40));
        if (_disposed) return;
        final changed = _shownSignature != value.signature;
        announcement = value;
        _shownSignature = value.signature;
        fromCache = false;
        if (changed) dismissed = false;
        status = AnnouncementStatus.ready;
        await _persist(value);
      } on FormatException catch (failure) {
        if (!_disposed) {
          error = failure.message;
          status = AnnouncementStatus.failed;
        }
      } catch (_) {
        if (!_disposed) {
          error = '公告读取失败，请检查网络后重试。';
          status = AnnouncementStatus.failed;
        }
      } finally {
        if (!_disposed) notifyListeners();
      }
    }();
    _pending = future;
    future.whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
    return future;
  }

  Future<void> _persist(Announcement value) async {
    try {
      await _prefs.setString(
        cacheKey,
        jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'announcement': value.toCacheJson(),
        }),
      );
    } catch (_) {
      // The network copy is still usable even when the cache cannot be written.
    }
  }

  void dismiss() {
    if (_disposed || announcement == null || dismissed) return;
    dismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
