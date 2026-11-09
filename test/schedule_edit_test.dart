import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/schedule/schedule.dart';
import 'package:nuist_aio/src/schedule/json_import.dart';
import 'package:nuist_aio/src/schedule/course_editor.dart';
import 'package:nuist_aio/src/schedule/schedule_widgets.dart';
import 'package:nuist_aio/src/schedule/week_schedule.dart';

import 'schedule_test.dart' show fixture, row;

Map<String, dynamic> exportCourse(String room, List<int> weeks) => {
  'name': '实验课程',
  'teacher': '教师甲',
  'classroom': room,
  'dayOfWeek': 1,
  'startSection': 5,
  'endSection': 6,
  'isCustomTime': false,
  'selectedWeeks': weeks,
  'startWeek': 1,
  'endWeek': 20,
  'weekType': 0,
  'colorRes': 0xff4488cc,
};
Map<String, dynamic> exported() => {
  'schedule_name': '测试课表',
  'settings': {'class_start_time': '2026/08/31', 'total_weeks': 20},
  'courses': [
    exportCourse('实验室A', [2, 3, 4]),
    exportCourse('实验室B', [5, 6, 7]),
    exportCourse('实验室C', [8, 9, 10]),
    exportCourse('实验室A', [11, 12, 13]),
    exportCourse('实验室D', [14, 15, 16, 17]),
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'JSON import preserves every location transition and exact eleven periods',
    () {
      final s = ScheduleJsonImport.parse(exported());
      expect(s.courses.length, 4);
      expect(s.slots.length, 11);
      expect(s.timeFor(11, end: true), '21:20');
      for (final pair in [
        (2, '实验室A'),
        (5, '实验室B'),
        (8, '实验室C'),
        (11, '实验室A'),
        (14, '实验室D'),
      ]) {
        expect(
          s
              .onDate(
                DateTime(2026, 8, 31).add(Duration(days: (pair.$1 - 1) * 7)),
              )
              .single
              .location,
          pair.$2,
        );
      }
      expect(
        Schedule.fromJson(s.toJson()).courses.first.colorValue,
        0xff4488cc,
      );
    },
  );
  test('empty selected weeks uses the explicit normal week range without dropping personal events', () {
    final raw = exported()..['courses'] = [exportCourse('地点', [])];
    expect(ScheduleJsonImport.parse(raw).courses.single.weeks.length, 20);
  });
  test('API integral doubles and legacy numeric cache no longer discard courses; API slots cannot override user times', () {
    final r = row()
      ..['SKXQ'] = 1.0
      ..['KSJC'] = 5.0
      ..['JSJC'] = 6.0;
    final raw = fixture([r])
      ..['slots'] = [
        {'DM': 1, 'KSSJ': '09:00', 'JSSJ': '09:50'},
        {'DM': 12, 'KSSJ': '22:00', 'JSSJ': '22:45'},
      ];
    final s = ScheduleParser.parse(raw);
    expect(s.courses.length, 1);
    expect(s.slots.length, 11);
    expect(s.timeFor(1), '08:00');
    final json = s.toJson();
    (json['courses'] as List).first['day'] = 1.0;
    expect(Schedule.fromJson(json).courses.single.day, 1);
  });
  test('invalid nonempty API data cannot overwrite an existing timetable as an empty success', () {
    expect(
      () => ScheduleParser.parse(fixture([row(mask: 'invalid')])),
      throwsFormatException,
    );
  });
  test('editing/deleting one arrangement keeps same-name courses at other locations and weeks', () {
    final s = ScheduleJsonImport.parse(exported()),
        original = ScheduleJsonImport.parse(exported()).courses.first;
    final replacement = Course(
      name: original.name,
      teacher: original.teacher,
      location: '编辑地点',
      day: original.day,
      start: original.start,
      end: original.end,
      weeks: original.weeks,
      colorValue: 0xffff8800,
    );
    final edited = s.replaceCourse(original, replacement);
    expect(edited.localEdits, isTrue);
    expect(edited.courses.any((c) => c.location == '实验室B'), isTrue);
    expect(
      edited.replaceCourse(replacement, null).courses.length,
      s.courses.length - 1,
    );
  });
  test('legacy cache with dropped rows is re-fetched and repair notice clears after saving', () async {
    final broken = ScheduleParser.parse(fixture([])).toJson()
      ..['warnings'] = ['39 条排课记录缺少有效的时间或周次，未放入日程。'];
    await const FlutterSecureStorage().write(
      key: 'nuist.schedule.v1',
      value: jsonEncode(broken),
    );
    final state = AppState();
    await state.load();
    expect(state.schedule, isNull);
    expect(state.startupNotice, contains('旧版课表'));
    await state.saveSchedule(
      ScheduleParser.parse(fixture([row()])),
      generation: state.sessionGeneration,
    );
    expect(state.schedule!.courses.length, 1);
    expect(state.startupNotice, isNull);
    state.dispose();
  });
  testWidgets('editor persists fields and course color in encrypted schedule', (
    tester,
  ) async {
    final state = AppState();
    await state.load();
    final s = ScheduleJsonImport.parse(exported());
    await state.saveSchedule(s, generation: state.sessionGeneration);
    await tester.pumpWidget(
      MaterialApp(
        home: CourseEditorPage(
          state: state,
          course: s.courses.first,
          schedule: s,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), '新实验室');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    final restored = AppState();
    await restored.load();
    expect(restored.schedule!.courses.any((c) => c.location == '新实验室'), isTrue);
    expect(restored.schedule!.courses.any((c) => c.location == '实验室B'), isTrue);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    restored.dispose();
  });
  testWidgets('delete action only removes selected schedule fragment', (
    tester,
  ) async {
    final state = AppState();
    await state.load();
    final s = ScheduleJsonImport.parse(exported());
    await state.saveSchedule(s, generation: state.sessionGeneration);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showCourseDetails(context, s.courses.first, s, state: state),
              child: const Text('课程'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('课程'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除本机安排'));
    await tester.tap(find.text('删除本机安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(state.schedule!.courses.length, s.courses.length - 1);
    expect(state.schedule!.courses.any((c) => c.location == '实验室B'), isTrue);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
    'week table changes classroom by week and contains only eleven rows',
    (tester) async {
      final state = AppState();
      await state.load();
      final s = ScheduleJsonImport.parse(exported());
      await state.saveSchedule(s, generation: state.sessionGeneration);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: WeekSchedule(state: state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('第 5 周'),
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('第 5 周').last);
      await tester.pumpAndSettle();
      expect(find.text('实验室B'), findsOneWidget);
      expect(find.text('实验室C'), findsNothing);
      expect(find.text('22:00'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
