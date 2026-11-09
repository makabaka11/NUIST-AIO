import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Deliberately narrow schema: never accepts form values, tokens, raw errors,
/// API payloads, query strings, fragments, or full HTTP headers.
class SsoDiagnostics {
  static const enabled = bool.fromEnvironment('NUIST_SSO_DIAGNOSTICS');
  static const _channel = MethodChannel('nuistaio/sso_diagnostics');
  static Future<void> reset() async {
    if (!enabled) return;
    try {
      await _channel.invokeMethod<void>('reset');
    } catch (_) {}
  }

  static String entry(
    String site,
    String event, {
    Uri? location,
    String? task,
    String? type,
    bool? ok,
    bool? ready,
    int? status,
    bool? mainFrame,
  }) => jsonEncode({
    'site': site,
    'event': event,
    if (location != null)
      'location': '${location.scheme}://${location.host}${location.path}',
    'task': ?task,
    'type': ?type,
    'ok': ?ok,
    'ready': ?ready,
    'status': ?status,
    'mainFrame': ?mainFrame,
  });
  static void record(
    String site,
    String event, {
    Uri? location,
    String? task,
    String? type,
    bool? ok,
    bool? ready,
    int? status,
    bool? mainFrame,
  }) {
    if (!enabled) return;
    final line = entry(
      site,
      event,
      location: location,
      task: task,
      type: type,
      ok: ok,
      ready: ready,
      status: status,
      mainFrame: mainFrame,
    );
    debugPrint('NUIST_SSO $line');
    _channel.invokeMethod<void>('append', line).catchError((Object _) {});
  }
}
