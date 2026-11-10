/// Shared policy for visible and background school SSO pages.
class SchoolNavigation {
  static final portalCasEntry = Uri.https(
    'authserver.nuist.edu.cn',
    '/authserver/login',
    {'service': 'https://i.nuist.edu.cn/login#/'},
  );
  static bool portalCalendar(Uri? uri) =>
      trusted(uri, {'i.nuist.edu.cn', 'authserver.nuist.edu.cn'});
  static final vpnEntry = Uri.parse(
    'https://client.vpn.nuist.edu.cn/enlink/#/client/app',
  );
  static final vpnCasEntry = Uri.https(
    'authserver.nuist.edu.cn',
    '/authserver/login',
    {
      'service':
          'https://client.vpn.nuist.edu.cn/enlink/api/client/callback/cas',
    },
  );
  static bool vpn(Uri? uri) =>
      trusted(uri, {'authserver.nuist.edu.cn', 'client.vpn.nuist.edu.cn'});
  // Observed gateway relay needed before a proxied resource receives its session.
  static bool vpnResourceAuth(Uri? uri) =>
      trusted(uri, {'client.vpn.nuist.edu.cn'}) &&
          {
            '/enlink/sso/login',
            '/engateway/api/sso/authorized',
            '/enlink/',
            '/enlink/api/client/callback/cas',
          }.contains(uri!.path) ||
      trusted(uri, {'authserver.nuist.edu.cn'}) &&
          uri!.path.startsWith('/authserver/');
  // Begin at the relying party so its own CAS/CSRF context is established.
  static final libraryCasEntry = Uri.https(
    'elib.nuist.edu.cn',
    '/meta-local/opac/cas/rosetta',
  );
  static bool library(Uri? uri) =>
      trusted(uri, {'elib.nuist.edu.cn', 'authserver.nuist.edu.cn'});
  static bool bulletin(Uri? uri) => trusted(uri, {'bulletin.nuist.edu.cn'});
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
