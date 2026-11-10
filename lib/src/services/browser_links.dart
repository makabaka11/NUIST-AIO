import '../campus_ui.dart';

import '../academic/official_page.dart';
import '../app_state.dart';
import '../network/campus_network.dart';
import 'site_registry.dart';
import 'navigation.dart';

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

class SchoolBrowserEntryTile extends StatefulWidget {
  const SchoolBrowserEntryTile({
    super.key,
    required this.link,
    required this.state,
  });
  final SchoolBrowserLink link;
  final AppState state;
  @override
  State<SchoolBrowserEntryTile> createState() => _SchoolBrowserEntryTileState();
}

class _SchoolBrowserEntryTileState extends State<SchoolBrowserEntryTile> {
  bool busy = false;
  Future<void> open({bool vpn = false}) async {
    if (busy) return;
    final link = widget.link;
    if (link.instructions != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(link.name),
          content: Text(link.instructions!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => busy = true);
    final generation = widget.state.sessionGeneration;
    try {
      var url = link.resolve(
        number: widget.state.studentProfile?.studentNumber,
      );
      if (vpn) {
        final probe = await widget.state.bulletins.vpn.query('probe', {});
        if (!mounted || generation != widget.state.sessionGeneration) return;
        if (probe['ok'] != true || probe['ready'] != true) {
          throw const FormatException('请先在网络设置连接学校 VPN，或在系统浏览器打开学校 VPN 首页。');
        }
        url = externalVpnUri(
          url,
          Map<String, dynamic>.from(probe['routes'] as Map? ?? {}),
        );
      }
      if (mounted && generation == widget.state.sessionGeneration) {
        await launchSchoolBrowser(context, url);
      }
    } on FormatException catch (e) {
      if (mounted) {
        showCampusSnackBar(context, SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        showCampusSnackBar(context, 
          const SnackBar(content: Text('入口暂不可用，请稍后重试或从学校 VPN 首页进入。')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: Icon(
      widget.link.instructions != null
          ? Icons.chat_bubble_outline
          : widget.link.id == 'campusBus'
          ? Icons.directions_bus_outlined
          : Icons.open_in_new,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: Text(widget.link.name),
    subtitle: Text(widget.link.detail),
    onTap: busy
        ? null
        : () => open(
            vpn:
                widget.link.vpn &&
                widget.state.networkMode == CampusNetworkMode.vpn,
          ),
    trailing: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.link.vpn
        ? IconButton(
            tooltip: '通过学校 WebVPN 在浏览器打开',
            onPressed: () => open(vpn: true),
            icon: const Icon(Icons.vpn_lock_outlined),
          )
        : Icon(
            widget.link.instructions != null
                ? Icons.info_outline
                : Icons.open_in_new,
          ),
  );
}
