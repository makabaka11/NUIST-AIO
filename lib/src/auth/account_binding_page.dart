import '../campus_ui.dart';
import '../app_state.dart';
import '../chaoxing/chaoxing_page.dart';
import '../network/vpn_page.dart';
import '../widgets.dart';
import '../theme_settings.dart' show uiAction;
import 'login_page.dart';
import 'passkey_page.dart';

class AccountBindingPage extends StatefulWidget {
  const AccountBindingPage({super.key, required this.state});
  final AppState state;
  @override
  State<AccountBindingPage> createState() => _AccountBindingPageState();
}

class _AccountBindingPageState extends State<AccountBindingPage> {
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.state.refreshPasskey();
  }

  Future<void> toggle(bool enabled) async {
    if (busy) return;
    setState(() => busy = true);
    await uiAction(context, () async {
      if (enabled) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PasskeyPage(state: widget.state),
          ),
        );
      } else {
        await widget.state.disablePasskey();
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('账号绑定')),
      body: PageBody(
        children: [
          const SectionTitle('统一认证'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('统一认证账号'),
                  subtitle: Text(
                    widget.state.connectedAt == null ? '尚未连接' : '已保存会话 · 可重新登录',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => LoginPage(state: widget.state),
                          ),
                        ),
                ),
                SwitchListTile(
                  title: const Text('使用通行密钥自动登录'),
                  subtitle: const Text(
                    '密钥仅在本机加密保存，可增强连接稳定性。关闭会删除本机密钥，学校端记录可在账户安全中删除。',
                  ),
                  value: widget.state.passkeyEnabled,
                  onChanged: busy || widget.state.connectedAt == null
                      ? null
                      : toggle,
                ),
                if (widget.state.passkeyEnabled)
                  ListTile(
                    title: const Text('使用通行密钥重新连接'),
                    subtitle: Text(
                      widget.state.servicesNotice ?? '验证主账号后初始化校园服务',
                    ),
                    onTap: widget.state.connectingServices
                        ? null
                        : () => widget.state.connectCampusServices(
                            forcePasskey: true,
                          ),
                  ),
              ],
            ),
          ),
          const SectionTitle('学习通账号'),
          Card(child: ChaoxingAccountTile(state: widget.state)),
          const SectionTitle('VPN 账号'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('学校 WebVPN'),
              subtitle: const Text('复用统一认证与通行密钥，连接后独立验证授权目录'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        if (widget.state.passkeyEnabled) {
                          await widget.state.ensurePortal();
                        }
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const VpnLoginPage(),
                          ),
                        );
                        await widget.state.bulletins.vpn.close();
                        widget.state.networkLinks.reset();
                        await widget.state.detectNetworkLinks();
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    final remove = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('移除本机登录会话？'),
                        content: const Text(
                          '将清除通行密钥、全部业务会话、课表与个人数据缓存。学校端通行密钥记录需自行删除。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('移除'),
                          ),
                        ],
                      ),
                    );
                    if (remove == true && context.mounted) {
                      await uiAction(context, widget.state.disconnect);
                    }
                  },
            child: const Text('移除全部本机会话'),
          ),
        ],
      ),
    ),
  );
}
