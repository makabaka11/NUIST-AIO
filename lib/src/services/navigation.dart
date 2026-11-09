/// Shared policy for visible and background school SSO pages.
class SchoolNavigation {
  static final cardEntry = Uri.https(
    'icard.nuist.edu.cn',
    '/berserker-auth/cas/login/wisedu',
    {'targetUrl': 'https://icard.nuist.edu.cn/plat-pc/?name=loginTransit'},
  );
  static final scheduleEntry = Uri.parse(
    'https://jwxt.nuist.edu.cn/jwapp/sys/wdkb/*default/index.do?EMAP_LANG=zh#/xskcb',
  );
  static bool trusted(Uri? uri, Set<String> hosts) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      hosts.contains(uri.host);

  static bool card(Uri? uri) {
    if (!trusted(uri, {
      'authserver.nuist.edu.cn',
      'i.nuist.edu.cn',
      'icard.nuist.edu.cn',
    })) {
      return false;
    }
    if (uri!.host != 'icard.nuist.edu.cn') return true;
    return uri.path.startsWith('/berserker-auth/') ||
        uri.path == '/plat-pc' ||
        uri.path.startsWith('/plat-pc/') ||
        uri.path == '/campus-card-pc/campusCard' ||
        uri.path == '/campus-card-pc/billing';
  }

  static bool schedule(Uri? uri) => trusted(uri, {
    'authserver.nuist.edu.cn',
    'i.nuist.edu.cn',
    'jwxt.nuist.edu.cn',
  });

  /// Some school reverse proxies return HTTP login redirects even when the
  /// incoming connection is HTTPS. Cancel that navigation and reload HTTPS;
  /// never allow credentials onto cleartext or change the destination host.
  static Uri? httpsUpgrade(Uri? uri, bool Function(Uri?) allowed) {
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return null;
    }
    final secure = uri.replace(scheme: 'https');
    return allowed(secure) ? secure : null;
  }

  // No query strings/fragments: CAS tickets and business tokens occur there.
  static String safeLocation(Uri? uri) =>
      uri == null ? '未知页面' : '${uri.scheme}://${uri.host}${uri.path}';
}
