import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/chaoxing/chaoxing.dart';
import 'package:nuist_aio/src/chaoxing/current_term.dart';
import 'package:nuist_aio/src/schedule/schedule.dart';

import 'schedule_test.dart' show fixture, row;
import 'service_sessions_test.dart' show FakeSession;

import 'package:nuist_aio/src/chaoxing/chaoxing_page.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/schedule/learning_page.dart';
import 'package:nuist_aio/src/services/site_registry.dart';

void autoConfirmCourses(ChaoxingRepository repository) {
  repository.addListener(() {
    final pending = repository.pendingSelection;
    if (pending != null) repository.confirmCourseSelection(pending.automatic);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });
  final course = {'courseId': '1', 'classId': '2', 'cpi': '3', 'title': '课程'};
  Map<String, dynamic> item(String kind, String title) => {
    'kind': kind,
    'title': title,
    'status': '未交',
    'state': 'todo',
    'time': '剩余1小时',
    'url': 'https://mooc1.chaoxing.com/work/detail?id=1',
  };
  test(
    'cold repository restores native session only after server probe',
    () async {
      var reads = 0;
      Future<Map<String, dynamic>> reader(Uri _, String task) async {
        reads++;
        expect(task, 'courses');
        return {
          'ok': true,
          'courses': [course],
        };
      }

      final first = ChaoxingRepository(documentReader: reader);
      await first.verify();
      expect(first.verified, true);
      await first.close();
      final cold = ChaoxingRepository(documentReader: reader);
      expect(cold.verified, false);
      final restored = await Future.wait([
        cold.restoreConnection(),
        cold.restoreConnection(),
        cold.restoreConnection(retry: true),
      ]);
      expect(restored, [true, true, true]);
      expect(reads, 2);
      expect(cold.verified, true);
      expect(cold.items, isEmpty); // Verification does not scan personal data.
      await cold.close(clearCookies: true);
      final removed = ChaoxingRepository(documentReader: reader);
      expect(await removed.restoreConnection(), false);
      expect(reads, 2);
      first.dispose();
      cold.dispose();
      removed.dispose();
    },
  );

  test('saved intent cannot authenticate expired session or revive removed account', () async {
    final first = ChaoxingRepository(
      documentReader: (_, _) async => {
        'ok': true,
        'courses': [course],
      },
    );
    await first.verify();
    final expired = ChaoxingRepository(
      documentReader: (_, _) async => {'ok': false, 'code': 'auth'},
    );
    expect(await expired.restoreConnection(), false);
    expect(expired.verified, false);
    final response = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    final late = ChaoxingRepository(
      documentReader: (_, _) {
        started.complete();
        return response.future;
      },
    );
    final restoring = late.restoreConnection();
    await started.future;
    await late.close(clearCookies: true);
    response.complete({
      'ok': true,
      'courses': [course],
    });
    expect(await restoring, false);
    expect(late.verified, false);
    final next = ChaoxingRepository(
      documentReader: (_, _) async =>
          throw StateError('removed accounts must not request'),
    );
    expect(await next.restoreConnection(), false);
    first.dispose();
    expired.dispose();
    late.dispose();
    next.dispose();
  });

  test('automatic restoration is registered but data refresh requires verified login', () async {
    var calls = 0;
    final r = ChaoxingRepository(
      documentReader: (_, _) async {
        calls++;
        return {
          'ok': true,
          'courses': [course],
        };
      },
    );
    final site = SchoolSites.get(SchoolSiteId.chaoxing);
    expect(site.auth, SiteAuth.nativeCookies);
    expect(site.automatic, true);
    expect(site.dependsOn, isEmpty);
    expect(site.probeTask, 'courses');
    expect(site.navigation!(site.entry), true);
    await r.refresh();
    expect(calls, 0);
    expect(r.verified, false);
    r.dispose();
  });
  test(
    'verification is separate from data scan and expiry requires manual login',
    () async {
      final tasks = <String>[];
      var auth = false;
      final r = ChaoxingRepository(
        documentReader: (_, task) async {
          tasks.add(task);
          return auth
              ? {'ok': false, 'code': 'auth'}
              : {
                  'ok': true,
                  'courses': [course],
                };
        },
      );
      autoConfirmCourses(r);
      await r.verify();
      expect(r.verified, true);
      expect(tasks, ['courses']);
      expect(r.items, isEmpty);
      auth = true;
      await r.refresh();
      expect(r.verified, false);
      expect(r.notice, isNotNull);
      r.dispose();
    },
  );
  test(
    'partial failure keeps failed list cache and updates successful list',
    () async {
      var phase = 0;
      final r = ChaoxingRepository(
        courseGap: Duration.zero,
        currentTerm: () async =>
            ChaoxingTermScope(ScheduleParser.parse(fixture([row(name: '课程')]))),
        documentReader: (url, task) async {
          if (task == 'courses') {
            return {
              'ok': true,
              'courses': [course],
            };
          }
          if (task == 'progress') {
            return {
              'ok': true,
              'progress': {'completed': 3, 'total': 10},
            };
          }
          if (task == 'meta') {
            return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
          }
          expect(url.queryParameters['stuenc'], 'a' * 32);
          if (task == 'work') {
            expect(url.queryParameters['enc'], 'b' * 32);
            if (phase == 1) return {'ok': false, 'code': 'parse'};
          }
          return {
            'ok': true,
            'items': [item(task, '$task $phase')],
          };
        },
      );
      autoConfirmCourses(r);
      await r.verify();
      await r.refresh();
      expect(r.items.map((e) => e.title), ['work 0', 'exam 0']);
      phase = 1;
      await r.refresh();
      expect(r.items.map((e) => e.title), ['work 0', 'exam 1']);
      expect(r.notice, contains('部分'));
      r.dispose();
    },
  );
  test(
    'account removal rejects late verification and clears cached data',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final r = ChaoxingRepository(documentReader: (_, _) => pending.future);
      final operation = r.verify();
      await r.close();
      pending.complete({
        'ok': true,
        'courses': [course],
      });
      await operation;
      expect(r.verified, false);
      expect(r.items, isEmpty);
      expect(r.busy, false);
      expect(r.notice, isNull);
      r.dispose();
    },
  );
  test(
    'rate limit prevents subsequent network requests during cooling period',
    () async {
      var calls = 0;
      final r = ChaoxingRepository(
        documentReader: (_, _) async {
          calls++;
          return {'ok': false, 'code': 'busy'};
        },
      );
      autoConfirmCourses(r);
      await r.verify();
      autoConfirmCourses(r);
      await r.verify();
      expect(calls, 1);
      expect(r.verified, false);
      expect(r.busyUntil, isNotNull);
      r.dispose();
    },
  );
  test('course progress preserves valid cache on failure and clears on account change', () async {
    var fail = false;
    final r = ChaoxingRepository(
      courseGap: Duration.zero,
      currentTerm: () async =>
          ChaoxingTermScope(ScheduleParser.parse(fixture([row(name: '课程')]))),
      documentReader: (url, task) async {
        if (task == 'courses') {
          return {
            'ok': true,
            'courses': [course],
          };
        }
        if (task == 'meta') {
          return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
        }
        if (task == 'progress') {
          return fail
              ? {'ok': false, 'code': 'parse'}
              : {
                  'ok': true,
                  'progress': {'completed': 4, 'total': 12},
                };
        }
        return {'ok': true, 'items': []};
      },
    );
    autoConfirmCourses(r);
    await r.verify();
    await r.refresh();
    expect(r.courses.single.completed, 4);
    expect(r.courses.single.total, 12);
    expect(r.courses.single.failed, false);
    fail = true;
    await r.refresh();
    expect(r.courses.single.completed, 4);
    expect(r.courses.single.failed, true);
    expect(r.notice, contains('任务点未读取'));
    await r.close();
    expect(r.courses, isEmpty);
    r.dispose();
  });
  testWidgets(
    'course tab displays progress and switches to existing task filters',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      state.chaoxing.verified = true;
      state.chaoxing.updatedAt = DateTime.now();
      state.chaoxing.courses = [
        ChaoxingCourse(
          key: '1:2',
          title: '测试课程',
          alias: '本学期',
          url: Uri.https('mooc1.chaoxing.com', '/visit/stucoursemiddle'),
          completed: 3,
          total: 12,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ChaoxingPanel(state: state)),
          ),
        ),
      );
      expect(find.text('测试课程'), findsOneWidget);
      expect(find.text('已完成任务点 3 / 12'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('未完成 0'), findsNothing);
      await tester.tap(find.text('作业与考试'));
      await tester.pumpAndSettle();
      expect(find.text('未完成 0'), findsOneWidget);
      expect(find.text('测试课程'), findsNothing);
      await tester.tap(find.text('课程').first);
      await tester.pumpAndSettle();
      expect(find.text('测试课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('late progress cannot restore courses after account removal', () async {
    final started = Completer<void>();
    final pending = Completer<Map<String, dynamic>>();
    final r = ChaoxingRepository(
      courseGap: Duration.zero,
      currentTerm: () async =>
          ChaoxingTermScope(ScheduleParser.parse(fixture([row(name: '课程')]))),
      documentReader: (url, task) async {
        if (task == 'courses') {
          return {
            'ok': true,
            'courses': [course],
          };
        }
        if (task == 'meta') {
          return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
        }
        if (task == 'progress') {
          started.complete();
          return pending.future;
        }
        return {'ok': true, 'items': []};
      },
    );
    autoConfirmCourses(r);
    await r.verify();
    final scanning = r.refresh();
    await started.future;
    await r.close();
    pending.complete({
      'ok': true,
      'progress': {'completed': 9, 'total': 10},
    });
    await scanning;
    expect(r.courses, isEmpty);
    expect(r.items, isEmpty);
    expect(r.updatedAt, isNull);
    r.dispose();
  });
  test('legacy login destination upgrades without broadening trust', () {
    final raw = Uri.parse('http://i.mooc.chaoxing.com/?refer=opaque#section');
    final secure = chaoxingHttpsUpgrade(raw)!;
    expect(secure.scheme, 'https');
    expect(secure.host, raw.host);
    expect(secure.query, raw.query);
    expect(secure.fragment, raw.fragment);
    expect(chaoxingNavigation(raw), false);
    expect(chaoxingNavigation(secure), true);
    for (final url in [
      'http://evil.org/',
      'http://i.mooc.chaoxing.com.evil.org/',
      'http://user@i.mooc.chaoxing.com/',
      'http://i.mooc.chaoxing.com:8080/',
      'http://i.mooc.chaoxing.com/unknown',
      'http://passport2.chaoxing.com/login',
      'https://i.mooc.chaoxing.com/',
    ]) {
      expect(chaoxingHttpsUpgrade(Uri.parse(url)), isNull);
    }
  });
  test('current roster excludes unrelated and explicitly historical same-name courses', () {
    final scope = ChaoxingTermScope(
      ScheduleParser.parse(fixture([row(name: '大学物理Ⅱ')])),
    );
    for (final course in [
      {'title': '大学物理II', 'alias': '本学期'},
      {'title': '大学物理Ⅱ', 'alias': '26-27-1'},
      {'title': '时间待定课程', 'alias': ''},
    ]) {
      expect(scope.includes(course), true);
    }
    for (final course in [
      {'title': '大学物理II', 'alias': '25-26-2'},
      {'title': '大学物理II', 'alias': '2025-2026学年第二学期'},
      {'title': '历史课程', 'alias': '教师甲'},
      {'title': '大学物理I', 'alias': ''},
      {'title': '大学物理Ⅱ（选课指导）', 'alias': '26-27-1'},
      {'title': '大学物理Ⅱ', 'alias': '本学期选课指导'},
      {'title': '大学物理Ⅱ（选 课 指 导）', 'alias': ''},
    ]) {
      expect(scope.includes(course), false);
    }
    expect(ChaoxingTermScope.explicitTerm('2025级'), isNull);
    expect(ChaoxingTermScope.explicitTerm('2026-2027学年第一学期'), '2026-2027-1');
  });
  test('scan reads only current roster and never falls back to all courses', () async {
    final reads = <String>[];
    final scope = ChaoxingTermScope(
      ScheduleParser.parse(fixture([row(name: '课程')])),
    );
    final r = ChaoxingRepository(
      courseGap: Duration.zero,
      currentTerm: () async => scope,
      documentReader: (url, task) async {
        reads.add(
          '$task:${url.queryParameters['courseid'] ?? url.queryParameters['courseId'] ?? ''}',
        );
        if (task == 'courses') {
          return {
            'ok': true,
            'courses': [
              course,
              {...course, 'courseId': '8', 'alias': '2025-2026-2'},
              {...course, 'courseId': '9', 'title': '以前的课'},
              {...course, 'courseId': '10', 'title': '课程（选课指导）'},
              {...course, 'courseId': '11', 'alias': '选课指导'},
            ],
          };
        }
        if (task == 'progress') {
          return {
            'ok': true,
            'progress': {'completed': 3, 'total': 10},
          };
        }
        if (task == 'meta') {
          return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
        }
        return {'ok': true, 'items': []};
      },
    );
    autoConfirmCourses(r);
    await r.verify();
    await r.refresh();
    expect(r.totalCourseCount, 5);
    expect(r.selectedCourseCount, 1);
    expect(r.scanTerm, '2026-2027-1');
    expect(reads.where((s) => s.startsWith('meta')), ['meta:1']);
    expect(reads.any((s) => [':8', ':9', ':10', ':11'].any(s.endsWith)), false);
    reads.clear();
    r.currentTerm = () async => throw const FormatException('名单不可用');
    await r.refresh();
    expect(reads, ['courses:']);
    expect(r.notice, '名单不可用');
    r.dispose();
  });
  test('app scan uses server current term without replacing the displayed historical timetable', () async {
    final calls = <String>[];
    final repository = ChaoxingRepository(
      courseGap: Duration.zero,
      documentReader: (url, task) async {
        if (task == 'courses') {
          return {
            'ok': true,
            'courses': [course],
          };
        }
        if (task == 'progress') {
          return {
            'ok': true,
            'progress': {'completed': 3, 'total': 10},
          };
        }
        if (task == 'meta') {
          return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
        }
        return {'ok': true, 'items': []};
      },
    );
    final state = AppState(
      chaoxingRepository: repository,
      teachingSession: FakeSession((task, args) async {
        calls.add(task);
        if (task == 'semesters') {
          return {
            'ok': true,
            'current': '2026-2027-1',
            'terms': [
              {'DM': '2026-2027-1', 'MC': '本学期'},
            ],
          };
        }
        expect(args['term'], '2026-2027-1');
        // Missing time information is irrelevant to an enrollment roster.
        return {
          'ok': true,
          'data': fixture([
            {'KCM': '课程', 'SKJS': '教师甲'},
          ]),
        };
      }),
    );
    state.connectedAt = DateTime.now();
    final historical = ScheduleParser.parse({
      ...fixture([row(name: '旧课')]),
      'term': '2025-2026-2',
    });
    state.schedule = historical;
    autoConfirmCourses(repository);
    await repository.verify();
    await state.refreshChaoxing();
    expect(calls, ['semesters', 'schedule']);
    expect(repository.selectedCourseCount, 1);
    expect(identical(state.schedule, historical), true);
    state.dispose();
  });
  test(
    'navigation and outbound links reject spoofed hosts, ports and credentials',
    () {
      for (final u in [
        'http://mooc1.chaoxing.com/work',
        'https://mooc1.chaoxing.com.evil.org/',
        'https://evil@mooc1.chaoxing.com/',
        'https://mooc1.chaoxing.com:444/',
        'javascript:alert(1)',
        'intent://work',
        'https://passport2.chaoxing.com/login',
      ]) {
        expect(chaoxingItemLink(Uri.parse(u)), false);
      }
      expect(
        chaoxingItemLink(Uri.parse('https://mooc1.chaoxing.com/work?id=2')),
        true,
      );
    },
  );
  test(
    'Android tries the exact item link in the app, then falls back to browser',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      var appOpens = false;
      messenger.setMockMethodCallHandler(
        const MethodChannel('nuistaio/chaoxing'),
        (call) async {
          calls.add('app:${call.arguments}');
          return appOpens;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          calls.add('browser:${call.arguments['url']}');
          return true;
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('nuistaio/chaoxing'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
      });
      final url = Uri.parse('https://mooc1.chaoxing.com/work/detail?id=7');
      expect(await launchChaoxingItem(url), true);
      expect(calls, ['app:$url', 'browser:$url']);
      calls.clear();
      appOpens = true;
      expect(await launchChaoxingItem(url), true);
      expect(calls, ['app:$url']);
      calls.clear();
      expect(await launchChaoxingItem(url, browserOnly: true), true);
      expect(calls, ['browser:$url']);
      calls.clear();
      expect(await launchChaoxingItem(Uri.parse('https://evil.org/')), false);
      expect(calls, isEmpty);
    },
  );
  testWidgets(
    'opening connection settings preserves verified session and cached items',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      state.chaoxing.verified = true;
      state.chaoxing.items = [
        ChaoxingItem.fromJson(item('work', '已读取的作业'), '课程', courseKey: '1:2'),
      ];
      final generation = state.chaoxing.generation;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChaoxingAccountTile(state: state)),
        ),
      );
      await tester.tap(find.text('学习通登录'));
      await tester.pumpAndSettle();
      expect(find.text('连接学习通'), findsOneWidget);
      expect(state.chaoxing.verified, true);
      expect(state.chaoxing.generation, generation);
      expect(state.chaoxing.items.single.title, '已读取的作业');
      expect(find.text('重新登录 / 切换账号'), findsOneWidget);
      await tester.tap(find.text('重新登录 / 切换账号'));
      await tester.pumpAndSettle();
      expect(state.chaoxing.verified, false);
      expect(state.chaoxing.items, isEmpty);
      expect(state.chaoxing.generation, generation + 1);
    },
  );
  test('weak course matching tolerates names and qualifiers while preserving sequence', () {
    for (final names in [
      ('高等数学（理工类）', '高等数学A'),
      ('大学英语读写', '大学英语读写教程'),
      ('程序设计基础', '程序设计基础与实践'),
      ('大学物理（Ⅱ）', '大学物理II'),
    ]) {
      expect(ChaoxingTermScope.weakMatch(names.$1, names.$2), true);
    }
    expect(ChaoxingTermScope.weakMatch('大学英语I', '大学英语II'), false);
    expect(ChaoxingTermScope.weakMatch('程序设计', '英语听力'), false);
  });
  testWidgets(
    'task filters separate grading and expiry and retain all counts',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      state.chaoxing.verified = true;
      state.chaoxing.items = [
        for (final entry in {
          '未完成条目': '未提交',
          '待批改条目': '待批阅',
          '已完成条目': '已完成',
          '已过期条目': '已过期未交',
        }.entries)
          ChaoxingItem.fromJson({
            ...item('work', entry.key),
            'status': entry.value,
            'state': entry.value == '已完成' ? 'done' : 'todo',
          }, '课程'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ChaoxingPanel(state: state)),
          ),
        ),
      );
      await tester.tap(find.text('作业与考试'));
      await tester.pumpAndSettle();
      expect(find.text('未完成 1'), findsOneWidget);
      expect(find.text('待批改 1'), findsOneWidget);
      expect(find.text('已完成 1'), findsOneWidget);
      expect(find.text('已过期 1'), findsOneWidget);
      await tester.tap(find.text('待批改 1'));
      await tester.pumpAndSettle();
      expect(find.text('待批改条目'), findsOneWidget);
      expect(find.text('未完成条目'), findsNothing);
      await tester.tap(find.text('已过期 1'));
      await tester.pumpAndSettle();
      expect(find.text('已过期条目'), findsOneWidget);
      expect(find.text('待批改条目'), findsNothing);
      await tester.tap(find.text('课程').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('作业与考试'));
      await tester.pumpAndSettle();
      expect(find.text('已过期条目'), findsOneWidget);
      expect(find.text('待批改条目'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'expiry uses school deadline and never mistakes exam start for deadline',
    () {
      final now = DateTime.utc(2026, 11, 10, 4);
      expect(chaoxingDeadline('开始时间：2026-11-09 10:00', now: now), isNull);
      expect(
        chaoxingDeadline('结束时间：2026-11-09 10:00', now: now),
        DateTime.utc(2026, 11, 9, 2),
      );
      expect(chaoxingDeadline('结束时间：2026-02-30 10:00', now: now), isNull);
      expect(
        chaoxingDeadline('剩余1小时20分钟', now: now),
        now.add(const Duration(minutes: 80)),
      );
      expect(
        chaoxingDeadline(
          '开始时间：2026-11-09 10:00 结束时间：2026-11-12 18:00',
          now: now,
        ),
        DateTime.utc(2026, 11, 12, 10),
      );
      expect(
        ChaoxingItem.fromJson({
          ...item('work', '旧作业'),
          'time': '结束时间：2020-01-01 10:00',
        }, '课程').group,
        'expired',
      );
      expect(
        ChaoxingItem.fromJson({
          ...item('work', '已提交作业'),
          'state': 'done',
          'status': '已提交',
          'time': '结束时间：2020-01-01 10:00',
        }, '课程').group,
        'done',
      );
    },
  );
  test('successful connection automatically starts data sync without manual refresh', () async {
    final scanned = Completer<void>();
    final repository = ChaoxingRepository(
      courseGap: Duration.zero,
      documentReader: (url, task) async {
        if (task == 'courses') {
          return {
            'ok': true,
            'courses': [course],
          };
        }
        if (task == 'progress') {
          return {
            'ok': true,
            'progress': {'completed': 3, 'total': 10},
          };
        }
        if (task == 'meta') {
          if (!scanned.isCompleted) scanned.complete();
          return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
        }
        return {'ok': true, 'items': []};
      },
    );
    final state = AppState(
      chaoxingRepository: repository,
      teachingSession: FakeSession((task, args) async {
        if (task == 'semesters') {
          return {
            'ok': true,
            'current': '2026-2027-1',
            'terms': [
              {'DM': '2026-2027-1', 'MC': '当前学期'},
            ],
          };
        }
        return {
          'ok': true,
          'data': fixture([row(name: '课程')]),
        };
      }),
    );
    state.connectedAt = DateTime.now();
    autoConfirmCourses(repository);
    expect(await state.connectChaoxing(), true);
    await scanned.future;
    expect(repository.selectedCourseCount, 1);
    state.dispose();
  });
  testWidgets(
    'learning has third tab and does not fetch before manual connection',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LearningPage(state: state)),
        ),
      );
      expect(find.text('课程安排'), findsOneWidget);
      expect(find.text('学业服务'), findsOneWidget);
      await tester.tap(find.text('学习通'));
      await tester.pump();
      expect(find.byType(ChaoxingPanel), findsOneWidget);
      expect(find.text('学习通登录'), findsOneWidget);
      expect(state.chaoxing.busy, false);
    },
  );
}
