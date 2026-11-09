import 'dart:convert';
import 'dart:io';

import 'package:nuist_aio/src/schedule/json_import.dart';
import 'package:nuist_aio/src/schedule/schedule.dart';

void main(List<String> args) {
  final raw =
      jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;
  final schedule = ScheduleJsonImport.parse(raw);
  final expected = <String>{};
  for (final r in raw['courses'] as List) {
    final selected = r['selectedWeeks'] as List;
    final weeks = selected.isNotEmpty
        ? selected
        : [for (var w = r['startWeek'] as int; w <= r['endWeek']; w++) w];
    for (final w in weeks) {
      expected.add(
        jsonEncode([
          r['name'],
          r['teacher'],
          r['classroom'],
          r['dayOfWeek'],
          r['startSection'],
          r['endSection'],
          w,
        ]),
      );
    }
  }
  final actual = <String>{
    for (final c in schedule.courses)
      for (final w in c.weeks)
        jsonEncode([c.name, c.teacher, c.location, c.day, c.start, c.end, w]),
  };
  if (expected.difference(actual).isNotEmpty ||
      actual.difference(expected).isNotEmpty) {
    throw StateError('Occurrence mismatch');
  }
  final times = raw['times'] as Map;
  final reference = [
    for (final part in ['morning', 'afternoon', 'evening'])
      ...(times[part] as Map).values,
  ];
  if (reference.length != 11 || schedule.slots.length != 11) {
    throw StateError('Expected eleven periods');
  }
  for (var i = 0; i < 11; i++) {
    if ('${schedule.slots[i].start}-${schedule.slots[i].end}' != reference[i]) {
      throw StateError('Time mismatch');
    }
  }
  stdout.writeln(
    jsonEncode({
      'sourceRecords': (raw['courses'] as List).length,
      'mergedArrangements': schedule.courses.length,
      'occurrencesMatched': actual.length,
      'periodsMatched': 11,
      'roundTrip':
          jsonEncode(schedule.toJson()) ==
          jsonEncode(Schedule.fromJson(schedule.toJson()).toJson()),
    }),
  );
}
