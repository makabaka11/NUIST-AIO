import '../services/site_registry.dart';
import '../services/navigation.dart';

Uri externalVpnUri(Uri original, Map<String, dynamic> routes) {
  if (!SchoolBrowserLinks.all.any(
    (l) => l.vpn && l.entry?.origin == original.origin,
  )) {
    throw const FormatException('该站点尚未登记 VPN 入口。');
  }
  final value = routes[original.origin];
  if (value is! String) {
    throw const FormatException('学校授权目录没有此站点，请在系统浏览器的 VPN 首页确认访问权限。');
  }
  final proxy = Uri.tryParse(value);
  if (proxy == null ||
      !SchoolNavigation.trusted(proxy, {'client.vpn.nuist.edu.cn'}) ||
      proxy.hasQuery ||
      proxy.hasFragment ||
      !RegExp('^/${original.scheme}/webvpn[0-9a-f]{64}\$')
          .hasMatch(proxy.path)) {
    throw const FormatException('学校 VPN 入口未通过校验。');
  }
  return proxy.replace(
    path: proxy.path + original.path,
    query: original.hasQuery ? original.query : null,
    fragment: original.hasFragment ? original.fragment : null,
  );
}
