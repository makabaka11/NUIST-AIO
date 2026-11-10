import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/accounts/accounts_page.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/shell.dart';
import 'package:nuist_aio/src/onboarding.dart';
import 'package:nuist_aio/src/services/site_registry.dart';
import 'package:nuist_aio/src/services/navigation.dart';
import 'package:nuist_aio/src/services/service_sessions.dart';

import 'schedule_test.dart' show fixture, row;
import 'accounts_test.dart' show sampleWallet, sampleBill;

class FakeSession implements ServiceSession {
  FakeSession(this.handler);
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  handler;
  final calls = <String>[];
  int closes = 0;
  @override
  bool get available => true;
  @override
  Future<Map<String, dynamic>> query(String task, Map<String, dynamic> args) {
    calls.add(task);
    return handler(task, args);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

FakeSession fakeCalendar() => FakeSession(
  (task, args) async => {
    'ok': true,
    'year': 2026,
    'terms': [
      {'weeks': []},
      {'weeks': []},
    ],
  },
);

FakeSession fakeLibrary() => FakeSession(
  (task, args) async => task == 'probe'
      ? {'ok': true, 'ready': true}
      : {'ok': true, 'total': 0, 'books': []},
);

FakeSession teaching({bool fail = false}) => FakeSession((task, args) async {
  if (fail) throw const FormatException('example failure');
  if (task == 'semesters') {
    return {
      'ok': true,
      'current': '2026-2027-1',
      'terms': [
        {'DM': '2026-2027-1', 'MC': '当前学期'},
      ],
    };
  }
  if (task == 'studentProfile') {
    return {
      'ok': true,
      'profile': {
        'name': '示例学生',
        'studentNumber': 'synthetic-number',
        'college': '示例学院',
        'major': '示例专业',
        'grade': '2024级',
      },
    };
  }
  expect(args['term'], '2026-2027-1');
  return {
    'ok': true,
    'data': fixture([row()]),
  };
});
FakeSession card() => FakeSession(
  (task, args) async => {
    'ok': true,
    'wallet': sampleWallet(),
    'bills': sampleBill(),
  },
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('official auth callbacks and portal roots are allowed, payments remain excluded', () {
    for (final path in [
      '/plat-pc',
      '/plat-pc/',
      '/plat-pc/businesslobby',
      '/berserker-auth/cas/login/wisedu',
      '/berserker-auth/login',
    ]) {
      expect(
        SchoolNavigation.card(Uri.https('icard.nuist.edu.cn', path)),
        isTrue,
      );
    }
    for (final url in [
      'http://icard.nuist.edu.cn/plat-pc',
      'https://icard.nuist.edu.cn:8443/plat-pc',
      'https://icard.nuist.edu.cn.evil.test/plat-pc',
      'https://user:pass@icard.nuist.edu.cn/plat-pc',
      'https://icard.nuist.edu.cn/charge/order/add',
      'https://icard.nuist.edu.cn/charge-pc/pays/448',
    ]) {
      expect(SchoolNavigation.card(Uri.parse(url)), isFalse);
    }
    expect(
      SchoolNavigation.safeLocation(
        Uri.parse(
          'https://icard.nuist.edu.cn/plat-pc?ticket=PRIVATE&synjones-auth=PRIVATE#PRIVATE',
        ),
      ),
      'https://icard.nuist.edu.cn/plat-pc',
    );
  });
  test(
    'one portal connection imports the current timetable and syncs accounts',
    () async {
      final t = teaching(), c = card();
      final state = AppState(
        portalSession: fakeCalendar(),
        librarySession: fakeLibrary(),
        cardSession: c,
        teachingSession: t,
      );
      state.connectedAt ??= DateTime.now();
      await state.connectCampusServices();
      expect(t.calls, ['semesters', 'schedule', 'studentProfile']);
      expect(c.calls, ['sync']);
      expect(state.schedule!.term, '2026-2027-1');
      expect(state.schedule!.courses, isNotEmpty);
      expect(state.accounts.wallet!.balance, 1234);
      expect(state.connectingServices, isFalse);
      expect(state.servicesNotice, contains('已自动连接'));
      state.connectedAt ??= DateTime.now();
      await state.connectCampusServices();
      expect(t.calls, [
        'semesters',
        'schedule',
        'studentProfile',
        'semesters',
        'studentProfile',
      ]); // Preserve an existing selected timetable.
    },
  );
  test('teaching failure does not prevent card synchronization', () async {
    final c = card();
    final state = AppState(
      portalSession: fakeCalendar(),
      librarySession: fakeLibrary(),
      cardSession: c,
      teachingSession: teaching(fail: true),
    );
    state.connectedAt ??= DateTime.now();
    await state.connectCampusServices();
    expect(c.calls, ['sync']);
    expect(state.accounts.wallet, isNotNull);
    expect(state.servicesNotice, contains('教务自动连接未完成'));
  });
  test(
    'empty account results do not report successful synchronization',
    () async {
      final state = AppState(
        portalSession: fakeCalendar(),
        librarySession: fakeLibrary(),
        teachingSession: teaching(),
        cardSession: FakeSession((_, _) async => {'ok': true, 'errors': []}),
      );
      state.connectedAt ??= DateTime.now();
      await state.connectCampusServices();
      expect(state.accounts.wallet, isNull);
      expect(state.servicesNotice, contains('一卡通自动连接未完成'));
    },
  );
  test('account reset closes both services and rejects late results', () async {
    final pending = Completer<Map<String, dynamic>>();
    final t = FakeSession((_, _) => pending.future), c = card();
    final state = AppState(
      portalSession: fakeCalendar(),
      librarySession: fakeLibrary(),
      cardSession: c,
      teachingSession: t,
    );
    state.connectedAt = DateTime.now();
    final operation = state.connectCampusServices();
    await state.clearPrivateData();
    await state.resetServiceSessions();
    pending.complete({'ok': true, 'terms': []});
    await operation;
    expect(c.closes, 1);
    expect(t.closes, 1);
    expect(c.calls.length, lessThanOrEqualTo(1));
    expect(state.accounts.wallet, isNull);
    expect(state.servicesNotice, isNull);
  });
  test('credential initialization is followed by separate profile sync without timetable or account reads', () async {
    final t = teaching();
    final c = FakeSession((task, args) async {
      expect(task, 'probe');
      return {'ok': true, 'ready': true};
    });
    final state = AppState(
      portalSession: fakeCalendar(),
      librarySession: fakeLibrary(),
      cardSession: c,
      teachingSession: t,
    );
    state.connectedAt = DateTime.now();
    state.connectedAt ??= DateTime.now();
    await state.connectCampusServices(synchronizeData: false);
    expect(t.calls, ['semesters', 'studentProfile']);
    expect(c.calls, ['probe']);
    expect(state.schedule, isNull);
    expect(state.accounts.wallet, isNull);
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.teaching)),
      SitePhase.ready,
    );
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.campusCard)),
      SitePhase.ready,
    );
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.library)),
      SitePhase.ready,
    );
  });

  test(
    'initialization waits for the main account before accessing child sites',
    () async {
      final c = card(), t = teaching();
      final state = AppState(
        portalSession: fakeCalendar(),
        librarySession: fakeLibrary(),
        cardSession: c,
        teachingSession: t,
      );
      await state.connectCampusServices(synchronizeData: false);
      expect(c.calls, isEmpty);
      expect(t.calls, isEmpty);
      expect(state.servicesNotice, contains('请先连接校园账号'));
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.teaching)),
        SitePhase.waiting,
      );
    },
  );

  testWidgets(
    'wizard shows an independent live initialization step before dorm selection',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final state = AppState(
        portalSession: fakeCalendar(),
        librarySession: fakeLibrary(),
        cardSession: FakeSession((task, args) => pending.future),
        teachingSession: teaching(),
      );
      state.connectedAt = DateTime.now();
      await tester.pumpWidget(MaterialApp(home: OnboardingPage(state: state)));
      await tester.tap(find.text('开始设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pump();
      expect(find.text('4 / 5'), findsOneWidget);
      expect(find.text('初始化校园服务。'), findsOneWidget);
      expect(state.connectingServices, isTrue);
      pending.complete({'ok': true, 'ready': true});
      await tester.pumpAndSettle();
      expect(find.text('已检查 3 / 3 个已接入子站点'), findsOneWidget);
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.library)),
        SitePhase.ready,
      );
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('选择实际宿舍'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an existing portal login reconnects school services on startup',
    (tester) async {
      final c = card(), t = teaching();
      final state = AppState(
        portalSession: fakeCalendar(),
        librarySession: fakeLibrary(),
        cardSession: c,
        teachingSession: t,
      );
      state.connectedAt = DateTime.now();
      await tester.pumpWidget(MaterialApp(home: CampusShell(state: state)));
      await tester.pumpAndSettle();
      expect(c.calls, ['sync']);
      expect(t.calls, ['semesters', 'schedule', 'studentProfile']);
      expect(state.accounts.wallet, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account page queries a shared session automatically without displaying a WebView',
    (tester) async {
      final c = card(),
          state = AppState(
            portalSession: fakeCalendar(),
            librarySession: fakeLibrary(),
            cardSession: c,
            teachingSession: teaching(),
          );
      await tester.pumpWidget(
        MaterialApp(home: CampusAccountsPage(state: state)),
      );
      await tester.pumpAndSettle();
      expect(c.calls, ['wallet']);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('wallet-current-balance')))
            .data,
        '¥ 12.34',
      );
      expect(find.text('连接学校一卡通'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '账单'));
      await tester.pumpAndSettle();
      expect(c.calls, ['wallet', 'bills']);
      expect(find.text('连接学校一卡通'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
