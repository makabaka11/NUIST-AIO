import 'dart:convert';
import 'dart:io';

import 'package:nuist_aio/src/schedule/schedule.dart';

void main(List<String> args) {
  final raw =
      jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;
  final s = ScheduleParser.parse(raw);
  final rawOccurrences = (raw['rows'] as List).fold<int>(
    0,
    (n, r) => n + '${r['SKZC']}'.split('').where((v) => v == '1').length,
  );
  final actual = {
    for (final c in s.courses)
      for (final w in c.weeks)
        jsonEncode([c.name, c.teacher, c.location, c.day, c.start, c.end, w]),
  };
  final expected = <String>{};
  for (final r in raw['rows'] as List) {
    final room = '${r['JASMC'] ?? ''}'.trim(),
        campus = '${r['XXXQDM_DISPLAY'] ?? ''}'.trim();
    final location = room.isEmpty
        ? (campus.isEmpty ? '地点待定' : campus)
        : (campus.isEmpty ? room : '$room（$campus）');
    final mask = '${r['SKZC']}';
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == '1') {
        expected.add(
          jsonEncode([
            '${r['KCM']}'.trim(),
            '${r['SKJS'] ?? ''}'.trim(),
            location,
            num.parse('${r['SKXQ']}').toInt(),
            num.parse('${r['KSJC']}').toInt(),
            num.parse('${r['JSJC']}').toInt(),
            i + 1,
          ]),
        );
      }
    }
  }
  if (expected.difference(actual).isNotEmpty ||
      actual.difference(expected).isNotEmpty) {
    throw StateError('Per-occurrence fields differ');
  }
  if (s.warnings.any((w) => w.contains('条排课记录'))) {
    throw StateError('Dropped a verified API row');
  }
  stdout.writeln(
    jsonEncode({
      'rows': (raw['rows'] as List).length,
      'arrangements': s.courses.length,
      'rawOccurrences': rawOccurrences,
      'uniqueOccurrences': actual.length,
      'dropped': 0,
      'slots': s.slots.length,
    }),
  );
}
