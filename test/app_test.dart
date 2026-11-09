import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_liquid_glass_nav_bar/flutter_liquid_glass_nav_bar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/accounts/accounts.dart';
import 'package:nuist_aio/src/accounts/accounts_page.dart';
import 'package:nuist_aio/src/accounts/dorm_picker.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/auth/invite_codes.dart';
import 'package:nuist_aio/src/auth/session_store.dart';
import 'package:nuist_aio/src/schedule/schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AppState> mount(
    WidgetTester tester, {
    bool onboarded = true,
    Size size = const Size(412, 915),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
    await state.load();
    state.onboarded = onboarded;
    await tester.pumpWidget(CampusApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  test('invite codes validate case- and separator-insensitively', () {
    expect(isValidInviteCode('DT9Q-59W8-TSPH-8TQZ'), isTrue);
    expect(isValidInviteCode('dt9q59w8tsph8tqz'), isTrue);
    expect(isValidInviteCode('dt9q 59w8 tsph 8tqz'), isTrue);
    expect(isValidInviteCode('DT9Q-59W8-TSPH-8TQ1'), isFalse);
    expect(isValidInviteCode('DT9Q-59W8-TSPH-8TQ'), isFalse);
    expect(isValidInviteCode(''), isFalse);
  });

  testWidgets('invite code gate blocks first run then wizard follows', (
    tester,
  ) async {
    await mount(tester, onboarded: false);
    expect(find.text('信大AIO 内部测试'), findsOneWidget);
    expect(find.text('校园日常，一站就好。'), findsNothing);
    await tester.tap(find.text('完成注册'));
    await tester.pumpAndSettle();
    expect(
      find.text('邀请码不正确。请核对后重试，或向开发者索取新的邀请码。'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'dt9q59w8tsph8tqz');
    await tester.tap(find.text('完成注册'));
    await tester.pumpAndSettle();
    expect(find.text('校园日常，一站就好。'), findsOneWidget);
    final restored = AppState();
    await restored.load();
    expect(restored.registered, isTrue);
    expect(restored.onboarded, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'first-run wizard can be completed without login and stays completed',
    (tester) async {
      await mount(tester, onboarded: false);
      // 先通过内测邀请码注册，再进入正常的设置向导。
      expect(find.text('信大AIO 内部测试'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'DT9Q-59W8-TSPH-8TQZ');
      await tester.tap(find.text('完成注册'));
      await tester.pumpAndSettle();
      expect(find.text('校园日常，一站就好。'), findsOneWidget);
      await tester.tap(find.text('开始设置'));
      await tester.pumpAndSettle();
      expect(find.text('选一个喜欢的模样。'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('前往统一认证'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('初始化校园服务。'), findsOneWidget);
      expect(find.text('等待主账号登录'), findsWidgets);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('选择实际宿舍'), findsOneWidget);
      await tester.tap(find.text('稍后选择，先逛逛'));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassNavBar), findsOneWidget);
      final restored = AppState();
      await restored.load();
      expect(restored.onboarded, isTrue);
      expect(restored.connectedAt, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home uses the authenticated display name and restores it securely',
    (tester) async {
      final state = await mount(tester);
      const secure = FlutterSecureStorage();
      await secure.write(
        key: 'nuist.portal.session.v1',
        value: jsonEncode({
          'version': 2,
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
          'displayName': ' 测试姓名 ',
        }),
      );
      await state.sessionChanged();
      await tester.pumpAndSettle();
      expect(find.textContaining('测试姓名 同学'), findsOneWidget);
      final restored = AppState();
      await restored.load();
      expect(restored.displayName, '测试姓名');
      await secure.delete(key: 'nuist.portal.session.v1');
      await state.sessionChanged();
      await tester.pumpAndSettle();
      expect(find.textContaining('测试姓名'), findsNothing);
      expect(state.displayName, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('four tabs, service filtering, and theme persistence work', (
    tester,
  ) async {
    final state = await mount(tester);
    await tester.tap(find.text('学习').last);
    await tester.pumpAndSettle();
    expect(find.text('获取我的课表').hitTestable(), findsOneWidget);
    await tester.tap(find.text('功能').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '图书');
    await tester.pumpAndSettle();
    expect(find.text('图书馆').hitTestable(), findsOneWidget);
    expect(find.text('校园卡').hitTestable(), findsNothing);
    await tester.tap(find.text('图书馆').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('入口已预留，具体功能将在后续版本接入。'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观与主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('鸢尾'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '深色'));
    await tester.pumpAndSettle();
    expect(state.dynamicColor, isFalse);
    final restored = AppState();
    await restored.load();
    expect(restored.palette, CampusPalette.violet);
    expect(restored.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  Schedule exampleSchedule() {
    final today = DateTime.now();
    return Schedule(
      term: '2026-2027-1',
      termName: '示例课表（非账号数据）',
      startDate: mondayOf(today),
      totalWeeks: 20,
      updatedAt: today,
      slots: ScheduleParser.defaultSlots,
      unscheduled: const [UnscheduledCourse('示例实验课', '教师乙')],
      courses: [
        Course(
          name: '示例课程 · 高等数学',
          teacher: '教师甲、教师乙',
          location: '示例教室 A101',
          day: today.weekday,
          start: 1,
          end: 2,
          weeks: const [1],
        ),
        Course(
          name: '示例课程 · 大学英语',
          teacher: '教师丙',
          location: '示例教室 B203',
          day: today.weekday,
          start: 5,
          end: 6,
          weeks: const [1],
        ),
      ],
    );
  }

  testWidgets(
    'imported data is shared across home and learning and dates filter exact weeks',
    (tester) async {
      final state = await mount(tester);
      await state.saveSchedule(
        exampleSchedule(),
        generation: state.sessionGeneration,
      );
      await tester.pumpAndSettle();
      expect(find.text('示例课程 · 高等数学').hitTestable(), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('home-course-示例课程 · 高等数学-1')))
            .height,
        lessThanOrEqualTo(68),
      );
      await tester.tap(find.byTooltip('下一周').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('这一天没有已安排的课程。').hitTestable(), findsOneWidget);
      expect(find.text('示例课程 · 高等数学').hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('上一周').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('示例课程 · 高等数学').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('教师：教师甲、教师乙'), findsOneWidget);
      Navigator.of(tester.element(find.text('教师：教师甲、教师乙'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('学习').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('示例课程 · 高等数学').last);
      await tester.pumpAndSettle();
      expect(find.text('示例课程 · 高等数学').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small screens and enlarged text do not overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = await mount(tester, size: const Size(320, 640));
    await state.saveSchedule(
      exampleSchedule(),
      generation: state.sessionGeneration,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final tab in ['学习', '功能', '我的', '首页']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.tap(find.byTooltip('外观与主题'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('authentication only probes the official portal origin after its login callback', () {
    expect(SessionStore.isAllowedNavigation(SessionStore.loginUri), isTrue);
    for (final url in [
      'http://i.nuist.edu.cn/',
      'https://i.nuist.edu.cn.evil.test/',
      'https://i.nuist.edu.cn:8443/',
      'https://user:pass@i.nuist.edu.cn/',
      'javascript:alert(1)',
    ]) {
      expect(
        SessionStore.isAllowedNavigation(Uri.parse(url)),
        isFalse,
        reason: url,
      );
    }
    expect(
      SessionStore.isPortalLanding(
        Uri.parse('https://i.nuist.edu.cn/index.html#/'),
      ),
      isTrue,
    );
    expect(
      SessionStore.isPortalLanding(
        Uri.parse('https://i.nuist.edu.cn/default/index.html#/'),
      ),
      isTrue,
    );
    expect(
      SessionStore.isPortalLanding(
        Uri.parse('https://i.nuist.edu.cn/mobile/index.html#/'),
      ),
      isTrue,
    );
    expect(
      SessionStore.isPortalLanding(
        Uri.parse('https://i.nuist.edu.cn/login?ticket=secret'),
      ),
      isFalse,
    );
  });

  if (Platform.environment['CAPTURE_UI'] == '1') {
    testWidgets('capture UI review images', (tester) async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final fontPath = Platform.environment['UI_FONT'];
      if (fontPath != null) {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(
              ByteData.sublistView(File(fontPath).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState();
      await state.load();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: CampusApp(state: state),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('build/ui-preview/$name.png');
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('onboarding');
      await state.finishOnboarding();
      await capture('home');
      await state.saveSchedule(
        exampleSchedule(),
        generation: state.sessionGeneration,
      );
      await capture('home-schedule-example');
      final catalog = await tester.runAsync(DormCatalog.load);
      final service = catalog!.services.first;
      var nodes = service.nodes;
      final path = <DormNode>[];
      for (int i = 0; i < service.codes.length; i++) {
        path.add(nodes.first);
        nodes = nodes.first.children;
      }
      final dorm = DormSelection(service.id, service.label, {
        for (int i = 0; i < path.length; i++) service.codes[i]: path[i].value,
      }, path.map((n) => n.name).toList());
      await state.setDorm(dorm);
      final stamp = DateTime.now();
      await state.saveAccounts({
        'wallet': Wallet(const [
          CampusCard('示例校园卡', 1234, 251, false, false),
        ], stamp).toJson(),
        'bills': BillPage(currentMonth(), 1, 1, 20, 0, 2468, const [
          BillRecord('示例消费', 2468, false, true, '示例时间', '示例支付'),
        ], stamp).toJson(),
        'electricity': Electricity(dorm.key, {
          '剩余电量': '123.456789',
        }, stamp).toJson(),
      }, generation: state.sessionGeneration);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('¥ 12.34'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('home-accounts-example');
      Navigator.of(tester.element(find.byType(NavigationBar))).push(
        MaterialPageRoute<void>(
          builder: (_) => CampusAccountsPage(state: state),
        ),
      );
      await capture('card-example');
      await tester.tap(find.text('账单'));
      await capture('bills-example');
      await tester.tap(find.text('电费'));
      await capture('electricity-example');
      Navigator.of(tester.element(find.byType(CampusAccountsPage))).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(NavigationBar))).push(
        MaterialPageRoute<void>(builder: (_) => DormPickerPage(state: state)),
      );
      await capture('dorm-selection');
      Navigator.of(tester.element(find.byType(DormPickerPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('学习').last);
      await capture('learning');
      await tester.tap(find.text('功能').last);
      await capture('features');
      await tester.tap(find.text('我的').last);
      await capture('profile');
      await tester.tap(find.text('外观与主题'));
      await capture('themes');
      await state.setMode(ThemeMode.dark);
      await capture('themes-dark');
      expect(tester.takeException(), isNull);
    });
  }
}
