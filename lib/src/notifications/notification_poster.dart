import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_settings.dart';

/// 系统通知投递与权限申请的唯一入口。业务层不直接触碰平台插件。
abstract class NotificationPoster {
  /// 申请系统通知权限（Android 13+ 运行时权限 / iOS 弹窗）。
  /// 返回是否已授权；平台不支持或失败时返回 false。
  Future<bool> requestPermission();

  /// 查询当前是否已授权。尽量不触发弹窗；Android 永久拒绝时只返回 false。
  Future<bool> permissionGranted();

  /// 立即投递一条本地系统通知。失败静默，轮询周期会再次尝试。
  Future<void> show(NotifyKind kind, int id, String title, String body);
}

/// 系统通知仅在 Android / iOS 上开放；其他平台（含 Web 与桌面）不申请权限、
/// 不投递通知。
bool notificationPlatformSupported() =>
    !kIsWeb &&
    const {TargetPlatform.android, TargetPlatform.iOS}.contains(
      defaultTargetPlatform,
    );

NotificationPoster defaultNotificationPoster() =>
    notificationPlatformSupported()
        ? LocalNotificationPoster()
        : const UnsupportedNotificationPoster();

/// 不支持平台使用的空实现，保证业务层无需判空。
class UnsupportedNotificationPoster implements NotificationPoster {
  const UnsupportedNotificationPoster();
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> permissionGranted() async => false;
  @override
  Future<void> show(NotifyKind kind, int id, String title, String body) async {}
}

class LocalNotificationPoster implements NotificationPoster {
  LocalNotificationPoster();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // 权限统一在用户开启通知项时显式申请，初始化阶段不弹窗。
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );    } catch (_) {
      // 初始化失败时权限与投递均按 false 处理，不向业务层抛错。
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!notificationPlatformSupported()) return false;
    await _initialize();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        return granted ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? false;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  @override
  Future<bool> permissionGranted() async {
    if (!notificationPlatformSupported()) return false;
    await _initialize();
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final options = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return options?.isEnabled ?? false;
      }
      // Android：已授权时该调用直接返回 true，不会重复弹窗。
      return await requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show(NotifyKind kind, int id, String title, String body) async {
    if (!notificationPlatformSupported()) return;
    await _initialize();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kind.channelId,
            kind.label,
            channelDescription: kind.description,
            importance: kind.urgent
                ? Importance.high
                : Importance.defaultImportance,
            priority: kind.urgent ? Priority.high : Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      // 单条投递失败静默；下一轮询周期会重新评估。
    }
  }
}
