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
