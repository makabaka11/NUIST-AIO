import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/network/campus_network.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/bulletin/bulletin_page.dart';
import 'package:nuist_aio/src/services/site_registry.dart';

import 'service_sessions_test.dart' show FakeSession;

const origin = 'https://bulletin.nuist.edu.cn';
final proxy = 'https://client.vpn.nuist.edu.cn/https/webvpn${'a' * 64}';
Map<String, dynamic> directory() => {
  'ok': true,
  'ready': true,
  'routes': {origin: proxy},
};
Map<String, dynamic> list() => {
  'ok': true,
  'rows': [
    {
      'title': '测试公告',
      'url': '$origin/info/1001/1.htm',
      'date': '2020-01-01',
      'department': '测试部门',
      'category': '教学考试',
      'pinned': true,
    },
  ],
  'categories': [],
  'next': null,
};
void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'only registered HTTPS resources and exact gateway prefixes are accepted',
    () {
      final route = CampusRoute.fromDirectory(origin, proxy);
      final article = Uri.parse(
        '$origin/content.jsp?urltype=news.NewsContentUrl&wbnewsid=1',
      );
      expect(route.resolve(article).query, article.query);
      expect(route.accepts(route.resolve(article)), true);
      for (final invalid in [
        '$proxy-fake/page',
        'https://client.vpn.nuist.edu.cn.evil/https/webvpn${'a' * 64}/',
        '$proxy/../other',
      ]) {
        expect(route.accepts(Uri.parse(invalid)), false);
      }
      for (final target in [
        '$proxy/extra',
        '$proxy?token=secret',
        proxy.replaceFirst('https:', 'http:'),
        proxy.replaceFirst('client.vpn.nuist.edu.cn', 'evil.example'),
      ]) {
        expect(
          () => CampusRoute.fromDirectory(origin, target),
          throwsFormatException,
        );
      }
      expect(
        () => CampusRoute.fromDirectory('https://jwxt.nuist.edu.cn', proxy),
        throwsFormatException,
      );
      expect(
        () => route.resolve(Uri.parse('https://evil.example/')),
        throwsFormatException,
      );
    },
  );
  test('automatic falls back after content failure and fixed direct never queries VPN', () async {
    final direct = FakeSession((_, _) async => {'ok': false});
    final vpn = FakeSession((_, _) async => directory());
    final proxied = FakeSession((_, _) async => list());
    final repo = BulletinRepository(
      direct: direct,
      vpn: vpn,
      proxyFactory: (site) {
        expect(site.acceptsProbeLocation(Uri.parse('$proxy/index.htm')), true);
        final relay = Uri.parse(
          'https://client.vpn.nuist.edu.cn/enlink/sso/login',
        );
        expect(site.navigation!(relay), true);
        expect(site.acceptsProbeLocation(relay), false);
        expect(
          site.navigation!(Uri.parse('https://evil.example/enlink/sso/login')),
          false,
        );
        return proxied;
      },
    );
    expect(
      (await repo.query(CampusNetworkMode.automatic, 'list')).path,
      CampusPath.vpn,
    );
    expect(vpn.calls.length, 1);
    await expectLater(
      repo.query(CampusNetworkMode.direct, 'list'),
      throwsFormatException,
    );
    expect(vpn.calls.length, 1);
    await repo.close();
    expect(proxied.closes, 1);
  });
  test('direct success skips VPN and VPN-only skips direct', () async {
    final direct = FakeSession((_, _) async => list()),
        vpn = FakeSession((_, _) async => directory());
    final repo = BulletinRepository(
      direct: direct,
      vpn: vpn,
      proxyFactory: (_) => FakeSession((_, _) async => list()),
    );
    expect(
      (await repo.query(CampusNetworkMode.automatic, 'list')).path,
      CampusPath.direct,
    );
    expect(vpn.calls, isEmpty);
    await repo.query(CampusNetworkMode.vpn, 'list');
    expect(direct.calls.length, 1);
    await repo.close();
  });
  test(
    'expired VPN probe cannot create proxy or leak a late old-account response',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var factories = 0;
      final repo = BulletinRepository(
        direct: FakeSession((_, _) => pending.future),
        vpn: FakeSession((_, _) async => {'ok': false}),
        proxyFactory: (_) {
          factories++;
          throw StateError('must not create');
        },
      );
      await expectLater(
        repo.query(CampusNetworkMode.vpn, 'list'),
        throwsFormatException,
      );
      expect(factories, 0);
      final late = repo.query(CampusNetworkMode.automatic, 'list');
      final assertion = expectLater(late, throwsFormatException);
      await repo.close();
      pending.complete(list());
      await assertion;
      expect(factories, 0);
    },
  );
  test('network choice persists and closes prior sessions', () async {
    final direct = FakeSession((_, _) async => list()),
        vpn = FakeSession((_, _) async => directory());
    final state = AppState(
      bulletinRepository: BulletinRepository(direct: direct, vpn: vpn),
    );
    await state.load();
    await state.setNetworkMode(CampusNetworkMode.vpn);
    expect(direct.closes, 1);
    final restored = AppState();
    await restored.load();
    expect(restored.networkMode, CampusNetworkMode.vpn);
    state.dispose();
    restored.dispose();
  });
  test(
    'on demand sites remain outside default personal-service initialization',
    () {
      expect(SchoolSites.get(SchoolSiteId.vpn).automatic, false);
      expect(SchoolSites.get(SchoolSiteId.bulletin).automatic, false);
      expect(SchoolSites.all.where((s) => s.networkRouting).map((s) => s.id), [
        SchoolSiteId.bulletin,
      ]);
    },
  );
  testWidgets('bulletin detail drops account content after account changes', (
    tester,
  ) async {
    final state = AppState(
      bulletinRepository: BulletinRepository(
        direct: FakeSession(
          (_, _) async => {'ok': true, 'body': '账号正文', 'links': []},
        ),
      ),
    );
    await state.load();
    await tester.pumpWidget(
      MaterialApp(
        home: BulletinDetailPage(state: state, row: list()['rows'][0]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('账号正文'), findsOneWidget);
    await state.clearSchedule();
    await tester.pumpAndSettle();
    expect(find.text('账号正文'), findsNothing);
    expect(find.text('测试公告'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
