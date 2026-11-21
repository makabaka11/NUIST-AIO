import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/notifications/notification_poster.dart';
import 'package:nuist_aio/src/notifications/notification_settings.dart';
import 'package:nuist_aio/src/notifications/notification_settings_page.dart';

class FakePoster implements NotificationPoster {
  FakePoster({this.granted = true});
  bool granted;
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
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
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AppState> mount(
    WidgetTester tester,
    FakePoster poster, {
    bool grantPermission = true,
  }) async {
    poster.granted = grantPermission;
    final state = AppState(
      notificationSettings: NotificationSettings(poster: poster),
    );
    await state.load();
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsPage(state: state)),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('默认仅登录失效开启，权限行展示已授权', (tester) async {
    final state = await mount(tester, FakePoster());
    expect(state.notifications.isEnabled(NotifyKind.authFailure), isTrue);
    for (final kind in NotifyKind.values.where((k) => k != NotifyKind.authFailure)) {
      expect(state.notifications.isEnabled(kind), isFalse);
    }
    expect(find.text('通知权限'), findsOneWidget);
    expect(find.text('已授权，可以接收系统通知'), findsOneWidget);
  });

  testWidgets('开启通知项时申请权限，被拒绝则开关回退并提示', (tester) async {
    final state = await mount(tester, FakePoster(), grantPermission: false);
    expect(find.text('学习通作业提醒'), findsOneWidget);

    await tester.tap(find.text('学习通作业提醒'));
    await tester.pumpAndSettle();

    expect(state.notifications.isEnabled(NotifyKind.chaoxingWork), isFalse,
        reason: '权限被拒时不保存开关');
    final opened = tester
        .widget<SwitchListTile>(
          find.ancestor(
            of: find.text('学习通作业提醒'),
            matching: find.byType(SwitchListTile),
          ),
        )
        .value;
    expect(opened, isFalse);
    expect(find.textContaining('系统未授予通知权限'), findsOneWidget);
  });

  testWidgets('权限通过后开关保存', (tester) async {
    final poster = FakePoster();
    final state = await mount(tester, poster, grantPermission: true);
    await tester.tap(find.text('新公告提醒'));
    await tester.pumpAndSettle();
    expect(state.notifications.isEnabled(NotifyKind.bulletins), isTrue);

    // 关闭时无需再次申请权限。
    await tester.tap(find.text('新公告提醒'));
    await tester.pumpAndSettle();
    expect(state.notifications.isEnabled(NotifyKind.bulletins), isFalse);
    expect(poster.permissionRequests, 1);
  });

  testWidgets('开启电费预警后出现阈值滑块', (tester) async {
    final state = await mount(tester, FakePoster());
    expect(find.byKey(const ValueKey('electricity-threshold-slider')), findsNothing);

    await tester.tap(find.text('电费预警'));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('electricity-threshold-slider'));
    await tester.scrollUntilVisible(slider, 300,
        scrollable: find.byType(Scrollable).first);
    expect(slider, findsOneWidget);
    expect(state.notifications.electricityThreshold,
        NotificationSettings.defaultThreshold);
    expect(find.text('预警阈值 · 10.0 度'), findsOneWidget);
  });

  testWidgets('阈值滑块拖动后持久化', (tester) async {
    final state = await mount(tester, FakePoster());
    await tester.tap(find.text('电费预警'));
    await tester.pumpAndSettle();

    final sliderFinder = find.byKey(
      const ValueKey('electricity-threshold-slider'),
    );
    await tester.scrollUntilVisible(sliderFinder, 300,
        scrollable: find.byType(Scrollable).first);
    // campus_ui 导出了自绘 Slider 包装，直接驱动其回调验证预览/落盘语义。
    final dynamic slider = tester.widget(sliderFinder);

    // 拖动过程：仅预览，不写盘。
    slider.onChanged!(5.0);
    await tester.pumpAndSettle();
    expect(state.notifications.electricityThreshold, 5.0);

    // 松手：持久化。
    slider.onChangeEnd!(5.0);
    await tester.pumpAndSettle();
    expect(state.notifications.electricityThreshold, 5.0);

    // 新实例读回持久化值。
    final reloaded = NotificationSettings();
    await reloaded.load();
    expect(reloaded.electricityThreshold, 5.0);
  });
}
