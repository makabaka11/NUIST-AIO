import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/dashboard/dashboard_config.dart';
import 'package:nuist_aio/src/dashboard/dashboard_widgets.dart';
import 'package:nuist_aio/src/dashboard/holiday.dart';
import 'package:nuist_aio/src/profile/avatar_store.dart';
import 'package:nuist_aio/src/services/site_registry.dart';
import 'package:nuist_aio/src/services/navigation.dart';

import 'service_sessions_test.dart' show FakeSession;

class NoAvatarFiles extends AvatarStore {
  @override
  Future<void> clear() async {}
}

Map<String, dynamic> book() => {
  'title': '测试图书',
  'author': '作者',
  'dueDate': '2026-12-01',
  'loanDate': '2026-10-01',
  'status': 'normal',
};
Map<String, dynamic> calendar(List<Map<String, dynamic>> days) => {
  'ok': true,
  'year': 2026,
  'terms': [
    {
      'weeks': [
        {'days': days},
      ],
    },
    {'weeks': []},
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({
      'nuist.portal.session.v1': jsonEncode({'accountKey': 'a' * 64}),
    });
  });
  test(
    'layout normalizes IDs, persists toggles/order and survives process reload',
    () async {
      final state = AppState();
      await state.updateDashboard(
        state.dashboardLayout
            .toggle(DashboardWidgetId.wallet, false)
            .reorder(0, 3),
      );
      final restored = AppState();
      await restored.load();
      expect(restored.dashboardLayout.order[3], DashboardWidgetId.library);
      expect(
        restored.dashboardLayout.enabled,
        isNot(contains(DashboardWidgetId.wallet)),
      );
      expect(
        DashboardLayout.decode(
          '{"order":["wallet","wallet","unknown"],"disabled":["unknown"]}',
        ).order.length,
        DashboardWidgetId.values.length,
      );
      state.dispose();
      restored.dispose();
    },
  );
  test('library validates readiness separately, stores display-only data and keeps cache on failure', () async {
    final calls = <String>[];
    var fail = false;
    final state = AppState(
      librarySession: FakeSession((task, args) async {
        calls.add(task);
        if (task == 'probe') return {'ok': true, 'ready': true};
        if (fail) throw const FormatException('network');
        return {
          'ok': true,
          'total': 1,
          'books': [book()],
        };
      }),
    );
    state.connectedAt = DateTime.now();
    await state.connectLibrary();
    expect(calls, ['probe', 'loans']);
    expect(state.libraryVerified, true);
    expect(state.libraryLoans!.books.single.title, '测试图书');
    expect((await state.sessions.readLibrary())!.books.length, 1);
    fail = true;
    await state.syncLibrary();
    expect(state.libraryLoans!.books.length, 1);
    expect(state.libraryNotice, isNotNull);
    state.dispose();
  });
  test(
    'account removal rejects late library responses and clears encrypted cache',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final state = AppState(
        avatarStore: NoAvatarFiles(),
        librarySession: FakeSession((task, args) => pending.future),
      );
      state.connectedAt = DateTime.now();
      state.libraryVerified = true;
      final request = state.syncLibrary();
      await state.clearPrivateData();
      pending.complete({
        'ok': true,
        'total': 1,
        'books': [book()],
      });
      await request;
      expect(state.libraryLoans, isNull);
      expect(await state.sessions.readLibrary(), isNull);
      expect(state.libraryVerified, false);
      state.dispose();
    },
  );
  test(
    'unknown or failed library probe cannot become ready or sync personal data',
    () async {
      final calls = <String>[];
      final state = AppState(
        librarySession: FakeSession((task, args) async {
          calls.add(task);
          return {'ok': true, 'token': 'not-proof'};
        }),
      );
      state.connectedAt = DateTime.now();
      await state.connectLibrary();
      expect(state.libraryVerified, false);
      expect(calls, ['probe']);
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.library)),
        SitePhase.failed,
      );
      state.dispose();
    },
  );
  test('holiday countdown uses explicit calendar events, merges dates and excludes make-up classes', () {
    final data = calendar([
      {'date': '2027-01-01', 'event': '元旦放假'},
      {'date': '2027-01-02', 'event': '元旦放假'},
      {'date': '2026-11-11', 'event': '国庆节补课'},
      {'date': '2026-11-12', 'event': '', 'lunar': '中秋节'},
      {'date': '2027-05-01', 'event': '劳动节放假'},
    ]);
    final next = SchoolHoliday.next(data, DateTime(2026, 12, 30))!;
    expect(next.name, '元旦');
    expect(next.daysFrom(DateTime(2026, 12, 30)), 2);
    expect(next.active(DateTime(2027, 1, 2)), true);
    expect(SchoolHoliday.next(data, DateTime(2027, 1, 3))!.name, '劳动节');
    expect(
      SchoolHoliday.next(
        calendar([
          {'date': '2026-11-11', 'event': '普通周末'},
        ]),
        DateTime(2026, 11, 10),
      ),
      isNull,
    );
  });
  test('school festival labels and explicit rest markers define countdown without guessed weekends', () {
    final data = calendar([
      {'date': '2026-09-25', 'event': '', 'lunar': '中秋节'},
      {'date': '2026-09-26', 'event': '休', 'lunar': '十六'},
      {'date': '2026-09-27', 'event': '休', 'lunar': '十七'},
      {'date': '2027-01-01', 'event': '', 'lunar': '元旦节'},
    ]);
    final autumn = SchoolHoliday.next(data, DateTime(2026, 9, 24))!;
    expect(autumn.end, DateTime.utc(2026, 9, 27));
    expect(autumn.declaredBreak, true);
    final newYear = SchoolHoliday.next(data, DateTime(2026, 11, 10))!;
    expect(newYear.name, '元旦');
    expect(newYear.daysFrom(DateTime(2026, 11, 10)), 52);
    expect(newYear.end, DateTime.utc(2027, 1, 1));
    expect(newYear.declaredBreak, false);
  });
  test('wizard initializes library credentials without synchronizing borrowing records', () async {
    final calls = <String>[];
    final state = AppState(
      librarySession: FakeSession((task, args) async {
        calls.add(task);
        return {'ok': true, 'ready': true};
      }),
    );
    state.connectedAt = DateTime.now();
    await state.connectCampusServices(synchronizeData: false);
    expect(calls, ['probe']);
    expect(state.libraryVerified, true);
    expect(state.libraryLoans, isNull);
    state.dispose();
  });
  test('library failure remains isolated from other ready services', () async {
    final state = AppState(
      librarySession: FakeSession(
        (task, args) async => throw const FormatException('offline'),
      ),
      teachingSession: FakeSession(
        (task, args) async => task == 'studentProfile'
            ? {'ok': false}
            : {'ok': true, 'terms': []},
      ),
      cardSession: FakeSession(
        (task, args) async => {'ok': true, 'ready': true},
      ),
    );
    state.connectedAt = DateTime.now();
    await state.connectCampusServices(synchronizeData: false);
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.campusCard)),
      SitePhase.ready,
    );
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.library)),
      SitePhase.failed,
    );
    state.dispose();
  });
  test('verified library registry declares both observed landing paths and exact HTTPS hosts', () {
    final site = SchoolSites.get(SchoolSiteId.library);
    expect(site.automatic, true);
    // Authentication must originate at the library, not a constructed CAS URL.
    expect(
      site.authEntry,
      Uri.https('elib.nuist.edu.cn', '/meta-local/opac/cas/rosetta'),
    );
    expect(site.authEntry!.hasQuery, false);
    expect(
      site.sessionEntry,
      Uri.https('elib.nuist.edu.cn', '/space/casBoard'),
    );
    expect(site.acceptsProbeLocation(site.sessionEntry), true);
    expect(SchoolNavigation.library(site.sessionEntry), true);
    for (final path in ['/space/reader/lendList', '/mspace/casBoard']) {
      expect(
        site.acceptsProbeLocation(Uri.https('elib.nuist.edu.cn', path)),
        true,
      );
    }
    for (final url in [
      'http://elib.nuist.edu.cn/space/',
      'https://elib.nuist.edu.cn.evil.org/',
      'https://user@elib.nuist.edu.cn/',
      'https://elib.nuist.edu.cn:8443/',
    ]) {
      expect(SchoolNavigation.library(Uri.parse(url)), false);
    }
  });
  testWidgets('dashboard settings toggle cards and drag their order', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => DashboardWidgets(state: state),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('自定义首页小组件'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('dashboard-option-library')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.dashboardLayout.disabled, contains(DashboardWidgetId.library));
    final handle = find.descendant(
      of: find.byKey(const ValueKey('dashboard-option-library')),
      matching: find.byType(ReorderableDragStartListener),
    );
    await tester.dragFrom(tester.getCenter(handle), const Offset(0, 130));
    await tester.pumpAndSettle();
    expect(
      state.dashboardLayout.order.indexOf(DashboardWidgetId.library),
      greaterThan(0),
    );
    Navigator.of(tester.element(find.byType(ReorderableListView))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard-library')), findsNothing);
    expect(find.byKey(const ValueKey('dashboard-holiday')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
