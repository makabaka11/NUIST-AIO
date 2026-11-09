import 'dart:convert';

import '../schedule/schedule.dart';
import '../accounts/accounts.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Native WebView owns the active cookie jar. This encrypted snapshot is not
/// restored into broader cookie domains or sent by a Dart HTTP client.
class SessionStore {
  static const _accountsKey = 'nuist.accounts.v1';
  static const _dormKey = 'nuist.dorm.v1';
  Future<AccountCache> readAccounts() async {
    final raw = await _secure.read(key: _accountsKey);
    return raw == null
        ? const AccountCache()
        : AccountCache.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveAccounts(AccountCache data) =>
      _secure.write(key: _accountsKey, value: jsonEncode(data.toJson()));
  Future<void> clearAccounts() => _secure.delete(key: _accountsKey);
  Future<DormSelection?> readDorm() async {
    final raw = await _secure.read(key: _dormKey);
    return raw == null
        ? null
        : DormSelection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveDorm(DormSelection? dorm) => dorm == null
      ? _secure.delete(key: _dormKey)
      : _secure.write(key: _dormKey, value: jsonEncode(dorm.toJson()));
  static const _scheduleKey = 'nuist.schedule.v1';
  Future<Schedule?> readSchedule() async {
    final raw = await _secure.read(key: _scheduleKey);
    return raw == null
        ? null
        : Schedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSchedule(Schedule value) =>
      _secure.write(key: _scheduleKey, value: jsonEncode(value.toJson()));
  Future<void> clearSchedule() => _secure.delete(key: _scheduleKey);

  static const _key = 'nuist.portal.session.v1';
  Future<Map<String, dynamic>?>? _portalRead;
  void invalidatePortalRead() => _portalRead = null;
  Future<Map<String, dynamic>?> _readPortal() => _portalRead ??= () async {
    final raw = await _secure.read(key: _key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }();
  static const _secure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static final loginUri = Uri.https(
    'authserver.nuist.edu.cn',
    '/authserver/login',
    {'service': 'https://i.nuist.edu.cn/login#/'},
  );
  static const origins = [
    'https://authserver.nuist.edu.cn/authserver/login',
    'https://i.nuist.edu.cn/',
  ];

  static bool isAllowedNavigation(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      const {'authserver.nuist.edu.cn', 'i.nuist.edu.cn'}.contains(uri.host);

  static bool isPortalLanding(Uri uri) =>
      isAllowedNavigation(uri) &&
      uri.host == 'i.nuist.edu.cn' &&
      uri.path != '/login' &&
      !uri.path.startsWith('/authserver/') &&
      !uri.queryParameters.containsKey('ticket');

  Future<bool> accountChanged(String accountKey) async {
    final data = await _readPortal();
    if (data == null) return false;
    return data['accountKey'] != accountKey;
  }

  Future<bool> capturePortalSession({
    required String accountKey,
    required String displayName,
  }) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(accountKey)) return false;
    final manager = CookieManager.instance();
    final auth = await manager.getCookies(url: WebUri(origins[0]));
    final portal = await manager.getCookies(url: WebUri(origins[1]));
    await _secure.write(
      key: _key,
      value: jsonEncode({
        'version': 2,
        'accountKey': accountKey,
        'displayName': displayName.trim(),
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        // Android can omit attributes. Keep unknown values unknown; never infer
        // a parent domain from an observed request URL.
        'snapshots': [
          {
            'observedUrl': origins[0],
            'cookies': auth.map((c) => c.toJson()).toList(),
          },
          {
            'observedUrl': origins[1],
            'cookies': portal.map((c) => c.toJson()).toList(),
          },
        ],
      }),
    );
    _portalRead = null;
    return true;
  }

  /// Restore only fully described, exact-host cookies captured by this app.
  /// Unknown scope/security attributes are never inferred. Existing native
  /// cookies win, so a newer login cannot be replaced by an old snapshot.
  static bool canRestoreCookie(Uri origin, Cookie cookie, DateTime now) {
    final domain = cookie.domain;
    final path = cookie.path;
    return origins.contains(origin.toString()) &&
        domain != null &&
        domain.replaceFirst(RegExp(r'^\.'), '') == origin.host &&
        path != null &&
        path.startsWith('/') &&
        (origin.path == path ||
            origin.path.startsWith(path.endsWith('/') ? path : '$path/')) &&
        cookie.name.isNotEmpty &&
        cookie.value is String &&
        cookie.isSecure != null &&
        cookie.isHttpOnly != null &&
        (cookie.expiresDate == null ||
            cookie.expiresDate! > now.millisecondsSinceEpoch);
  }

  Future<void> restorePortalSession() async {
    final saved = await _readPortal();
    if (saved == null) return;
    if (saved['version'] != 2) return;
    final manager = CookieManager.instance();
    final restored = <String>{};
    for (final snapshot in saved['snapshots'] as List? ?? []) {
      final origin = Uri.tryParse('${snapshot['observedUrl']}');
      if (origin == null || !origins.contains(origin.toString())) continue;
      final current = await manager.getCookies(url: WebUri(origin.toString()));
      for (final item in snapshot['cookies'] as List? ?? []) {
        final cookie = Cookie.fromMap(Map<String, dynamic>.from(item as Map));
        if (cookie == null ||
            !canRestoreCookie(origin, cookie, DateTime.now())) {
          continue;
        }
        final key = '${cookie.domain}|${cookie.path}|${cookie.name}';
        if (!restored.add(key) ||
            current.any(
              (c) => c.name == cookie.name && c.path == cookie.path,
            )) {
          continue;
        }
        await manager.setCookie(
          url: WebUri(origin.toString()),
          name: cookie.name,
          value: cookie.value as String,
          domain: cookie.domain,
          path: cookie.path!,
          expiresDate: cookie.expiresDate,
          isSecure: cookie.isSecure,
          isHttpOnly: cookie.isHttpOnly,
          sameSite: cookie.sameSite,
        );
      }
    }
  }

  Future<String?> displayName() async {
    final data = await _readPortal();
    if (data == null) return null;
    final value = data['displayName'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  Future<DateTime?> connectionTime() async {
    final data = await _readPortal();
    if (data == null) return null;
    return DateTime.tryParse(data['capturedAt'] as String? ?? '')?.toLocal();
  }

  Future<void> clear() async {
    // This app's WebView is dedicated to school login; it is not the system
    // browser cookie store. Do not call the school's global logout endpoint.
    await CookieManager.instance().deleteAllCookies();
    await WebStorageManager.instance().deleteAllData();
    await _secure.delete(key: _key);
    _portalRead = Future.value(null);
  }
}
