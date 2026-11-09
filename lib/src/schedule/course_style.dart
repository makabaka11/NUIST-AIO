import 'package:flutter/material.dart';

import 'schedule.dart';

Color courseSeed(Course course) {
  if (course.colorValue != null) return Color(course.colorValue!);
  var hash = 0;
  for (final code in course.name.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.6, 0.48).toColor();
}

ColorScheme courseScheme(BuildContext context, Course course) =>
    ColorScheme.fromSeed(
      seedColor: courseSeed(course),
      brightness: Theme.of(context).brightness,
    );
String weekRanges(List<int> weeks) {
  final sorted = weeks.toSet().toList()..sort();
  final parts = <String>[];
  for (var i = 0; i < sorted.length; i++) {
    final from = sorted[i];
    var end = from;
    while (i + 1 < sorted.length && sorted[i + 1] == end + 1) {
      end = sorted[++i];
    }
    parts.add(from == end ? '$from' : '$from–$end');
  }
  return parts.join('、');
}
