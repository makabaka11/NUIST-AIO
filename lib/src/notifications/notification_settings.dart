import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_poster.dart';

/// 通知分类。除 [authFailure]（登录失效提醒）外，其余默认关闭，
/// 由用户在「我的 → 偏好设置 → 通知设置」中按需开启。
enum NotifyKind {
  chaoxingWork(
    'chaoxingWork',
    '学习通作业提醒',
    'chaoxing_work_reminders',
    '学习通新作业发布与截止前提醒',
  ),
  bulletins('bulletins', '新公告提醒', 'bulletin_reminders', '学校公告板新公告提醒'),
  electricity('electricity', '电费预警', 'electricity_alerts', '宿舍电量低于阈值提醒'),
  exams('exams', '新考试发布', 'exam_reminders', '教务新考试安排提醒'),
  grades('grades', '新成绩发布', 'grade_reminders', '教务新成绩发布提醒'),
  authFailure(
    'authFailure',
    '登录失效提醒',
    'auth_failure_alerts',
    '统一认证失效提醒',
    urgent: true,
  );

  const NotifyKind(
    this.name,
    this.label,
    this.channelId,
    this.description, {
    this.urgent = false,
  });

  final String name;
  final String label;

  /// Android 通知渠道 ID；用户可在系统设置中按渠道单独控制。
  final String channelId;
  final String description;

  /// 登录失效使用高优先级渠道，其余使用默认优先级。
  final bool urgent;

  /// 是否依赖轮询获取数据；登录失效为事件驱动，不参与轮询。
  bool get polling => this != authFailure;
}

/// 电费预警阈值（单位：度），支持范围与默认值。
class NotificationSettings extends ChangeNotifier {
  NotificationSettings({NotificationPoster? poster})
    : poster = poster ?? defaultNotificationPoster();

  /// 系统通知投递与权限申请入口。
  final NotificationPoster poster;

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final Map<NotifyKind, bool> enabled = {
    for (final kind in NotifyKind.values) kind: kind == NotifyKind.authFailure,
  };

  double electricityThreshold = defaultThreshold;
  static const double defaultThreshold = 10;
  static const double minThreshold = 1;
  static const double maxThreshold = 30;

  bool _disposed = false;

  bool isEnabled(NotifyKind kind) => enabled[kind] ?? false;
  bool get anyPollingEnabled => NotifyKind.values.any(
    (kind) => kind.polling && isEnabled(kind),
  );

  Future<void> load() async {
    try {
      for (final kind in NotifyKind.values) {
        enabled[kind] =
            await _prefs.getBool('notify.${kind.name}') ??
            (kind == NotifyKind.authFailure);
      }
      final stored = await _prefs.getDouble('notify.electricityThreshold');
      if (stored != null && stored.isFinite) {
        electricityThreshold = stored.clamp(minThreshold, maxThreshold);
      }
    } catch (_) {
      // 通知是可选功能，偏好读取失败不得阻塞启动。
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> setEnabled(NotifyKind kind, bool value) async {
    try {
      await _prefs.setBool('notify.${kind.name}', value);
    } catch (_) {
      // 写入失败仍更新内存值；下一轮启动按默认/旧值恢复。
    }
    enabled[kind] = value;
    if (!_disposed) notifyListeners();
  }

  /// [persist] 为 false 时仅预览（拖动滑块过程中），松手时再持久化。
  Future<void> setElectricityThreshold(double value, {bool persist = true}) async {
    final next = value.isFinite
        ? value.clamp(minThreshold, maxThreshold)
        : electricityThreshold;
    electricityThreshold = next;
    if (!_disposed) notifyListeners();
    if (!persist) return;
    try {
      await _prefs.setDouble('notify.electricityThreshold', next);
    } catch (_) {
      // 同上，静默即可。
    }
  }
}
