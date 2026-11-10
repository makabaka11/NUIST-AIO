import '../services/navigation.dart';
import '../services/service_sessions.dart';
import '../services/site_registry.dart';

enum CampusNetworkMode { automatic, direct, vpn }

enum CampusPath { direct, vpn }

class CampusRoute {
  const CampusRoute._(this.origin, this.proxy);
  final Uri origin, proxy;
  static CampusRoute fromDirectory(String source, String target) {
    final origin = Uri.parse(source), proxy = Uri.parse(target);
    final supported = SchoolSites.all.any(
      (s) => s.networkRouting && s.host == origin.host,
    );
    if (!supported ||
        origin.scheme != 'https' ||
        origin.hasPort ||
        origin.path.isNotEmpty && origin.path != '/' ||
        origin.hasQuery ||
        origin.hasFragment ||
        origin.userInfo.isNotEmpty ||
        !SchoolNavigation.trusted(proxy, {'client.vpn.nuist.edu.cn'}) ||
        proxy.hasQuery ||
        proxy.hasFragment ||
        !RegExp(r'^/https/webvpn[0-9a-f]{64}/?$').hasMatch(proxy.path)) {
      throw const FormatException('学校 VPN 资源映射未通过校验。');
    }
    return CampusRoute._(
      origin,
      proxy.replace(path: proxy.path.replaceFirst(RegExp(r'/$'), '')),
    );
  }

  static bool _safePath(Uri url) => !url.pathSegments.any(
    (s) => s == "." || s == ".." || s.contains("/") || s.contains("\\"),
  );
  Uri resolve(Uri url) {
    if (url.origin != origin.origin ||
        url.userInfo.isNotEmpty ||
        !_safePath(url)) {
      throw const FormatException('链接超出当前学校资源范围。');
    }
    return proxy.replace(
      path: proxy.path + url.path,
      query: url.hasQuery ? url.query : null,
      fragment: url.hasFragment ? url.fragment : null,
    );
  }

  bool accepts(Uri? url) =>
      url != null &&
      SchoolNavigation.trusted(url, {'client.vpn.nuist.edu.cn'}) &&
      _safePath(url) &&
      (url.path == proxy.path || url.path.startsWith('${proxy.path}/'));
}

class CampusResponse {
  const CampusResponse(this.data, this.path, {this.route});
  final Map<String, dynamic> data;
  final CampusPath path;
  final CampusRoute? route;
}

/// Campus-network sites use this broker. Each new service must be registered
/// and provide a route-aware adapter before its VPN mapping can be used.
class BulletinRepository {
  BulletinRepository({
    ServiceSession? direct,
    ServiceSession? vpn,
    ServiceSession Function(SchoolSite)? proxyFactory,
  }) : direct =
           direct ??
           NativeServiceSession(
             site: SchoolSites.get(SchoolSiteId.bulletin),
             connectionTimeout: const Duration(seconds: 12),
           ),
       vpn =
           vpn ?? NativeServiceSession(site: SchoolSites.get(SchoolSiteId.vpn)),
       proxyFactory =
           proxyFactory ??
           ((site) => NativeServiceSession(
             site: site,
             connectionTimeout: const Duration(seconds: 20),
           ));
  final ServiceSession direct, vpn;
  final ServiceSession Function(SchoolSite) proxyFactory;
  ServiceSession? _proxy;
  CampusRoute? _route;
  int _generation = 0;
  Future<void> close() async {
    _generation++;
    final proxy = _proxy;
    _proxy = null;
    _route = null;
    await Future.wait([
      direct.close(),
      vpn.close(),
      if (proxy != null) proxy.close(),
    ]);
  }

  Future<CampusResponse> query(
    CampusNetworkMode mode,
    String task, {
    Uri? url,
  }) async {
    final generation = _generation;
    final canonical = url ?? SchoolSites.get(SchoolSiteId.bulletin).entry!;
    if (!SchoolNavigation.bulletin(canonical)) {
      throw const FormatException('公告链接不在学校站点范围内。');
    }
    void valid() {
      if (generation != _generation) {
        throw const FormatException('网络或账号已变化，请重试。');
      }
    }

    if (mode != CampusNetworkMode.vpn) {
      try {
        final data = await direct.query(task, {
          'params': {'url': canonical.toString()},
        });
        valid();
        if (data['ok'] != true) throw const FormatException('公告页面未返回有效内容。');
        return CampusResponse(data, CampusPath.direct);
      } catch (_) {
        valid();
        if (mode == CampusNetworkMode.direct) rethrow;
      }
    }
    try {
      final probe = await vpn.query('probe', {});
      valid();
      if (probe['ok'] != true || probe['ready'] != true) {
        throw const FormatException('请先连接学校 VPN。');
      }
      final routes = Map<String, dynamic>.from(probe['routes'] as Map? ?? {}),
          target = routes['https://bulletin.nuist.edu.cn'];
      if (target is! String) {
        throw const FormatException('学校 VPN 目录未提供公告板，请在官方入口确认访问权限。');
      }
      final route = CampusRoute.fromDirectory(
        'https://bulletin.nuist.edu.cn',
        target,
      );
      if (_route?.proxy != route.proxy) {
        final old = _proxy;
        _proxy = null;
        _route = route;
        await old?.close();
        valid();
        _proxy = proxyFactory(
          SchoolSite(
            id: SchoolSiteId.bulletin,
            label: '公告板 · VPN',
            auth: SiteAuth.campusNetwork,
            host: route.proxy.host,
            entry: route.resolve(SchoolSites.get(SchoolSiteId.bulletin).entry!),
            features: const [],
            credentialRule: '复用学校网关会话，不复制 Cookie。',
            renewalRule: '重新验证网关目录后按需续接。',
            asset: 'assets/js/nuist_bulletin.js',
            probeTask: 'list',
            probePrefixes: ['${route.proxy.path}/'],
            navigation: (uri) =>
                route.accepts(uri) || SchoolNavigation.vpnResourceAuth(uri),
            onDemand: true,
            networkRouting: true,
          ),
        );
      }
      final data = await _proxy!.query(task, {
        'params': {'url': canonical.toString()},
      });
      valid();
      if (data['ok'] != true) {
        throw FormatException('${data['error'] ?? 'VPN 公告读取失败。'}');
      }
      return CampusResponse(data, CampusPath.vpn, route: route);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('校外访问需要学校 VPN 会话，请在网络设置中连接 VPN 后重试。');
    }
  }
}
