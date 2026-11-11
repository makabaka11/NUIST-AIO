import '../campus_ui.dart';

import '../academic/official_page.dart';
import '../app_state.dart';
import '../network/campus_network.dart';
export '../network/external_link_route.dart' show externalVpnUri;
import 'site_registry.dart';

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
  Future<void> open() async {
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
      final url = await widget.state.resolveBrowserLink(link);
      if (mounted && generation == widget.state.sessionGeneration) {
        await launchSchoolBrowser(context, url);
      }
    } on FormatException catch (e) {
      if (mounted) {
        showCampusSnackBar(context, SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        showCampusSnackBar(
          context,
          const SnackBar(content: Text('入口暂不可用，请稍后重试或从学校 VPN 首页进入。')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => ListTile(
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
      subtitle: Text(
        widget.link.vpn
            ? '${widget.link.detail} · ${_routeLabel()}'
            : widget.link.detail,
      ),
      onTap: busy ? null : open,
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.link.vpn
          ? IconButton(
              tooltip: '按当前网络配置在浏览器打开',
              onPressed: open,
              icon: const Icon(Icons.open_in_browser_outlined),
            )
          : Icon(
              widget.link.instructions != null
                  ? Icons.info_outline
                  : Icons.open_in_new,
            ),
    ),
  );
  String _routeLabel() {
    final mode = widget.state.networkMode;
    if (mode == CampusNetworkMode.direct) return '手动直连';
    if (mode == CampusNetworkMode.vpn) return '手动 VPN';
    final detector = widget.state.networkLinks,
        status = detector.results[widget.link.id];
    if (status?.path == CampusPath.direct) return '自动：直连';
    if (status?.path == CampusPath.vpn) return '自动：VPN';
    if (detector.checking) return '正在检测链路';
    return status?.error == null ? '待检测链路' : '链路不可用';
  }
}
