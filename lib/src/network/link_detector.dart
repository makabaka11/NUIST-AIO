import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../services/site_registry.dart';
import '../services/navigation.dart';
import 'campus_network.dart';
import 'external_link_route.dart';

class LinkAvailability {
  const LinkAvailability({this.path, this.error});
  final CampusPath? path;
  final String? error;
}

/// Network-only probe: no cookies, student ID, account state or TLS exceptions.
class DirectCampusLinkProbe {
  DirectCampusLinkProbe({HttpClient Function()? clientFactory})
    : clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() clientFactory;
  Future<bool> call(SchoolBrowserLink link) async {
    if (!link.vpn ||
        link.entry == null ||
        !SchoolBrowserLinks.all.any(
          (l) => l.vpn && l.id == link.id && l.entry == link.entry,
        )) {
      return false;
    }
    final client = clientFactory()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      return await _read(client, link).timeout(const Duration(seconds: 6));
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _read(HttpClient client, SchoolBrowserLink link) async {
    final origin = link.entry!;
    var uri = origin.replace(query: null, fragment: null);
    for (var redirect = 0; redirect < 4; redirect++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'text/html');
      final response = await request.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) return false;
        final next = uri.resolve(location);
        if (SchoolNavigation.trusted(next, {'authserver.nuist.edu.cn'}) &&
            next.path.startsWith('/authserver/')) {
          return true;
        }
        if (next.userInfo.isNotEmpty ||
            !(next.origin == origin.origin ||
                SchoolNavigation.trusted(next, {origin.host}))) {
          return false;
        }
        uri = next;
        continue;
      }
      if (response.statusCode != 200) return false;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        final remaining = 65536 - bytes.length;
        bytes.add(
          chunk.length > remaining ? chunk.sublist(0, remaining) : chunk,
        );
        if (bytes.length >= 65536) break;
      }
      final html = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      if (!RegExp(
        r'<!doctype\s+html|<html[\s>]',
        caseSensitive: false,
      ).hasMatch(html)) {
        return false;
      }
      return link.directProbeMarkers.every(html.contains) &&
          (origin.scheme == 'https' || link.directProbeMarkers.isNotEmpty);
    }
    return false;
  }
}

/// Per-origin routing: a public bulletin response cannot prove intranet access.
class CampusLinkDetector extends ChangeNotifier {
  CampusLinkDetector({
    required this.directory,
    Future<bool> Function(SchoolBrowserLink)? directProbe,
    DateTime Function()? now,
  }) : directProbe = directProbe ?? DirectCampusLinkProbe().call,
       now = now ?? DateTime.now;
  final Future<Map<String, dynamic>> Function() directory;
  final Future<bool> Function(SchoolBrowserLink) directProbe;
  final DateTime Function() now;
  final Map<String, LinkAvailability> results = {};
  DateTime? checkedAt;
  bool checking = false;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _pending;
  Future<Map<String, dynamic>>? _directoryPending;
  Map<String, dynamic>? _routes;
  DateTime? _routesCheckedAt;
  static const maxAge = Duration(minutes: 5);
  bool get fresh => checkedAt != null && now().difference(checkedAt!) < maxAge;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void reset() {
    _generation++;
    _pending = null;
    _directoryPending = null;
    _routes = null;
    _routesCheckedAt = null;
    results.clear();
    checkedAt = null;
    checking = false;
    _notify();
  }

  void _valid(int generation) {
    if (_disposed || generation != _generation) {
      throw const FormatException('网络或账号已变化，请重新打开入口。');
    }
  }

  Future<Map<String, dynamic>> _vpnRoutes() {
    if (_routes != null &&
        _routesCheckedAt != null &&
        now().difference(_routesCheckedAt!) < maxAge) {
      return Future.value(_routes);
    }
    if (_directoryPending != null) return _directoryPending!;
    final generation = _generation;
    final future = () async {
      final data = await directory().timeout(const Duration(seconds: 20));
      _valid(generation);
      if (data['ok'] != true ||
          data['ready'] != true ||
          data['routes'] is! Map) {
        throw const FormatException('请在网络设置连接学校 VPN 后重新检测。');
      }
      _routesCheckedAt = now();
      return _routes = Map<String, dynamic>.from(data['routes'] as Map);
    }();
    _directoryPending = future;
    future.then<void>(
      (_) {
        if (identical(_directoryPending, future)) _directoryPending = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_directoryPending, future)) _directoryPending = null;
      },
    );
    return future;
  }

  Future<void> detect({bool force = false}) {
    if (force) reset();
    if (_disposed) return Future.value();
    if (fresh) return Future.value();
    if (_pending != null) return _pending!;
    final generation = _generation;
    checking = true;
    results.clear();
    _routes = null;
    _notify();
    final future = () async {
      final failed = <SchoolBrowserLink>[];
      await Future.wait([
        for (final link in SchoolBrowserLinks.all.where((l) => l.vpn))
          () async {
            var available = false;
            try {
              available = await directProbe(link)
                  .timeout(const Duration(seconds: 7));
            } catch (_) {}
            if (_disposed || generation != _generation) return;
            if (available) {
              results[link.id] = const LinkAvailability(
                path: CampusPath.direct,
              );
              _notify();
            } else {
              failed.add(link);
            }
          }(),
      ]);
      if (_disposed || generation != _generation) return;
      if (failed.isNotEmpty) {
        Map<String, dynamic>? routes;
        try {
          routes = await _vpnRoutes();
        } catch (_) {}
        if (_disposed || generation != _generation) return;
        for (final link in failed) {
          try {
            if (routes == null) {
              throw const FormatException('直连不可达，需连接学校 VPN 后重新检测。');
            }
            externalVpnUri(link.entry!, routes);
            results[link.id] = const LinkAvailability(path: CampusPath.vpn);
          } on FormatException catch (e) {
            results[link.id] = LinkAvailability(error: e.message);
          }
        }
      }
      checkedAt = now();
      checking = false;
      _notify();
    }();
    _pending = future;
    future.then<void>(
      (_) {
        if (identical(_pending, future)) _pending = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_pending, future)) _pending = null;
      },
    );
    return future;
  }

  Future<Uri> resolve(
    SchoolBrowserLink link,
    CampusNetworkMode mode, {
    String? studentNumber,
  }) async {
    final uri = link.resolve(number: studentNumber);
    if (!link.vpn || mode == CampusNetworkMode.direct) return uri;
    final generation = _generation;
    if (mode == CampusNetworkMode.automatic) {
      // A completed result for this site must not wait for unrelated probes.
      final cached = (fresh || checking) ? results[link.id] : null;
      if (cached?.path == CampusPath.direct) return uri;
      if (cached?.path != CampusPath.vpn) await detect();
      _valid(generation);
      final status = results[link.id];
      if (status?.path == CampusPath.direct) return uri;
      if (status?.path != CampusPath.vpn) {
        throw FormatException(status?.error ?? '可用链路尚未确定，请在网络设置重新检测。');
      }
    }
    final routes = await _vpnRoutes();
    _valid(generation);
    return externalVpnUri(uri, routes);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pending = null;
    _routes = null;
    _directoryPending = null;
    super.dispose();
  }
}
