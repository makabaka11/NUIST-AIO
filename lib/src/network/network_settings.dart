import '../campus_ui.dart';

import '../app_state.dart';
import '../services/site_registry.dart';
import '../theme_settings.dart' show uiAction;
import '../widgets.dart';
import 'campus_network.dart';
import '../auth/account_binding_page.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key, required this.state});
  final AppState state;
  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  bool busy = false;
  String? status;
  Future<void> test({CampusNetworkMode? mode}) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final result = await widget.state.bulletins.query(
        mode ?? widget.state.networkMode,
        'list',
      );
      if (mounted) {
        setState(
          () => status =
              '公告板验证成功 · ${result.path == CampusPath.direct ? '校园直连' : '学校 WebVPN'}',
        );
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => status = e.message);
    } catch (_) {
      if (mounted) setState(() => status = '连接未完成，请检查网络或登录状态。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('网络设置')),
    body: ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => PageBody(
        children: [
          const SectionTitle('校内资源访问路径'),
          const Text('选择访问校内资源的网络路径。因为系统浏览器会话独立，使用 VPN 时可能需要再次登录。'),
          const SizedBox(height: 16),
          for (final mode in CampusNetworkMode.values)
            Card(
              child: ListTile(
                selected: widget.state.networkMode == mode,
                leading: Icon(
                  widget.state.networkMode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(switch (mode) {
                  CampusNetworkMode.automatic => '自动选择',
                  CampusNetworkMode.direct => '校园直连',
                  CampusNetworkMode.vpn => '学校 WebVPN',
                }),
                subtitle: Text(switch (mode) {
                  CampusNetworkMode.automatic => '检测各站点直连；不可达时使用学校 VPN 入口',
                  CampusNetworkMode.direct => '只使用学校原始地址，不自动切换',
                  CampusNetworkMode.vpn => '只使用官方授权资源的 WebVPN 地址',
                }),
                onTap: busy
                    ? null
                    : () async {
                        await uiAction(
                          context,
                          () => widget.state.setNetworkMode(mode),
                        );
                        if (mounted) setState(() => status = null);
                      },
              ),
            ),
          const SizedBox(height: 20),
          const SectionTitle('各站点打开链路'),
          Card(
            child: Column(
              children: [
                for (final link in SchoolBrowserLinks.all.where((l) => l.vpn))
                  ListTile(
                    title: Text(link.name),
                    subtitle: Text(_linkStatus(link)),
                  ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed:
                busy ||
                    widget.state.networkLinks.checking ||
                    widget.state.networkMode != CampusNetworkMode.automatic
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await widget.state.detectNetworkLinks(force: true);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            icon: const Icon(Icons.refresh),
            label: Text(
              widget.state.networkLinks.checking ? '正在检测链路…' : '重新检测自动链路',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AccountBindingPage(state: widget.state),
                      ),
                    );
                    if (mounted) {
                      await widget.state.bulletins.vpn.close();
                      widget.state.networkLinks.reset();
                      await widget.state.detectNetworkLinks();
                      if (mounted) test(mode: CampusNetworkMode.vpn);
                    }
                  },
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('前往账号绑定连接 VPN'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => test(),
            icon: const Icon(Icons.network_check),
            label: const Text('测试公告板访问'),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(status!),
            ),
        ],
      ),
    ),
  );
  String _linkStatus(SchoolBrowserLink link) {
    if (widget.state.networkMode == CampusNetworkMode.direct) {
      return '校园直连（手动固定）';
    }
    if (widget.state.networkMode == CampusNetworkMode.vpn) {
      return '学校 WebVPN（手动固定）';
    }
    final result = widget.state.networkLinks.results[link.id];
    if (result?.path == CampusPath.direct) return '自动选择：校园直连';
    if (result?.path == CampusPath.vpn) return '自动选择：学校 WebVPN（授权目录已验证）';
    if (widget.state.networkLinks.checking) return '正在检测可用链路…';
    return result?.error ?? '尚未检测，首次打开时会检测';
  }
}
