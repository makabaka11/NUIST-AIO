import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/calendar/calendar_page.dart';
import 'package:nuist_aio/src/services/site_registry.dart';
import 'package:nuist_aio/src/services/browser_links.dart';
import 'package:nuist_aio/src/network/campus_network.dart';
import 'package:nuist_aio/src/profile/student_profile.dart';
import 'package:nuist_aio/src/profile/avatar_store.dart';

import 'service_sessions_test.dart' show FakeSession;

class NoFileAvatarStore extends AvatarStore {
  @override
  Future<void> clear() async {}
}

Map<String, dynamic> calendar(int year) => {
  'ok': true,
  'year': year,
  'terms': [
    for (final index in [0, 1])
      {
        'weeks': [
          {
            'month': '8月',
            'week': index == 0 ? '1' : '暑假',
            'days': [
              for (var d = 0; d < 7; d++)
                {
                  'date': '2026-09-${(7 + d).toString().padLeft(2, '0')}',
                  'lunar': '农历',
                  'event': d == 0 ? '学校事件' : '',
                },
            ],
          },
        ],
        'remarks': '学期备注',
      },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final launches = <Map<String, dynamic>>[];
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    launches.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launches.add(Map<String, dynamic>.from(call.arguments));
              return true;
            }
            return false;
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
  );
  SchoolBrowserLink link(String id) =>
      SchoolBrowserLinks.all.singleWhere((l) => l.id == id);
  test(
    'repair fragment uses current student number and never the example account',
    () {
      final uri = link('repair').resolve(number: '0000123456');
      expect(uri.origin, 'http://xdex.nuist.edu.cn:18080');
      expect(uri.query, isEmpty);
      expect(Uri.parse(uri.fragment).queryParameters['WxId'], '0000123456');
      expect(Uri.parse(uri.fragment).path, '/index');
      expect(() => link('repair').resolve(), throwsFormatException);
      expect(
        () => link('repair').resolve(number: '1&other=2'),
        throwsFormatException,
      );
    },
  );
  test('external VPN mapping preserves target path, port scope, query and fragment', () {
    final uri = link('repair').resolve(number: '0000123456');
    final prefix = 'https://client.vpn.nuist.edu.cn/http/webvpn${'a' * 64}';
    final routed = externalVpnUri(uri, {uri.origin: prefix});
    expect(routed.fragment, uri.fragment);
    expect(routed.path, '${Uri.parse(prefix).path}/NUIST-WEB/');
    for (final bad in [
      prefix.replaceFirst('/http/', '/https/'),
      prefix.replaceFirst('client.vpn.nuist.edu.cn', 'evil.example'),
      '$prefix?token=secret',
      '$prefix/fake',
    ]) {
      expect(
        () => externalVpnUri(uri, {uri.origin: bad}),
        throwsFormatException,
      );
    }
    expect(
      () => externalVpnUri(uri, {'http://xdex.nuist.edu.cn': prefix}),
      throwsFormatException,
    );
  });
  test(
    'browser-only sites are registered without credential initialization',
    () {
      for (final l in SchoolBrowserLinks.all.where((l) => l.standalone)) {
        final site = SchoolSites.get(l.site);
        expect(site.browserOnly, true);
        expect(site.automatic, false);
        expect(site.entry, l.entry);
      }
      expect(SchoolSites.automatic.map((s) => s.id), [
        SchoolSiteId.chaoxing,
        SchoolSiteId.teaching,
        SchoolSiteId.campusCard,
        SchoolSiteId.library,
      ]);
      expect(
        SchoolSites.get(SchoolSiteId.portal).features
            .singleWhere((f) => f.id == 'calendar')
            .implemented,
        true,
      );
    },
  );
  testWidgets(
    'school calendar shows official weeks, switches terms and requests previous year',
    (tester) async {
      final requests = <int?>[];
      final session = FakeSession((task, args) async {
        expect(task, 'calendar');
        final year = (args['params'] as Map)['year'] as int?;
        requests.add(year);
        return calendar(year ?? 2026);
      });
      final state = AppState(
        portalSession: session,
        avatarStore: NoFileAvatarStore(),
      );
      await state.load();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: SchoolCalendarPage(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2026–2027 学年'), findsOneWidget);
      expect(find.text('学校事件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('第二学期'));
      await tester.pumpAndSettle();
      expect(find.text('暑假'), findsOneWidget);
      await tester.tap(find.byTooltip('上一学年'));
      await tester.pumpAndSettle();
      expect(requests, [null, 2025]);
      expect(find.text('2025–2026 学年'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'account reset refuses a late calendar response and session is closed',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>(),
          session = FakeSession((_, _) => pending.future);
      final state = AppState(
        portalSession: session,
        avatarStore: NoFileAvatarStore(),
      );
      await state.load();
      await tester.pumpWidget(
        MaterialApp(home: SchoolCalendarPage(state: state)),
      );
      await tester.pump();
      await state.clearPrivateData();
      await state.resetServiceSessions();
      pending.complete(calendar(2026));
      await tester.pumpAndSettle();
      expect(find.text('2026–2027 学年'), findsNothing);
      expect(session.closes, 1);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'browser entry launches external browser and repair has no hardcoded fallback',
    (tester) async {
      final state = AppState();
      await state.load();
      state.networkMode = CampusNetworkMode.direct;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolBrowserEntryTile(
              link: link('enrollment'),
              state: state,
            ),
          ),
        ),
      );
      await tester.tap(find.text('选课系统'));
      await tester.pumpAndSettle();
      expect(launches.single['url'], link('enrollment').entry.toString());
      expect(launches.single['useWebView'], false);
      expect(launches.single['useSafariVC'], false);
      launches.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolBrowserEntryTile(
              key: const ValueKey('repair'),
              link: link('repair'),
              state: state,
            ),
          ),
        ),
      );
      await tester.tap(find.text('信大 E 修'));
      await tester.pumpAndSettle();
      expect(launches, isEmpty);
      expect(find.textContaining('请先在“我的”'), findsOneWidget);
      state.studentProfile = StudentProfile.fromJson({
        'name': '测试',
        'studentNumber': '0000123456',
      });
      await tester.tap(find.text('信大 E 修'));
      await tester.pumpAndSettle();
      expect(
        Uri.parse(Uri.parse(launches.single['url']).fragment)
            .queryParameters['WxId'],
        '0000123456',
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'public campus bus opens directly in system browser even in VPN mode',
    (tester) async {
      final state = AppState();
      state.networkMode = CampusNetworkMode.vpn;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolBrowserEntryTile(link: link('campusBus'), state: state),
          ),
        ),
      );
      await tester.tap(find.text('信大 E 行'));
      await tester.pumpAndSettle();
      expect(
        launches.single['url'],
        'http://www.ns-res.cn/hydxflat/indexelct.html',
      );
      expect(launches.single['useWebView'], false);
      expect(link('campusBus').vpn, false);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('WeCom guide opens instructions without launching a URL', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchoolBrowserEntryTile(link: link('eHomeGuide'), state: state),
        ),
      ),
    );
    await tester.tap(find.text('信大 E 家'));
    await tester.pumpAndSettle();
    expect(find.textContaining('企业微信 → 工作台'), findsOneWidget);
    expect(launches, isEmpty);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
