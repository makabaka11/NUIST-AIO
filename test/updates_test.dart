import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/updates/update_model.dart';
import 'package:nuist_aio/src/updates/update_download.dart';
import 'package:nuist_aio/src/updates/update_service.dart';
import 'package:nuist_aio/src/updates/update_ui.dart';

List<AppRelease> releases(
  UpdateSource source, {
  String notes = '修复课表显示',
}) => parseReleases([
  {
    'tag_name': 'v0.4.0',
    'body': notes,
    'assets': [
      {
        'name': 'nuistaio-arm64-v8a.apk',
        'browser_download_url':
            '${source.repository}/releases/download/v0.4.0/nuistaio-arm64-v8a.apk',
      },
    ],
  },
], source);
UpdateController controller({
  Future<List<AppRelease>> Function(UpdateSource)? fetch,
  UpdateDownload Function()? downloader,
  Future<String> Function(File)? installer,
}) => UpdateController(
  downloader: downloader,
  installer: installer,
  installed: () async => const InstalledBuild('0.3.5', '14'),
  fetch: fetch ?? (source) async => releases(source),
  runtime: const UpdateRuntime(TargetPlatform.android, 'arm64'),
);

class RealUpdateHttp extends HttpOverrides {}

class UpdateHttpClient implements HttpClient {
  UpdateHttpClient(this.local);
  final Uri local;
  final inner = HttpOverrides.runWithHttpOverrides(
    HttpClient.new,
    RealUpdateHttp(),
  );
  final requests = <Uri>[];
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests.add(url);
    return inner.getUrl(local);
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
  test('unavailable mirror falls back to the official package', () async {
    final root = await Directory.systemTemp.createTemp('mirror-fallback');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    var calls = 0;
    server.listen((request) async {
      if (++calls == 1) {
        request.response.statusCode = 403;
      } else {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([80, 75, 3, 4]);
      }
      await request.response.close();
    });
    final client = UpdateHttpClient(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final job = UpdateDownload(
      clientFactory: () => client,
      directory: () async => root,
    );
    final asset = releases(UpdateSource.github).single.assets.single;
    final file = await job.download(asset, onProgress: (_, _) {});
    expect(client.requests, [githubUpdateMirror(asset.url), asset.url]);
    expect(await file.readAsBytes(), [80, 75, 3, 4]);
  });

  test(
    'streamed package download reports bytes and removes partial files',
    () async {
      final root = await Directory.systemTemp.createTemp('update-test');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        await root.delete(recursive: true);
      });
      var mode = 'success';
      server.listen((request) async {
        if (mode == 'html') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html>Login</html>');
        } else if (mode == 'redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(
            'location',
            'http://unsafe.example/file.apk',
          );
        } else {
          request.response.headers.contentType = ContentType.binary;
          request.response.contentLength = 4;
          request.response.add([80, 75]);
          await request.response.flush();
          request.response.add([3, 4]);
        }
        await request.response.close();
      });
      final client = UpdateHttpClient(
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final job = UpdateDownload(
        clientFactory: () => client,
        directory: () async => root,
      );
      final counts = <int>[];
      final asset = ReleaseAsset(
        'test.apk',
        Uri.parse('https://github.com/test/test/releases/download/v1/test.apk'),
      );
      final file = await job.download(
        asset,
        onProgress: (n, total) {
          counts.add(n);
          expect(total, 4);
        },
      );
      expect(await file.readAsBytes(), [80, 75, 3, 4]);
      expect(counts.first, 0);
      expect(counts.last, 4);
      expect(client.closed, isTrue);
      for (final failure in ['html', 'redirect']) {
        mode = failure;
        final failedJob = UpdateDownload(
          clientFactory: () =>
              UpdateHttpClient(Uri.parse('http://127.0.0.1:${server.port}')),
          directory: () async => root,
        );
        await expectLater(
          failedJob.download(asset, onProgress: (_, _) {}),
          throwsFormatException,
        );
        expect(await File('${file.path}.part').exists(), isFalse);
        expect(await file.readAsBytes(), [80, 75, 3, 4]);
      }
    },
  );

  test('cancelled downloads remove partial package', () async {
    final root = await Directory.systemTemp.createTemp('update-cancel');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    server.listen((request) async {
      request.response.headers.contentType = ContentType.binary;
      request.response.bufferOutput = false;
      request.response.contentLength = 1024 * 1024;
      request.response.add(List.filled(32768, 1));
      await request.response.flush();
      await release.future;
      request.response.done.catchError((Object _) => request.response);
    });
    final job = UpdateDownload(
      clientFactory: () =>
          UpdateHttpClient(Uri.parse('http://127.0.0.1:${server.port}')),
      directory: () async => root,
    );
    await expectLater(
      job.download(
        ReleaseAsset(
          'cancel.apk',
          Uri.parse('https://github.com/test/test/cancel.apk'),
        ),
        onProgress: (received, _) {
          if (received > 0) job.cancel();
        },
      ),
      throwsA(anything),
    );
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'GitHub files are mirrored automatically while APIs and Gitee stay direct',
    () {
      final asset = releases(UpdateSource.github).single.assets.single;
      expect(
        githubUpdateMirror(asset.url).toString(),
        'https://gh-proxy.org/${asset.url}',
      );
      expect(
        githubUpdateMirror(UpdateSource.github.api),
        UpdateSource.github.api,
      );
      expect(
        githubUpdateMirror(UpdateSource.gitee.api),
        UpdateSource.gitee.api,
      );
      expect(
        githubUpdateMirror(githubUpdateMirror(asset.url)),
        githubUpdateMirror(asset.url),
      );
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'default source is GitHub and explicitly saved Gitee is preserved',
    () async {
      final u = controller();
      expect(u.source, UpdateSource.github);
      await u.loadSettings();
      expect(u.source, UpdateSource.github);
      await u.setSource(UpdateSource.gitee);
      final restored = controller();
      await restored.loadSettings();
      expect(restored.source, UpdateSource.gitee);
      u.dispose();
      restored.dispose();
    },
  );
  test('repository uses public source API without credentials and handles invalid responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = 200;
    var body = jsonEncode([
      {'tag_name': 'v0.4.0', 'body': '源内日志'},
    ]);
    final subscription = server.listen((request) async {
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
      request.response.statusCode = status;
      if (status == 302) {
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'https://evil.test',
        );
      }
      request.response.write(body);
      await request.response.close();
    });
    final clients = <UpdateHttpClient>[];
    final repository = ReleaseRepository(
      clientFactory: () {
        final c = UpdateHttpClient(
          Uri.parse('http://127.0.0.1:${server.port}'),
        );
        clients.add(c);
        return c;
      },
    );
    try {
      for (final source in UpdateSource.values) {
        expect((await repository.fetch(source)).single.notes, '源内日志');
        expect(clients.last.requests.single, source.api);
        expect(clients.last.closed, isTrue);
      }
      status = 403;
      await expectLater(
        repository.fetch(UpdateSource.gitee),
        throwsFormatException,
      );
      status = 302;
      await expectLater(
        repository.fetch(UpdateSource.gitee),
        throwsFormatException,
      );
      status = 200;
      body = '<html>login</html>';
      await expectLater(
        repository.fetch(UpdateSource.gitee),
        throwsFormatException,
      );
      expect(clients.every((c) => c.closed), isTrue);
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });
  test(
    'stable numeric versions and explicit build numbers compare correctly',
    () {
      AppVersion v(String s) => AppVersion.parse(s)!;
      expect(v('v0.10.0').newerThan(v('0.9.9+999')), isTrue);
      expect(v('0.3.5+15').newerThan(v('0.3.5+14')), isTrue);
      expect(v('0.3.5-15').newerThan(v('0.3.5.14')), isTrue);
      expect(v('0.3.5').newerThan(v('0.3.5+14')), isFalse);
      expect(v('0.3.5+15').newerThan(v('0.3.5')), isFalse);
      expect(v('0.3.4+99').newerThan(v('0.3.5+14')), isFalse);
      for (final tag in ['0.4.0-beta.1', 'v0.4.0-rc', 'main', '2026.11']) {
        expect(AppVersion.parse(tag), isNull);
      }
    },
  );
  test('only stable releases, source notes and repository-scoped assets are used', () {
    for (final source in UpdateSource.values) {
      final result = parseReleases([
        {'tag_name': 'v9.0.0', 'draft': true},
        {'tag_name': 'v8.0.0', 'prerelease': true},
        {'tag_name': 'v7.0.0-beta'},
        {'tag_name': 'v0.3.0'},
        {
          'tag_name': 'v0.4.0',
          'body': '  ${source.label} 日志  ',
          'assets': [
            {
              'name': 'bad.apk',
              'browser_download_url': 'https://evil.test/file.apk',
            },
            '${source.repository}/releases/download/v0.4.0/good.apk',
            {
              'name': 'insecure.apk',
              'browser_download_url':
                  '${source.repository.toString().replaceFirst('https', 'http')}/a.apk',
            },
          ],
        },
      ], source);
      expect(result.map((r) => r.tag), ['v0.4.0', 'v0.3.0']);
      expect(result.first.notes, '${source.label} 日志');
      expect(result.first.assets.single.name, 'good.apk');
      expect(result.first.page.host, source.repository.host);
    }
    expect(
      () => parseReleases({'message': 'rate limited'}, UpdateSource.github),
      throwsFormatException,
    );
  });
  test('download selection respects platform and architecture, unsupported platforms have no package', () {
    final source = UpdateSource.github;
    final release = parseReleases([
      {
        'tag_name': 'v0.4.0',
        'assets': [
          for (final name in [
            'app-x86_64.apk',
            'app-arm64-v8a.apk',
            'app-debug.apk',
            'app-macos-arm64.dmg',
            'app-windows-x64.zip',
          ])
            {
              'name': name,
              'browser_download_url':
                  '${source.repository}/releases/download/v0.4.0/$name',
            },
        ],
      },
    ], source).single;
    expect(
      release
          .packageFor(const UpdateRuntime(TargetPlatform.android, 'arm64'))!
          .path,
      endsWith('app-arm64-v8a.apk'),
    );
    expect(
      release
          .packageFor(const UpdateRuntime(TargetPlatform.macOS, 'arm64'))!
          .path,
      endsWith('.dmg'),
    );
    expect(
      release.packageFor(const UpdateRuntime(TargetPlatform.linux, 'x64')),
      isNull,
    );
    expect(
      release.packageFor(const UpdateRuntime(TargetPlatform.iOS, 'arm64')),
      isNull,
    );
  });
  test(
    'settings persist and startup is claimed once only when enabled',
    () async {
      final u = controller();
      await u.setSource(UpdateSource.github);
      await u.setAutomatic(false);
      await u.setReminder(false);
      final restored = controller();
      await restored.loadSettings();
      expect(restored.source, UpdateSource.github);
      expect(restored.remind, isFalse);
      expect(restored.claimStartup(), isFalse);
      await restored.setAutomatic(true);
      expect(restored.claimStartup(), isTrue);
      expect(restored.claimStartup(), isFalse);
      u.dispose();
      restored.dispose();
    },
  );
  test(
    'concurrent checks coalesce and changing source rejects late responses',
    () async {
      final old = Completer<List<AppRelease>>();
      var calls = 0;
      final u = controller(
        fetch: (source) {
          calls++;
          return source == UpdateSource.github
              ? old.future
              : Future.value(releases(source));
        },
      );
      final first = u.check();
      expect(identical(first, u.check()), isTrue);
      await Future<void>.delayed(Duration.zero);
      await u.setSource(UpdateSource.gitee);
      expect((await u.check())!.source, UpdateSource.gitee);
      old.complete(releases(UpdateSource.github));
      expect(await first, isNull);
      expect(u.latest!.source, UpdateSource.gitee);
      expect(calls, 2);
      u.dispose();
    },
  );
  test(
    'empty lists and failures are not reported as current; retry works',
    () async {
      var attempt = 0;
      final u = controller(
        fetch: (source) async {
          if (attempt++ == 0) return [];
          if (attempt == 2) throw const FormatException('请求受限');
          return releases(source);
        },
      );
      expect(await u.check(), isNull);
      expect(u.status, UpdateCheckStatus.noRelease);
      expect(await u.check(), isNull);
      expect(u.status, UpdateCheckStatus.failed);
      expect(u.error, '请求受限');
      expect(await u.check(), isNotNull);
      expect(u.status, UpdateCheckStatus.available);
      u.dispose();
    },
  );
  testWidgets(
    'startup waits for login, downloads in app with progress and requests installation',
    (tester) async {
      final pending = Completer<List<AppRelease>>();
      final job = FakeUpdateDownload();
      final installed = <File>[];
      final u = controller(
        fetch: (_) => pending.future,
        downloader: () => job,
        installer: (file) async {
          installed.add(file);
          return 'requested';
        },
      );
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [updateRouteObserver],
          home: UpdateStartupGate(
            updates: u,
            child: const Scaffold(body: Text('首页')),
          ),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('官方登录页')),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(releases(UpdateSource.github));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v0.4.0'), findsNothing);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('修复课表显示'), findsOneWidget);
      await tester.tap(find.text('下载'));
      await tester.pump();
      expect(find.text('下载中'), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      job.done.complete(File('/tmp/update.apk'));
      await tester.pumpAndSettle();
      expect(installed.single.path, '/tmp/update.apk');
      expect(find.text('已请求系统安装，请在系统界面确认。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      u.dispose();
    },
  );
  testWidgets(
    'reminder off suppresses startup dialog, manual check still shows release notes',
    (tester) async {
      final u = controller();
      await u.setReminder(false);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [updateRouteObserver],
          home: UpdateStartupGate(
            updates: u,
            child: UpdateSettingsPage(updates: u),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(u.status, UpdateCheckStatus.available);
      expect(find.text('修复课表显示'), findsNothing);
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('修复课表显示'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      u.dispose();
    },
  );
  for (final style in UiStyle.values) {
    testWidgets(
      '$style settings and long notes fit narrow screen and large text',
      (tester) async {
        tester.view.physicalSize = const Size(360, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final u = controller(
          fetch: (s) async => releases(
            s,
            notes: List.filled(60, '改进校园服务查询，修复登录状态。').join('\n'),
          ),
        );
        await u.setAutomatic(false);
        final state = AppState(updateController: u);
        await state.load();
        state.onboarded = true;
        await state.setUiStyle(style);
        state.fontScale = 1.3;
        await tester.pumpWidget(CampusApp(state: state));
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的').last);
        await tester.pumpAndSettle();
        final target = find.text('更新设置');
        await tester.scrollUntilVisible(
          target,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(target), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byType(UpdateSettingsPage), findsOneWidget);
        expect(find.text('v0.3.5 · Build 14'), findsOneWidget);
        expect(find.text('更新通道'), findsNothing);
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
        expect(find.text('取消'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}

class FakeUpdateDownload extends UpdateDownload {
  final done = Completer<File>();
  @override
  Future<File> download(
    ReleaseAsset asset, {
    required void Function(int, int?) onProgress,
  }) {
    onProgress(50, 100);
    return done.future;
  }
}
