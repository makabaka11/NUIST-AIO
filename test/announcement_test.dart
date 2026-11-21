import 'dart:io';

import 'package:flutter/material.dart' as md;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:nuist_aio/src/announcements/announcement.dart';
import 'package:nuist_aio/src/announcements/announcement_service.dart';
import 'package:nuist_aio/src/announcements/announcement_ui.dart';
import 'package:nuist_aio/src/app.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/services/site_registry.dart';

const _rawSource =
    'https://raw.githubusercontent.com/makabaka11/NUIST-AIO/main/announcement.md';

Announcement _sample({String title = '期末考试安排', String body = '请携带学生证参加考试。'}) =>
    Announcement(
      title: title,
      publisher: '教务处',
      body: body,
      publishedAt: DateTime(2026, 11, 20),
      source: Uri.parse(_rawSource),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('announcement format', () {
    test('parses front matter and preserves Markdown body', () {
      final announcement = parseAnnouncement('''
---
title: "期末考试安排"
publisher: 教务处
date: 2026-11-20
unknown: ignored
---

## 考试时间

请携带学生证参加考试。

![考场](images/exam-room.png)

[查看原文](docs/exam.md)
''', source: Uri.parse(_rawSource));

      expect(announcement.title, '期末考试安排');
      expect(announcement.publisher, '教务处');
      expect(announcement.publishedLabel, '2026-11-20');
      expect(announcement.body, contains('## 考试时间'));
      expect(announcement.body, contains('![考场]'));

      final image = resolveAnnouncementUri(
        Uri.parse('images/exam-room.png'),
        announcement.source,
      );
      expect(
        image.toString(),
        'https://raw.githubusercontent.com/makabaka11/NUIST-AIO/main/images/exam-room.png',
      );

      final imageCandidates = resolveAnnouncementImageCandidates(
        Uri.parse('images/exam-room.png'),
        announcement.source,
      );
      expect(imageCandidates.map((url) => url.host).toList(), [
        'gh-proxy.org',
        'cdn.jsdelivr.net',
        'raw.githubusercontent.com',
      ]);
      expect(
        resolveAnnouncementImageCandidates(
          Uri.parse('https://example.com/image.png'),
          announcement.source,
        ).length,
        1,
      );

      final link = resolveAnnouncementUri(
        Uri.parse('docs/exam.md'),
        AppAnnouncementSource.page,
      );
      expect(
        link.toString(),
        'https://github.com/makabaka11/NUIST-AIO/blob/main/docs/exam.md',
      );
    });

    test('accepts the heading fallback with blockquote metadata', () {
      final announcement = parseAnnouncement('''
# 关于选课的通知
> 发布者：教务处
> 发布日期：2026-11-19

选课系统将于周五开放。
''', source: Uri.parse(_rawSource));

      expect(announcement.title, '关于选课的通知');
      expect(announcement.publisher, '教务处');
      expect(announcement.publishedLabel, '2026-11-19');
      expect(announcement.body, '选课系统将于周五开放。');
    });

    test('rejects incomplete or malformed notices', () {
      final source = Uri.parse(_rawSource);
      for (final text in [
        '',
        '---\ntitle: 没有发布者\n---\n正文',
        '---\ntitle: 缺少结束\n\n正文',
        '# 没有发布者\n\n正文',
        '---\ntitle: 标题\npublisher: 教务处\n---\n\n',
        '没有标题\n发布者：教务处\n正文',
      ]) {
        expect(
          () => parseAnnouncement(text, source: source),
          throwsA(isA<FormatException>()),
          reason: text,
        );
      }
    });

    test('only resolves HTTP(S) links without embedded credentials', () {
      final base = Uri.parse(_rawSource);
      expect(
        resolveAnnouncementUri(Uri.parse('https://example.com/a'), base),
        isNotNull,
      );
      expect(
        resolveAnnouncementUri(Uri.parse('http://example.com/a'), base),
        isNotNull,
      );
      for (final value in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,hi',
        'https://user:pass@example.com/a',
      ]) {
        expect(
          resolveAnnouncementUri(Uri.parse(value), base),
          isNull,
          reason: value,
        );
      }
    });

    test('repository announcement.md is published in a usable format', () {
      final file = File('announcement.md');
      final announcement = parseAnnouncement(
        file.readAsStringSync(),
        source: Uri.parse(_rawSource),
      );
      expect(announcement.title, isNotEmpty);
      expect(announcement.publisher, isNotEmpty);
      expect(announcement.body, contains('公告'));
      final image = resolveAnnouncementUri(
        Uri.parse('assets/branding/app_icon.png'),
        announcement.source,
      );
      expect(image, isNotNull);
      expect(image!.host, 'raw.githubusercontent.com');
    });

    test('announcement source prefers the gh-proxy GitHub mirror', () {
      expect(AppAnnouncementSource.mirror.host, 'gh-proxy.org');
      expect(
        AppAnnouncementSource.mirror.toString(),
        startsWith(
          'https://gh-proxy.org/https://raw.githubusercontent.com/makabaka11/NUIST-AIO/main/announcement.md',
        ),
      );
      final candidates = AppAnnouncementSource.candidates;
      expect(candidates.first, AppAnnouncementSource.mirror);
      expect(candidates.map((url) => url.host).toList(), [
        'gh-proxy.org',
        'raw.githubusercontent.com',
        'cdn.jsdelivr.net',
      ]);
    });

    test('cache JSON round trip keeps the canonical source', () {
      final original = _sample();
      final decoded = Announcement.fromCacheJson(original.toCacheJson());
      expect(decoded, isNotNull);
      expect(decoded!.title, original.title);
      expect(decoded.publisher, original.publisher);
      expect(decoded.body, original.body);
      expect(decoded.source, original.source);
      expect(decoded.publishedLabel, original.publishedLabel);
    });
  });

  group('announcement controller', () {
    test('restores cache and keeps it when refresh fails', () async {
      final first = AnnouncementController(fetch: () async => _sample());
      await first.refresh();
      expect(first.announcement?.title, '期末考试安排');
      expect(first.fromCache, isFalse);

      final restored = AnnouncementController(
        fetch: () async => throw const FormatException('公告文件暂时不可用'),
      );
      await restored.restoreCache();
      expect(restored.announcement?.title, '期末考试安排');
      expect(restored.fromCache, isTrue);

      await restored.refresh();
      expect(restored.status, AnnouncementStatus.failed);
      expect(restored.error, '公告文件暂时不可用');
      expect(restored.announcement?.title, '期末考试安排');
      expect(restored.fromCache, isTrue);
    });

    test('dismisses for the session and shows changed content again', () async {
      var announcement = _sample();
      final controller = AnnouncementController(
        fetch: () async => announcement,
      );
      await controller.refresh();
      controller.dismiss();
      expect(controller.dismissed, isTrue);

      announcement = _sample(body: '考试地点调整为明德楼。');
      await controller.refresh();
      expect(controller.dismissed, isFalse);

      controller.dismiss();
      await controller.refresh();
      expect(controller.dismissed, isTrue);
    });

    test('startup refresh is requested only once', () async {
      var calls = 0;
      final controller = AnnouncementController(
        fetch: () async {
          calls++;
          return _sample();
        },
      );
      controller.refreshOnStartup();
      controller.refreshOnStartup();
      await controller.refresh();
      expect(calls, 1);
    });
  });

  group('announcement repository', () {
    test('fetches Markdown over HTTP and ignores HTML responses', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var html = false;
      server.listen((request) async {
        if (html) {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html><body>login</body></html>');
        } else {
          request.response.headers.contentType = ContentType(
            'text',
            'plain',
            charset: 'utf-8',
          );
          request.response.write('''
---
title: 测试公告
publisher: 测试部门
---

正文内容。
''');
        }
        await request.response.close();
      });
      final source = Uri.parse(
        'http://127.0.0.1:${server.port}/announcement.md',
      );
      final repository = AnnouncementRepository(
        clientFactory: _realClient,
        candidates: [source],
        canonicalSource: Uri.parse(_rawSource),
      );
      final announcement = await repository.fetch();
      expect(announcement.title, '测试公告');
      expect(announcement.publisher, '测试部门');

      html = true;
      await expectLater(
        repository.fetch(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('网页'),
          ),
        ),
      );
    });

    test('falls back to the next candidate after a failed source', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var calls = 0;
      server.listen((request) async {
        calls++;
        if (calls == 1) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.write('''
---
title: 兜底公告
publisher: 教务处
---

兜底正文。
''');
        }
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final repository = AnnouncementRepository(
        clientFactory: _realClient,
        candidates: [
          Uri.parse('$base/missing.md'),
          Uri.parse('$base/announcement.md'),
        ],
        canonicalSource: Uri.parse(_rawSource),
      );
      final announcement = await repository.fetch();
      expect(announcement.title, '兜底公告');
      expect(calls, 2);
    });
  });

  group('announcement UI', () {
    Future<AppState> mount(
      WidgetTester tester, {
      bool miuix = false,
      String body = '## 考试时间\n\n请携带学生证参加考试。',
    }) async {
      tester.view.physicalSize = const md.Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AnnouncementController(
        fetch: () async => _sample(body: body),
      );
      final state = AppState(announcementController: controller);
      await state.load();
      state.onboarded = true;
      await state.setLiquidGlassNav(false);
      if (miuix) await state.setUiStyle(UiStyle.miuix);
      await tester.pumpWidget(CampusApp(state: state));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('home banner opens the Markdown detail and can be dismissed', (
      tester,
    ) async {
      await mount(tester);
      expect(find.text('期末考试安排'), findsOneWidget);
      expect(find.textContaining('教务处'), findsOneWidget);

      await tester.tap(find.text('期末考试安排'));
      await tester.pumpAndSettle();
      expect(find.text('公告'), findsOneWidget);
      expect(find.text('期末考试安排'), findsOneWidget);
      expect(find.textContaining('请携带学生证参加考试。'), findsOneWidget);

      md.Navigator.of(tester.element(find.text('公告'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭公告'));
      await tester.pumpAndSettle();
      expect(find.text('期末考试安排'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('banner uses MIUIX components when that style is selected', (
      tester,
    ) async {
      await mount(tester, miuix: true);
      expect(find.text('期末考试安排'), findsOneWidget);
      expect(find.byType(md.Card), findsNothing);
      expect(find.byType(md.ListTile), findsNothing);
      expect(find.byType(md.IconButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('banner fits narrow screens with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const md.Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = AnnouncementController(fetch: () async => _sample());
      final state = AppState(announcementController: controller);
      await state.load();
      state.onboarded = true;
      await state.setLiquidGlassNav(false);
      await tester.pumpWidget(CampusApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('期末考试安排'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await state.setUiStyle(UiStyle.miuix);
      await tester.pumpAndSettle();
      expect(find.text('期末考试安排'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders blockquotes, lists, code and tables', (tester) async {
      await tester.pumpWidget(
        md.MaterialApp(
          home: AnnouncementPage(
            announcement: _sample(
              body:
                  '> 请提前十分钟到场。\n\n'
                  '- 携带学生证\n'
                  '- 关闭手机\n\n'
                  '| 科目 | 时间 |\n| --- | --- |\n| 高数 | 09:00 |\n\n'
                  '使用 `校园卡` 入场。',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('请提前十分钟到场。'), findsOneWidget);
      expect(find.textContaining('携带学生证'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed images fall back and show a placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        md.MaterialApp(
          home: AnnouncementPage(
            announcement: _sample(body: '![考场](images/exam-room.png)'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('图片加载失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a Markdown link opens the resolved URL', (
      tester,
    ) async {
      Uri? opened;
      await tester.pumpWidget(
        md.MaterialApp(
          home: AnnouncementPage(
            announcement: _sample(body: '[打开链接](https://example.com/path)'),
            openLink: (url) async {
              opened = url;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开链接', findRichText: true));
      await tester.pump();
      expect(opened, Uri.parse('https://example.com/path'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cached notice is labelled as a cached copy', (tester) async {
      final controller = AnnouncementController(fetch: () async => _sample());
      await controller.refresh();
      // A fresh controller restores the persisted copy before the network
      // request; simulate the offline path by mounting with a cache-only state.
      final offline = AppState(
        announcementController: AnnouncementController(
          fetch: () async => throw const FormatException('离线'),
        ),
      );
      await offline.load();
      offline.onboarded = true;
      await offline.setLiquidGlassNav(false);
      await tester.pumpWidget(CampusApp(state: offline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('期末考试安排'));
      await tester.pumpAndSettle();
      expect(find.textContaining('上次成功读取的公告'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

HttpClient _realClient() {
  final inner = HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
  return inner;
}

class _RealHttp extends HttpOverrides {}
