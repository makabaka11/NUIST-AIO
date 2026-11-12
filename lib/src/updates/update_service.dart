import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_model.dart';
import 'update_download.dart';

class ReleaseRepository {
  ReleaseRepository({HttpClient Function()? clientFactory})
    : clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() clientFactory;
  Future<List<AppRelease>> fetch(UpdateSource source) async {
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      return await _read(client, source).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const FormatException('检查更新超时，请稍后重试或切换下载源。');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException('${source.label} 暂时无法连接，请稍后重试或切换下载源。');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<AppRelease>> _read(HttpClient client, UpdateSource source) async {
    final request = await client.getUrl(source.api);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'NUIST-AIO-Update');
    final response = await request.close();
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw FormatException('${source.label} 请求受限，请稍后重试或切换下载源。');
    }
    if (response.statusCode != 200) {
      throw FormatException('${source.label} 检查更新失败，请稍后重试。');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Release 数据过大，请到项目仓库查看。');
      }
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes.takeBytes()));
    } catch (_) {
      throw const FormatException('下载源返回格式异常，请稍后重试。');
    }
    return parseReleases(json, source);
  }
}

enum UpdateCheckStatus { idle, checking, noRelease, current, available, failed }

class UpdateController extends ChangeNotifier {
  UpdateController({
    Future<List<AppRelease>> Function(UpdateSource)? fetch,
    Future<InstalledBuild> Function()? installed,
    UpdateRuntime? runtime,
    UpdateDownload Function()? downloader,
    Future<String> Function(File)? installer,
  }) : fetch = fetch ?? ReleaseRepository().fetch,
       installed = installed ?? _installed,
       runtime = runtime ?? UpdateRuntime.current(),
       downloader = downloader ?? UpdateDownload.new,
       installer = installer ?? installUpdate;
  static Future<InstalledBuild> _installed() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledBuild(info.version, info.buildNumber);
  }

  final Future<List<AppRelease>> Function(UpdateSource) fetch;
  final Future<InstalledBuild> Function() installed;
  final UpdateRuntime runtime;
  final UpdateDownload Function() downloader;
  final Future<String> Function(File) installer;
  final _prefs = SharedPreferencesAsync();
  UpdateSource source = UpdateSource.github;
  bool autoCheck = true, remind = true;
  InstalledBuild? current;
  AppRelease? latest;
  String? error;
  UpdateCheckStatus status = UpdateCheckStatus.idle;
  bool _disposed = false, _startupClaimed = false;
  int _generation = 0;
  Future<AppRelease?>? _pending;
  Future<InstalledBuild>? _versionPending;
  final _presented = <String>{};
  bool wasPresented(AppRelease release) => _presented.contains(release.key);
  void markPresented(AppRelease release) => _presented.add(release.key);
  bool claimStartup() {
    if (_startupClaimed || !autoCheck || _disposed) return false;
    _startupClaimed = true;
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadSettings() async {
    try {
      final name = await _prefs.getString('updates.source');
      source = UpdateSource.values.firstWhere(
        (s) => s.name == name,
        orElse: () => UpdateSource.github,
      );
      autoCheck = await _prefs.getBool('updates.auto') ?? true;
      remind = await _prefs.getBool('updates.remind') ?? true;
    } catch (_) {
      /* Updating is optional and must not block startup. */
    }
  }

  Future<void> setSource(UpdateSource value) async {
    await _prefs.setString('updates.source', value.name);
    if (_disposed) return;
    source = value;
    _generation++;
    _pending = null;
    latest = null;
    error = null;
    status = UpdateCheckStatus.idle;
    _notify();
  }

  Future<void> setAutomatic(bool value) async {
    await _prefs.setBool('updates.auto', value);
    if (_disposed) return;
    autoCheck = value;
    _notify();
  }

  Future<void> setReminder(bool value) async {
    await _prefs.setBool('updates.remind', value);
    if (_disposed) return;
    remind = value;
    _notify();
  }

  Future<InstalledBuild> loadInstalled() {
    if (current != null) return Future.value(current);
    if (_versionPending != null) return _versionPending!;
    final future = installed().timeout(const Duration(seconds: 5));
    _versionPending = future;
    future.then<void>(
      (v) {
        if (!_disposed) {
          current = v;
          _notify();
        }
        if (identical(_versionPending, future)) _versionPending = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_versionPending, future)) _versionPending = null;
      },
    );
    return future;
  }

  Future<AppRelease?> check() {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    final generation = _generation, selected = source;
    status = UpdateCheckStatus.checking;
    error = null;
    _notify();
    final future = () async {
      try {
        final local = await loadInstalled();
        final localVersion = local.comparable;
        final list = await fetch(selected).timeout(const Duration(seconds: 18));
        if (_disposed || generation != _generation) return null;
        final stable = list.where((r) => r.source == selected).toList()
          ..sort((a, b) => b.version.compareTo(a.version));
        latest = stable.isEmpty ? null : stable.first;
        status = latest == null
            ? UpdateCheckStatus.noRelease
            : latest!.version.newerThan(localVersion)
            ? UpdateCheckStatus.available
            : UpdateCheckStatus.current;
        _notify();
        return status == UpdateCheckStatus.available ? latest : null;
      } on FormatException catch (e) {
        if (!_disposed && generation == _generation) {
          error = e.message;
          status = UpdateCheckStatus.failed;
          _notify();
        }
        return null;
      } catch (_) {
        if (!_disposed && generation == _generation) {
          error = '检查更新失败，请检查网络后重试。';
          status = UpdateCheckStatus.failed;
          _notify();
        }
        return null;
      }
    }();
    _pending = future;
    future.then<void>((_) {
      if (identical(_pending, future)) _pending = null;
    });
    return future;
  }

  String get statusText => switch (status) {
    UpdateCheckStatus.idle => '点击检查是否有新版本',
    UpdateCheckStatus.checking => '正在检查更新…',
    UpdateCheckStatus.noRelease => '所选仓库尚未发布正式版本',
    UpdateCheckStatus.current => '当前已是最新正式版本',
    UpdateCheckStatus.available => '发现新版本 ${latest!.tag}',
    UpdateCheckStatus.failed => error ?? '检查更新失败',
  };
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pending = null;
    super.dispose();
  }
}
