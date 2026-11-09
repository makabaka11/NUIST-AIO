import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/schedule/import_page.dart';
import 'package:nuist_aio/src/schedule/schedule.dart';

Map<String, dynamic> row({
  String mask = '1010100000',
  int day = 1,
  int start = 1,
  int end = 2,
  String name = '测试课程',
}) => {
  'KCM': name,
  'SKJS': '教师甲、教师乙',
  'JASMC': '测试教室',
  'XXXQDM_DISPLAY': '本部',
  'SKXQ': day,
  'KSJC': '$start',
  'JSJC': '$end',
  'SKZC': mask,
};
Map<String, dynamic> fixture(List<Map<String, dynamic>> rows) => {
  'term': '2026-2027-1',
  'termName': '2026-2027-1学期',
  'config': {'XQKSRQ': '2026-08-31 00:00:00', 'ZZC': 20},
  'rows': rows,
  'slots': [
    {'DM': 1, 'KSSJ': '08:00', 'JSSJ': '08:45'},
    {'DM': 2, 'KSSJ': '08:55', 'JSSJ': '09:40'},
  ],
  'unscheduled': [
    {'KCM': '时间待定课程', 'SKJS': '教师丙'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('week masks, fragmented records, and all teachers are preserved', () {
    final data = ScheduleParser.parse(
      fixture([
        row(mask: '1010001'),
        row(mask: '0101000'),
        row(mask: '1010001'),
      ]),
    );
    expect(data.courses.length, 1);
    expect(data.courses.single.weeks, [1, 2, 3, 4, 7]);
    expect(data.courses.single.teacher, '教师甲、教师乙');
    expect(data.courses.single.location, '测试教室（本部）');
    expect(data.unscheduled.single.name, '时间待定课程');
  });
  test(
    'odd weeks, Sunday, and teaching boundaries use calendar day arithmetic',
    () {
      final data = ScheduleParser.parse(
        fixture([row(), row(day: 7, name: '周日课程')]),
      );
      expect(data.weekAt(DateTime(2026, 8, 30)), 0);
      expect(data.weekAt(DateTime(2026, 8, 31)), 1);
      expect(data.weekAt(DateTime(2026, 9, 6)), 1);
      expect(data.weekAt(DateTime(2026, 9, 7)), 2);
      expect(data.onDate(DateTime(2026, 9, 7)), isEmpty);
      expect(data.onDate(DateTime(2026, 9, 14)).single.name, '测试课程');
      expect(data.onDate(DateTime(2026, 9, 6)).single.name, '周日课程');
      expect(data.onDate(DateTime(2027, 8, 31)), isEmpty);
      expect(data.timeFor(2, end: true), '09:40');
    },
  );
  test('invalid records are reported and distinct overlapping courses are retained', () {
    final data = ScheduleParser.parse(
      fixture([
        row(),
        row(name: '另一课程'),
        row(day: 0),
        row(start: 3, end: 1),
        row(mask: 'bad'),
      ]),
    );
    expect(data.courses.length, 2);
    expect(data.warnings.join(), contains('3 条排课记录'));
  });
  test('missing metadata never invents a semester start and missing times use labelled defaults', () {
    final raw = fixture([row()])
      ..['config'] = {}
      ..['slots'] = [];
    final data = ScheduleParser.parse(raw);
    expect(data.startDate, isNull);
    expect(data.weekAt(DateTime(2026, 11, 8)), isNull);
    expect(data.warnings.join(), contains('开学日期'));
    expect(data.warnings.join(), contains('默认作息'));
    expect(data.timeFor(1), '08:00');
    expect(
      data.withStart(DateTime(2026, 8, 31)).weekAt(DateTime(2026, 11, 8)),
      10,
    );
  });
  test('a legitimately empty schedule is valid and cache serialization is lossless', () {
    final data = ScheduleParser.parse(fixture([]));
    expect(data.courses, isEmpty);
    expect(Schedule.fromJson(data.toJson()).toJson(), data.toJson());
    expect(
      () => ScheduleParser.parse({'term': 'oops', 'rows': []}),
      throwsFormatException,
    );
  });
  test('encrypted cache restores and clearing prevents old in-flight imports from reappearing', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    final state = AppState();
    await state.load();
    final data = ScheduleParser.parse(fixture([row()]));
    final generation = state.sessionGeneration;
    await state.saveSchedule(data, generation: generation);
    final restored = AppState();
    await restored.load();
    expect(restored.schedule?.courses.single.name, '测试课程');
    await state.clearSchedule();
    await state.saveSchedule(data, generation: generation);
    expect(state.schedule, isNull);
    final cleared = AppState();
    await cleared.load();
    expect(cleared.schedule, isNull);
  });
  test(
    'teaching login allowlist does not expand to other subdomains or HTTP',
    () {
      expect(ScheduleImportPage.allowed(ScheduleImportPage.entry), isTrue);
      for (final s in [
        'http://jwxt.nuist.edu.cn/',
        'https://jwxt.nuist.edu.cn.evil.test/',
        'https://icard.nuist.edu.cn/',
        'https://jwxt.nuist.edu.cn:8443/',
      ]) {
        expect(ScheduleImportPage.allowed(Uri.parse(s)), isFalse);
      }
    },
  );
}
