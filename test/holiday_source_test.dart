import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuist_aio/src/dashboard/holiday.dart';
import 'package:nuist_aio/src/dashboard/holiday_source.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Map<String, dynamic> response(List<Map<String, String>> rows) => {
  'code': 0,
  'data': rows,
};
Map<String, String> row(String date, String type) => {
  'date': date,
  'name': '元旦',
  'type': type,
};
Map<String, dynamic> school(List<Map<String, String>> days) => {
  'terms': [
    {
      'weeks': [
        {'days': days},
      ],
    },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'expired cache survives a service failure without inventing a new year',
    () async {
      final saved = response([row('2026-01-01', 'holiday')]);
      await SharedPreferencesAsync().setString(
        'apisbo_holidays.2026.v1',
        jsonEncode({
          'savedAt': DateTime.now()
              .subtract(const Duration(days: 8))
              .toIso8601String(),
          'response': saved,
        }),
      );
      var attempted = false;
      final repository = PublicHolidayRepository(
        request: (_) async {
          attempted = true;
          throw StateError('offline');
        },
      );
      expect(await repository.load(2026), hasLength(1));
      expect(attempted, isTrue);
      expect(await repository.load(2027), isEmpty);
    },
  );
  test('validates year, real dates, types and duplicate records', () {
    for (final rows in [
      [row('2027-01-01', 'holiday')],
      [row('2026-02-30', 'holiday')],
      [row('2026-01-01', 'unknown')],
      [row('2026-01-01', 'holiday'), row('2026-01-01', 'workday')],
    ]) {
      expect(
        () => PublicHolidayDay.parse(response(rows), 2026),
        throwsFormatException,
      );
    }
  });
  test(
    'public data fills missing dates, excludes workdays and marks its source',
    () {
      final days = PublicHolidayDay.parse(
        response([
          row('2026-01-01', 'holiday'),
          row('2026-01-02', 'holiday'),
          row('2026-01-03', 'workday'),
        ]),
        2026,
      );
      final holiday = SchoolHoliday.next(
        school([]),
        DateTime(2025, 12, 31),
        supplement: days,
      )!;
      expect(holiday.start, DateTime.utc(2026, 1, 1));
      expect(holiday.end, DateTime.utc(2026, 1, 2));
      expect(holiday.supplemental, isTrue);
      expect(
        SchoolHoliday.next(school([]), DateTime(2026, 1, 3), supplement: days),
        isNull,
      );
    },
  );
  test('explicit school makeup day overrides public holiday', () {
    final holiday = SchoolHoliday.next(
      school([
        {'date': '2026-01-01', 'event': '正常上课', 'lunar': '元旦节'},
        {'date': '2026-01-02', 'event': '休', 'lunar': '元旦节'},
      ]),
      DateTime(2025, 12, 31),
      supplement: [
        const PublicHolidayDay('2026-01-01', '元旦', true),
        const PublicHolidayDay('2026-01-02', '元旦', true),
      ],
    )!;
    expect(holiday.start, DateTime.utc(2026, 1, 2));
    expect(holiday.supplemental, isFalse);
  });
  test('successful public year is cached, unsupported next year fails independently', () async {
    var calls = 0;
    final repository = PublicHolidayRepository(
      request: (year) async {
        calls++;
        if (year == 2027) throw StateError('unsupported');
        return response([row('2026-01-01', 'holiday')]);
      },
    );
    expect(await repository.load(2026), hasLength(1));
    expect(await repository.load(2026), hasLength(1));
    expect(calls, 1);
    expect(await repository.load(2027), isEmpty);
    expect(await repository.load(2026), hasLength(1));
  });
}
