import '../campus_ui.dart';

import '../app_state.dart';
import '../theme_settings.dart' show uiAction;
import '../widgets.dart';
import 'campus_network.dart';
import 'vpn_page.dart';

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
          const Text(
            '当前支持公告板；功能页的内网外部入口可单独选择 VPN 打开。学校网关会话独立验证，系统浏览器可能需要再次登录。',
          ),
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
                  CampusNetworkMode.automatic => '先验证直连，失败后尝试学校 WebVPN',
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
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const VpnLoginPage(),
                      ),
                    );
                    if (mounted) test(mode: CampusNetworkMode.vpn);
                  },
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('连接 / 重新验证学校 VPN'),
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
          const SectionTitle('后续站点'),
          const Text('新站点必须先核实官方直连地址、VPN 资源映射和页面读取规则，再加入切换清单。尚未接入的站点不会自动改写地址。'),
        ],
      ),
    ),
  );
}
