import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nuist_aio/src/auth/session_store.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nuist_aio/src/academic/academic.dart';
import 'package:nuist_aio/src/academic/rooms_page.dart';
import 'package:nuist_aio/src/academic/room_availability.dart';
import 'package:nuist_aio/src/academic/academic_page.dart';
import 'package:nuist_aio/src/app_state.dart';

import 'service_sessions_test.dart' show FakeSession;

void main() {
  test('exam status uses China end time and leaves missing times unknown', () {
    final now = DateTime.parse('2026-11-11T04:00:00Z');
    expect(examCompleted({'KSRQ': '2026-11-11', 'KSJSSJ': '12:00'}, now), true);
    expect(
      examCompleted({'KSRQ': '2026-11-11', 'KSSJMS': '13:00-15:00'}, now),
      false,
    );
    expect(examCompleted({'KSJSSJ': '2026-11-10 12:00:00'}, now), true);
    expect(examCompleted({'KSRQ': '2026-11-10'}, now), null);
    expect(examCompleted({'KSSJMS': '时间待定'}, now), null);
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('Mac cookie recovery rejects unknown, expired and expanded scopes', () {
    final origin = Uri.parse(SessionStore.origins.first),
        now = DateTime(2026, 11, 9);
    Cookie sample({
      String? domain = 'authserver.nuist.edu.cn',
      String? path = '/authserver',
      bool? secure = true,
      int? expires,
    }) => Cookie(
      name: 'synthetic',
      value: 'synthetic',
      domain: domain,
      path: path,
      isSecure: secure,
      isHttpOnly: true,
      expiresDate: expires,
    );
    expect(SessionStore.canRestoreCookie(origin, sample(), now), isTrue);
    for (final c in [
      sample(domain: null),
      sample(domain: '.nuist.edu.cn'),
      sample(path: null),
      sample(path: '/other'),
      sample(secure: null),
      sample(expires: now.millisecondsSinceEpoch - 1),
    ]) {
      expect(SessionStore.canRestoreCookie(origin, c, now), isFalse);
    }
    expect(
      SessionStore.canRestoreCookie(
        Uri.parse('https://other.test/'),
        sample(),
        now,
      ),
      isFalse,
    );
  });
  test('format credits without losing integer zeros or treating missing GPA as zero', () {
    expect(creditNumber(60), '60');
    expect(creditNumber(0), '0');
    expect(creditNumber(3.5), '3.5');
    expect(creditNumber(null), '—');
    for (final feature in AcademicFeature.values) {
      expect(feature.entry.host, 'jwxt.nuist.edu.cn');
      expect(feature.entry.scheme, 'https');
    }
  });
  test('GPA formatting preserves official precision and missing values', () {
    expect(gpaNumber('3.127'), '3.127');
    expect(gpaNumber('3.000'), '3.000');
    expect(gpaNumber(0), '0');
    for (final value in [null, '', 'NaN', 'Infinity', -1, false]) {
      expect(gpaNumber(value), '—');
    }
    expect(gradeAnalysisEntry.fragment, '/cjfx');
  });
  for (final mode in ['success', 'gpaFailure', 'creditFailure']) {
    testWidgets(
      'academic monitoring separates official GPA from credits: $mode',
      (tester) async {
        final session = FakeSession((task, _) async {
          if (task == 'gradeAnalysis') {
            if (mode == 'gpaFailure') return {'ok': false};
            return {
              'ok': true,
              'gpa': '3.127',
              'rows': [
                {'XNXQDM_DISPLAY': '测试学期', 'GPA': '0.000'},
              ],
            };
          }
          if (task == 'creditPlans') {
            return {
              'ok': true,
              'plans': [
                {'value': 'test-plan', 'label': '测试方案'},
              ],
            };
          }
          if (mode == 'creditFailure') {
            return {'ok': false, 'error': '学分报告暂不可用'};
          }
          return {
            'ok': true,
            'report': {
              'name': '总学分',
              'creditsEarned': 20,
              'creditsRequired': 100,
            },
            'completed': 20,
            'outside': 0,
            'rows': [
              {
                'XNXQDM_DISPLAY': '测试学期',
                'YXXF': 20,
                'YHXF': 20,
                'XQGPA': 9.999,
                'LJGPA': 8.888,
              },
            ],
          };
        });
        final state = AppState(teachingSession: session)
          ..connectedAt = DateTime(2026);
        await tester.pumpWidget(
          MaterialApp(
            home: AcademicPage(state: state, feature: AcademicFeature.credits),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('9.999'), findsNothing);
        expect(find.textContaining('8.888'), findsNothing);
        expect(find.text('成绩分析原网页'), findsNothing);
        if (mode == 'gpaFailure') {
          expect(find.textContaining('成绩单 GPA 暂未读取'), findsOneWidget);
          expect(find.text('成绩单 GPA 3.127'), findsNothing);
          expect(find.text('学分完成情况'), findsOneWidget);
        } else {
          expect(find.text('成绩单 GPA 3.127'), findsOneWidget);
          expect(find.text('测试学期 GPA 0.000'), findsOneWidget);
          if (mode == 'creditFailure') {
            expect(find.text('学分报告暂不可用'), findsOneWidget);
          }
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
  testWidgets(
    'account change discards late GPA before querying credit reports',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final session = FakeSession((task, _) => pending.future);
      final state = AppState(teachingSession: session)
        ..connectedAt = DateTime(2026);
      await tester.pumpWidget(
        MaterialApp(
          home: AcademicPage(state: state, feature: AcademicFeature.credits),
        ),
      );
      await tester.pump();
      await state.clearSchedule();
      pending.complete({'ok': true, 'gpa': '3.127', 'rows': []});
      await tester.pumpAndSettle();
      expect(find.text('成绩单 GPA 3.127'), findsNothing);
      expect(session.calls.length, 1);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'logged out view never queries academic data and has browser entry',
    (tester) async {
      final session = FakeSession((_, _) async => {'ok': true, 'rows': []});
      final state = AppState(teachingSession: session);
      await tester.pumpWidget(
        MaterialApp(
          home: AcademicPage(state: state, feature: AcademicFeature.grades),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.calls, isEmpty);
      expect(find.text('请先连接校园账号'), findsOneWidget);
      expect(find.byTooltip('在浏览器中打开'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'grade screen preserves zero score and displays actual course GPA',
    (tester) async {
      final session = FakeSession(
        (_, _) async => {
          'ok': true,
          'rows': [
            {
              'KCM': '测试课程',
              'XF': 2,
              'XFJD': 0,
              'ZCJ': 0,
              'XNXQDM': '2026-2027-1',
              'XNXQDM_DISPLAY': '测试学期',
            },
          ],
        },
      );
      final state = AppState(teachingSession: session)
        ..connectedAt = DateTime(2026);
      await tester.pumpWidget(
        MaterialApp(
          home: AcademicPage(state: state, feature: AcademicFeature.grades),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试课程'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('绩点 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('late response from previous account is discarded', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final state = AppState(
      teachingSession: FakeSession((_, _) => pending.future),
    )..connectedAt = DateTime(2026);
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicPage(state: state, feature: AcademicFeature.grades),
      ),
    );
    await tester.pump();
    await state.clearSchedule();
    pending.complete({
      'ok': true,
      'rows': [
        {'KCM': '旧账号课程'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('旧账号课程'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  test(
    'room blocks distinguish all free, occupied, mixed and missing periods',
    () {
      final slot = RoomSlot.fromJson({'start': 1, 'end': 2, 'label': '1-2节'});
      RoomUse status(List<String> values) => RoomAvailability.fromJson({
        'name': '测试101',
        'periods': [
          for (var i = 0; i < values.length; i++)
            {'period': i + 1, 'state': values[i]},
        ],
      }).stateFor(slot);
      expect(status(['free', 'free']), RoomUse.free);
      expect(status(['busy', 'busy']), RoomUse.busy);
      expect(status(['free', 'busy']), RoomUse.partial);
      expect(status(['free']), RoomUse.unknown);
      expect(status(['free', 'unknown']), RoomUse.unknown);
    },
  );
  testWidgets(
    'building selection automatically loads full-day grid on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = FakeSession((task, args) async {
        if (task == 'roomsOptions') {
          return {
            'ok': true,
            'buildings': [
              {
                'JXLDM': 'test-building',
                'JXLMC': '测试楼',
                'XXXQDM_DISPLAY': '测试校区',
              },
            ],
          };
        }
        expect(args['params']['building'], 'test-building');
        expect(args['params'].containsKey('start'), isFalse);
        return {
          'ok': true,
          'slots': [
            {'start': 1, 'end': 2, 'label': '1-2节'},
          ],
          'rows': [
            {
              'name': '测试101',
              'seats': 60,
              'periods': [
                {'period': 1, 'state': 'free'},
                {
                  'period': 2,
                  'state': 'busy',
                  'types': ['01'],
                },
              ],
            },
          ],
        };
      });
      final state = AppState(teachingSession: session)
        ..connectedAt = DateTime(2026);
      await tester.pumpWidget(
        MaterialApp(home: RoomAvailabilityPage(state: state)),
      );
      await tester.pumpAndSettle();
      expect(session.calls, ['roomsOptions']);
      expect(find.text('请选择教学楼'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试楼 · 测试校区').last);
      await tester.pumpAndSettle();
      expect(session.calls, ['roomsOptions', 'rooms']);
      expect(find.text('测试101'), findsOneWidget);
      expect(find.text('半'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('测试101'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('测试101 · 1-2节 · 部分空闲'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 节 · 空闲'), findsOneWidget);
      expect(find.text('第 2 节 · 占用'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
