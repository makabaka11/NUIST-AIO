import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:nuist_aio/src/notifications/notification_poster.dart';
import 'package:nuist_aio/src/notifications/notification_settings.dart';

class FakePoster implements NotificationPoster {
  FakePoster({this.granted = true});
  bool granted;
  int requests = 0;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<void> show(NotifyKind kind, int id, String title, String body) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('默认值', () {
    test('除登录失效外全部关闭', () async {
      final settings = NotificationSettings();
      await settings.load();
      for (final kind in NotifyKind.values) {
        expect(settings.isEnabled(kind), kind == NotifyKind.authFailure,
            reason: '${kind.label} 默认开关不符');
      }
      expect(settings.anyPollingEnabled, isFalse);
      expect(settings.electricityThreshold,
          NotificationSettings.defaultThreshold);
    });
  });

  group('持久化', () {
    test('开关与阈值可回读', () async {
      final first = NotificationSettings();
      await first.load();
      await first.setEnabled(NotifyKind.chaoxingWork, true);
      await first.setEnabled(NotifyKind.authFailure, false);
      await first.setElectricityThreshold(18.5);

      final second = NotificationSettings();
      await second.load();
      expect(second.isEnabled(NotifyKind.chaoxingWork), isTrue);
      expect(second.isEnabled(NotifyKind.authFailure), isFalse);
      expect(second.isEnabled(NotifyKind.bulletins), isFalse);
      expect(second.electricityThreshold, 18.5);
      expect(second.anyPollingEnabled, isTrue);
    });

    test('阈值写入超出范围时收敛到边界', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setElectricityThreshold(999);
      expect(settings.electricityThreshold, NotificationSettings.maxThreshold);
      await settings.setElectricityThreshold(0);
      expect(settings.electricityThreshold, NotificationSettings.minThreshold);
    });
  });

  group('Poster 注入', () {
    test('构造时可注入测试用 Poster', () {
      final poster = FakePoster();
      final settings = NotificationSettings(poster: poster);
      expect(identical(settings.poster, poster), isTrue);
    });
  });
}
