import 'holiday_source.dart';

class SchoolHoliday {
  const SchoolHoliday(
    this.name,
    this.start,
    this.end, {
    this.declaredBreak = true,
    this.supplemental = false,
  });
  final String name;
  final DateTime start, end;

  /// True for explicit rest dates from the school or public supplement. A named
  /// festival alone supplies its date without an inferred leave schedule.
  final bool declaredBreak;
  final bool supplemental;
  int daysFrom(DateTime today) => start
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays
      .clamp(0, 10000);
  bool active(DateTime today) =>
      !DateTime.utc(today.year, today.month, today.day).isBefore(start) &&
      !DateTime.utc(today.year, today.month, today.day).isAfter(end);
  static final _names = RegExp('元旦节?|春节|清明节?|劳动节|端午节?|中秋节?|国庆节?');
  static bool _makeup(String text) => RegExp('补课|补班|上课|工作日').hasMatch(text);
  static bool _rest(String text) =>
      !_makeup(text) && RegExp('休|放假|假期').hasMatch(text);
  static SchoolHoliday? next(
    Map<String, dynamic> calendar,
    DateTime today, {
    List<PublicHolidayDay> supplement = const [],
  }) {
    final dates = <DateTime, ({String event, String lunar})>{};
    for (final term in calendar['terms'] as List) {
      for (final week in term['weeks'] as List) {
        for (final day in week['days'] as List) {
          if (day == null) continue;
          final date = DateTime.tryParse('${day['date']}T00:00:00Z');
          if (date == null ||
              date.toIso8601String().substring(0, 10) != day['date']) {
            continue;
          }
          dates[date] = (
            event: day['event'] as String? ?? '',
            lunar: day['lunar'] as String? ?? '',
          );
        }
      }
    }
    final supplementalDates = <DateTime>{};
    for (final day in supplement) {
      final date = DateTime.parse('${day.date}T00:00:00Z');
      final school = dates[date];
      // A nonempty school event is authoritative, including makeup classes.
      if (school != null && school.event.trim().isNotEmpty) continue;
      dates[date] = (
        event: day.holiday ? '${day.name} 放假' : '补班',
        lunar: school?.lunar ?? '',
      );
      if (day.holiday) supplementalDates.add(date);
    }
    bool holidayDate(DateTime date) {
      final value = dates[date];
      return value != null &&
          !_makeup(value.event) &&
          (_rest(value.event) ||
              _names.hasMatch('${value.event} ${value.lunar}'));
    }

    final groups = <String, SchoolHoliday>{};
    for (final entry in dates.entries) {
      if (_makeup(entry.value.event)) continue;
      final names = _names
          .allMatches('${entry.value.event} ${entry.value.lunar}')
          .map((m) {
            final name = m[0]!.replaceAll('元旦节', '元旦');
            return name == '元旦' || name == '春节' || name.endsWith('节')
                ? name
                : '$name节';
          })
          .toSet();
      if (names.isEmpty) continue;
      var start = entry.key, end = entry.key;
      for (
        var n = 0;
        n < 13 && holidayDate(start.subtract(const Duration(days: 1)));
        n++
      ) {
        start = start.subtract(const Duration(days: 1));
      }
      for (
        var n = 0;
        n < 13 && holidayDate(end.add(const Duration(days: 1)));
        n++
      ) {
        end = end.add(const Duration(days: 1));
      }
      final marked = dates.entries.any(
        (d) =>
            !d.key.isBefore(start) &&
            !d.key.isAfter(end) &&
            _rest(d.value.event),
      );
      final key = '${start.toIso8601String()}/${end.toIso8601String()}';
      final previous = groups[key];
      if (previous != null) names.addAll(previous.name.split(' · '));
      groups[key] = SchoolHoliday(
        names.join(' · '),
        start,
        end,
        declaredBreak: marked,
        supplemental: supplementalDates.any(
          (d) => !d.isBefore(start) && !d.isAfter(end),
        ),
      );
    }
    final day = DateTime.utc(today.year, today.month, today.day);
    final upcoming = groups.values.where((h) => !h.end.isBefore(day)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return upcoming.isEmpty ? null : upcoming.first;
  }
}
