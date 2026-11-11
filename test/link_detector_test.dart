import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/network/campus_network.dart';
import 'package:nuist_aio/src/network/link_detector.dart';
import 'package:nuist_aio/src/network/network_lifecycle.dart';
import 'package:nuist_aio/src/services/browser_links.dart';
import 'package:nuist_aio/src/services/site_registry.dart';

SchoolBrowserLink entry(String id) =>
    SchoolBrowserLinks.all.singleWhere((l) => l.id == id);
Map<String, dynamic> directory([String letter = 'a']) => {
  'ok': true,
  'ready': true,
  'routes': {
    for (final l in SchoolBrowserLinks.all.where((l) => l.vpn))
      l.entry!.origin:
          'https://client.vpn.nuist.edu.cn/${l.entry!.scheme}/webvpn${letter * 64}',
  },
};

class RealHttpOverrides extends HttpOverrides {}

class LocalProbeClient implements HttpClient {
  LocalProbeClient(this.server);
  final Uri server;
  final inner = HttpOverrides.runWithHttpOverrides(
    HttpClient.new,
    RealHttpOverrides(),
  );
  final requests = <Uri>[];
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) {
    requests.add(uri);
    return inner.getUrl(server);
  }

  @override
  void close({bool force = false}) {
    closed = true;
    inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('ready site opens while unrelated probes are still pending', () async {
    final pending = Completer<bool>();
    final detector = CampusLinkDetector(
      directProbe: (link) =>
          link.id == 'studentAffairs' ? Future.value(true) : pending.future,
      directory: () async => directory(),
    );
    final work = detector.detect();
    await Future<void>.delayed(Duration.zero);
    final resolved = await detector
        .resolve(entry('studentAffairs'), CampusNetworkMode.automatic)
        .timeout(const Duration(milliseconds: 100));
    expect(resolved, entry('studentAffairs').entry);
    expect(detector.checking, true);
    pending.complete(true);
    await work;
    detector.dispose();
  });
  test('auto mode keeps per-site direct results and uses directory for only failed sites', () async {
    var probes = 0, dirs = 0;
    final detector = CampusLinkDetector(
      directProbe: (l) async {
        probes++;
        return l.id != 'innovation';
      },
      directory: () async {
        dirs++;
        return directory();
      },
    );
    await detector.detect();
    expect(probes, 3);
    expect(dirs, 1);
    final direct = await detector.resolve(
      entry('studentAffairs'),
      CampusNetworkMode.automatic,
    );
    final vpn = await detector.resolve(
      entry('innovation'),
      CampusNetworkMode.automatic,
    );
    expect(direct, entry('studentAffairs').entry);
    expect(vpn.host, 'client.vpn.nuist.edu.cn');
    expect(vpn.path, endsWith('/pt/System/Home/Index'));
    expect(probes, 3);
    expect(dirs, 1);
    detector.dispose();
  });
  test('concurrent opens share detection and preserve the current student ID fragment', () async {
    final pending = Completer<bool>();
    var probes = 0, dirs = 0;
    final detector = CampusLinkDetector(
      directProbe: (_) async {
        probes++;
        return pending.future;
      },
      directory: () async {
        dirs++;
        return directory();
      },
    );
    final first = detector.resolve(
      entry('repair'),
      CampusNetworkMode.automatic,
      studentNumber: '00001234',
    );
    final second = detector.resolve(
      entry('repair'),
      CampusNetworkMode.automatic,
      studentNumber: '00005678',
    );
    pending.complete(false);
    final links = await Future.wait([first, second]);
    expect(probes, 3);
    expect(dirs, 1);
    expect(Uri.parse(links[0].fragment).queryParameters['WxId'], '00001234');
    expect(Uri.parse(links[1].fragment).queryParameters['WxId'], '00005678');
    detector.dispose();
  });
  test(
    'fixed modes and public resources never perform automatic direct probing',
    () async {
      var probes = 0, dirs = 0;
      final detector = CampusLinkDetector(
        directProbe: (_) async {
          probes++;
          return false;
        },
        directory: () async {
          dirs++;
          return directory();
        },
      );
      expect(
        await detector.resolve(
          entry('repair'),
          CampusNetworkMode.direct,
          studentNumber: '00001234',
        ),
        entry('repair').resolve(number: '00001234'),
      );
      expect(
        (await detector.resolve(
          entry('repair'),
          CampusNetworkMode.vpn,
          studentNumber: '00001234',
        )).host,
        'client.vpn.nuist.edu.cn',
      );
      expect(
        await detector.resolve(entry('campusBus'), CampusNetworkMode.vpn),
        entry('campusBus').entry,
      );
      expect(probes, 0);
      expect(dirs, 1);
      detector.dispose();
    },
  );
  test('unavailable or unauthorized VPN never falls back silently to a failed direct link', () async {
    for (final data in [
      {'ok': false},
      {'ok': true, 'ready': true, 'routes': <String, dynamic>{}},
    ]) {
      final detector = CampusLinkDetector(
        directProbe: (_) async => false,
        directory: () async => data,
      );
      await expectLater(
        detector.resolve(entry('studentAffairs'), CampusNetworkMode.automatic),
        throwsFormatException,
      );
      expect(detector.results['studentAffairs']!.path, isNull);
      expect(detector.checking, false);
      detector.dispose();
    }
  });
  test(
    'reset refuses an old directory and keeps new account detection intact',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var dirs = 0;
      final detector = CampusLinkDetector(
        directProbe: (_) async => false,
        directory: () {
          dirs++;
          return dirs == 1 ? pending.future : Future.value(directory('b'));
        },
      );
      final old = detector.resolve(
        entry('innovation'),
        CampusNetworkMode.automatic,
      );
      final oldAssertion = expectLater(old, throwsFormatException);
      await Future<void>.delayed(Duration.zero);
      detector.reset();
      final current = await detector.resolve(
        entry('innovation'),
        CampusNetworkMode.automatic,
      );
      pending.complete(directory('a'));
      await oldAssertion;
      expect(current.path, contains('webvpn${'b' * 64}'));
      expect(detector.results['innovation']!.path, CampusPath.vpn);
      detector.dispose();
    },
  );
  test('cached detection expires and reopening rechecks the network', () async {
    var time = DateTime(2026, 11, 11), calls = 0, available = true;
    final detector = CampusLinkDetector(
      now: () => time,
      directProbe: (_) async {
        calls++;
        return available;
      },
      directory: () async => directory(),
    );
    await detector.detect();
    available = false;
    expect(
      (await detector.resolve(
        entry('studentAffairs'),
        CampusNetworkMode.automatic,
      )).host,
      'stu.nuist.edu.cn',
    );
    expect(calls, 3);
    time = time.add(const Duration(minutes: 6));
    expect(
      (await detector.resolve(
        entry('studentAffairs'),
        CampusNetworkMode.automatic,
      )).host,
      'client.vpn.nuist.edu.cn',
    );
    expect(calls, 6);
    detector.dispose();
  });
  test('anonymous direct probe validates HTML and rejects captive portal and foreign redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var kind = 'valid';
    final cookies = <String?>[];
    final subscription = server.listen((request) async {
      cookies.add(request.headers.value(HttpHeaders.cookieHeader));
      if (kind == 'redirect') {
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'https://example.invalid/login',
        );
      } else {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          kind == 'valid'
              ? '<html><title>奥蓝学生管理信息系统(学生版)</title></html>'
              : '<html><title>WiFi login</title></html>',
        );
      }
      await request.response.close();
    });
    try {
      final clients = <LocalProbeClient>[];
      final probe = DirectCampusLinkProbe(
        clientFactory: () {
          final c = LocalProbeClient(
            Uri.parse('http://127.0.0.1:${server.port}'),
          );
          clients.add(c);
          return c;
        },
      );
      expect(await probe(entry('studentAffairs')), true);
      kind = 'captive';
      expect(await probe(entry('studentAffairs')), false);
      kind = 'redirect';
      expect(await probe(entry('studentAffairs')), false);
      expect(cookies, everyElement(isNull));
      expect(clients.every((c) => c.closed), true);
      expect(
        clients
            .expand((c) => c.requests)
            .every((u) => u == entry('studentAffairs').entry),
        true,
      );
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });
  testWidgets(
    'startup and foreground resume recheck in the background without blocking the page',
    (tester) async {
      var calls = 0;
      final detector = CampusLinkDetector(
        directProbe: (_) async {
          calls++;
          return true;
        },
        directory: () async => directory(),
      );
      final state = AppState(linkDetector: detector);
      await tester.pumpWidget(
        CampusNetworkLifecycle(
          state: state,
          child: const MaterialApp(home: Text('offline page')),
        ),
      );
      expect(find.text('offline page'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 6);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('row and right button both use detected VPN in automatic mode', (
    tester,
  ) async {
    final launches = <Map<String, dynamic>>[];
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
    final detector = CampusLinkDetector(
      directProbe: (_) async => false,
      directory: () async => directory(),
    );
    final state = AppState(linkDetector: detector);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchoolBrowserEntryTile(
            link: entry('studentAffairs'),
            state: state,
          ),
        ),
      ),
    );
    await tester.tap(find.text('奥兰系统'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('按当前网络配置在浏览器打开'));
    await tester.pumpAndSettle();
    expect(launches.length, 2);
    expect(launches[0]['url'], launches[1]['url']);
    expect(Uri.parse(launches[0]['url']).host, 'client.vpn.nuist.edu.cn');
    expect(launches[0]['useWebView'], false);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  });
}
