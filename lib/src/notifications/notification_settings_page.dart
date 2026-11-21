import '../campus_ui.dart';

import '../app_state.dart';
import '../theme_settings.dart' show uiAction;
import '../widgets.dart';
import 'notification_poster.dart';
import 'notification_settings.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.state});
  final AppState state;
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  /// null 表示尚未检测；不支持通知的平台无需展示权限行。
  bool? permissionGranted;

  NotificationSettings get settings => widget.state.notifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermission());
  }

  Future<void> _refreshPermission() async {
    if (!notificationPlatformSupported() || !mounted) return;
    final granted = await settings.poster.permissionGranted();
    if (mounted) setState(() => permissionGranted = granted);
  }

  Future<void> _toggle(NotifyKind kind, bool value) async {
    if (value && notificationPlatformSupported()) {
      // 开启任何通知项前先申请系统权限；被拒绝则不保存开关。
      final granted = await settings.poster.requestPermission();
      if (mounted) setState(() => permissionGranted = granted);
      if (!granted) {
        if (mounted) {
          showCampusSnackBar(
            context,
            const SnackBar(
              content: Text('系统未授予通知权限，请在系统设置中允许信大AIO通知后再开启。'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    await uiAction(context, () => settings.setEnabled(kind, value));
    if (value) widget.state.notificationCenter?.start();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知设置')),
    body: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => PageBody(
        children: [
          if (notificationPlatformSupported()) ...[
            const SectionTitle('系统权限'),
            PreferenceGroup(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('通知权限'),
                  subtitle: Text(
                    permissionGranted == null
                        ? '正在检测…'
                        : permissionGranted!
                        ? '已授权，可以接收系统通知'
                        : '未授权，开启通知项时将申请；被拒后需前往系统设置开启',
                  ),
                  trailing: permissionGranted == true
                      ? const Icon(Icons.check_circle_outline)
                      : TextButton(
                          onPressed: () => _refreshPermission(),
                          child: const Text('重新检测'),
                        ),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '当前平台不支持系统通知，以下设置将在 Android / iOS 客户端上生效。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SectionTitle('通知项目'),
          PreferenceGroup(
            children: [
              PreferenceSwitchRow(
                title: '学习通作业提醒',
                subtitle: '新作业发布且未完成时；未完成作业距截止约 5 / 3 / 1 天时',
                value: settings.isEnabled(NotifyKind.chaoxingWork),
                onChanged: (value) => _toggle(NotifyKind.chaoxingWork, value),
              ),
              PreferenceSwitchRow(
                title: '新公告提醒',
                subtitle: '学校公告板出现新公告时',
                value: settings.isEnabled(NotifyKind.bulletins),
                onChanged: (value) => _toggle(NotifyKind.bulletins, value),
              ),
              PreferenceSwitchRow(
                title: '电费预警',
                subtitle: '宿舍剩余电量（度）低于阈值时提醒一次',
                value: settings.isEnabled(NotifyKind.electricity),
                onChanged: (value) => _toggle(NotifyKind.electricity, value),
              ),
              PreferenceSwitchRow(
                title: '新考试发布',
                subtitle: '本学期教务发布新考试安排时',
                value: settings.isEnabled(NotifyKind.exams),
                onChanged: (value) => _toggle(NotifyKind.exams, value),
              ),
              PreferenceSwitchRow(
                title: '新成绩发布',
                subtitle: '教务发布新成绩时',
                value: settings.isEnabled(NotifyKind.grades),
                onChanged: (value) => _toggle(NotifyKind.grades, value),
              ),
              PreferenceSwitchRow(
                title: '登录失效提醒',
                subtitle: '统一认证会话失效时提醒（默认开启）',
                value: settings.isEnabled(NotifyKind.authFailure),
                onChanged: (value) => _toggle(NotifyKind.authFailure, value),
              ),
            ],
          ),
          if (settings.isEnabled(NotifyKind.electricity)) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '预警阈值 · ${settings.electricityThreshold.toStringAsFixed(1)} 度',
                          ),
                        ),
                        TextButton(
                          onPressed: () => uiAction(
                            context,
                            () => settings.setElectricityThreshold(
                              NotificationSettings.defaultThreshold,
                            ),
                          ),
                          child: const Text('恢复默认'),
                        ),
                      ],
                    ),
                    Slider(
                      key: const ValueKey('electricity-threshold-slider'),
                      value: settings.electricityThreshold,
                      min: NotificationSettings.minThreshold,
                      max: NotificationSettings.maxThreshold,
                      divisions: 58,
                      label:
                          '阈值 ${settings.electricityThreshold.toStringAsFixed(1)} 度',
                      onChanged: (value) => settings.setElectricityThreshold(
                        value,
                        persist: false,
                      ),
                      onChangeEnd: (value) => uiAction(
                        context,
                        () => settings.setElectricityThreshold(value),
                      ),
                    ),
                    Text(
                      '剩余电量低于该值时提醒一次，充电回升后自动重新警戒。部分宿舍电费以金额（元）显示，暂不支持阈值提醒。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SectionTitle('工作方式'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  const Text(
                    '· 启用后，应用在后台保持存活期间每约 1 小时自动检查一次启用项；被系统回收后检查暂停，回到前台时会择机补查。',
                  ),
                  const Text(
                    '· 登录失效提醒为事件触发，无需等待轮询。',
                  ),
                  const Text('· 首次启用某项时，当前已有数据不会补发通知，只提醒之后的新变化。'),
                  const Text('· 学习通作业提醒需要先连接学习通并完成一次课程扫描；电费预警需要已选择实际宿舍。'),
                  const SizedBox(height: 6),
                  Text(
                    '通知仅在本机生成与展示，不向任何服务器上报提醒数据。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
