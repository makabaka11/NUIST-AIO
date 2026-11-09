import 'dart:convert';

int? _integer(dynamic value) {
  final n = value is num ? value : num.tryParse('$value');
  return n != null && n.isFinite && n == n.roundToDouble() ? n.toInt() : null;
}

String _text(dynamic value) => value?.toString().trim() ?? '';
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime mondayOf(DateTime date) =>
    dateOnly(date).subtract(Duration(days: date.weekday - 1));
int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

class Course {
  const Course({
    required this.name,
    required this.teacher,
    required this.location,
    required this.day,
    required this.start,
    required this.end,
    required this.weeks,
    this.colorValue,
  });
  final String name, teacher, location;
  final int day, start, end;
  final List<int> weeks;
  final int? colorValue;
  String get key => jsonEncode([name, teacher, location, day, start, end]);
  Map<String, dynamic> toJson() => {
    'name': name,
    'teacher': teacher,
    'location': location,
    'day': day,
    'start': start,
    'end': end,
    'weeks': weeks,
    'colorValue': colorValue,
  };
  factory Course.fromJson(Map<String, dynamic> j) => Course(
    name: j['name'],
    teacher: j['teacher'],
    location: j['location'],
    day: _integer(j['day'])!,
    start: _integer(j['start'])!,
    end: _integer(j['end'])!,
    weeks: (j['weeks'] as List).map((x) => _integer(x)!).toList(),
    colorValue: _integer(j['colorValue']),
  );
}

class UnscheduledCourse {
  const UnscheduledCourse(this.name, this.teacher);
  final String name, teacher;
  Map<String, dynamic> toJson() => {'name': name, 'teacher': teacher};
}

class TimeSlot {
  const TimeSlot(this.number, this.start, this.end);
  final int number;
  final String start, end;
  Map<String, dynamic> toJson() => {
    'number': number,
    'start': start,
    'end': end,
  };
  static bool validTime(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
}

class Semester {
  const Semester(this.code, this.name);
  final String code, name;
  factory Semester.fromJson(Map<String, dynamic> j) =>
      Semester(_text(j['DM']), _text(j['MC']));
}

class Schedule {
  const Schedule({
    required this.term,
    required this.termName,
    required this.startDate,
    required this.totalWeeks,
    required this.courses,
    required this.unscheduled,
    required this.slots,
    required this.updatedAt,
    this.warnings = const [],
    this.localEdits = false,
  });
  final String term, termName;
  final DateTime? startDate;
  final int totalWeeks;
  final List<Course> courses;
  final List<UnscheduledCourse> unscheduled;
  final List<TimeSlot> slots;
  final DateTime updatedAt;
  final List<String> warnings;
  final bool localEdits;

  int? weekAt(DateTime date) {
    if (startDate == null) {
      return null;
    }
    return ((_dayNumber(date) - _dayNumber(mondayOf(startDate!))) / 7).floor() +
        1;
  }

  List<Course> onDate(DateTime date) {
    final week = weekAt(date);
    if (week == null || week < 1 || week > totalWeeks) {
      return [];
    }
    return courses
        .where((c) => c.day == date.weekday && c.weeks.contains(week))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  String timeFor(int section, {bool end = false}) {
    for (final slot in slots) {
      if (slot.number == section) {
        return end ? slot.end : slot.start;
      }
    }
    return '第$section节';
  }

  Schedule withStart(DateTime date) => Schedule(
    term: term,
    termName: termName,
    startDate: dateOnly(date),
    totalWeeks: totalWeeks,
    courses: courses,
    unscheduled: unscheduled,
    slots: slots,
    updatedAt: updatedAt,
    localEdits: true,
    warnings: warnings.where((w) => !w.contains('开学日期')).toList(),
  );
  Schedule withCourses(List<Course> next) => Schedule(
    term: term,
    termName: termName,
    startDate: startDate,
    totalWeeks: totalWeeks,
    courses: next,
    unscheduled: unscheduled,
    slots: ScheduleParser.defaultSlots,
    updatedAt: DateTime.now(),
    warnings: warnings,
    localEdits: true,
  );
  Schedule replaceCourse(Course original, Course? replacement) {
    final next = [...courses];
    final index = next.indexWhere(
      (c) =>
          c.key == original.key &&
          jsonEncode(c.weeks) == jsonEncode(original.weeks),
    );
    if (index < 0) throw const FormatException('课表已变化，请重新打开课程。');
    if (replacement == null) {
      next.removeAt(index);
    } else {
      next[index] = replacement;
    }
    return withCourses(next);
  }

  Map<String, dynamic> toJson() => {
    'term': term,
    'termName': termName,
    'startDate': startDate?.toIso8601String(),
    'totalWeeks': totalWeeks,
    'courses': courses.map((c) => c.toJson()).toList(),
    'unscheduled': unscheduled.map((c) => c.toJson()).toList(),
    'slots': slots.map((s) => s.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'warnings': warnings,
    'localEdits': localEdits,
  };
  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
    term: j['term'],
    termName: j['termName'],
    startDate: DateTime.tryParse(j['startDate'] ?? ''),
    totalWeeks: _integer(j['totalWeeks'])!,
    courses: (j['courses'] as List)
        .map((c) => Course.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
    unscheduled: (j['unscheduled'] as List)
        .map((c) => UnscheduledCourse(c['name'], c['teacher']))
        .toList(),
    slots: ScheduleParser.defaultSlots,
    updatedAt: DateTime.parse(j['updatedAt']),
    warnings: List<String>.from(j['warnings'] ?? []),
    localEdits: j['localEdits'] == true,
  );
}

/// Field contract verified against NUIST's JSON API. See docs/schedule-integration.md.
class ScheduleParser {
  static const defaultSlots = [
    TimeSlot(1, '08:00', '08:45'),
    TimeSlot(2, '08:55', '09:40'),
    TimeSlot(3, '10:10', '10:55'),
    TimeSlot(4, '11:05', '11:50'),
    TimeSlot(5, '13:45', '14:30'),
    TimeSlot(6, '14:40', '15:25'),
    TimeSlot(7, '15:55', '16:40'),
    TimeSlot(8, '16:50', '17:35'),
    TimeSlot(9, '18:45', '19:30'),
    TimeSlot(10, '19:40', '20:25'),
    TimeSlot(11, '20:35', '21:20'),
  ];
  static Schedule parse(Map<String, dynamic> data) {
    final term = _text(data['term']);
    if (!RegExp(r'^\d{4}-\d{4}-[123]$').hasMatch(term) ||
        data['rows'] is! List) {
      throw const FormatException('课表数据格式不正确，请重新获取。');
    }
    final warnings = List<String>.from(data['warnings'] ?? []);
    final merged = <String, Course>{};
    int skipped = 0;
    for (final raw in data['rows']) {
      final r = Map<String, dynamic>.from(raw as Map);
      final day = _integer(r['SKXQ']),
          start = _integer(r['KSJC']),
          end = _integer(r['JSJC']);
      final mask = _text(r['SKZC']), name = _text(r['KCM']);
      if (name.isEmpty ||
          day == null ||
          day < 1 ||
          day > 7 ||
          start == null ||
          end == null ||
          start < 1 ||
          end > 11 ||
          start > end ||
          !RegExp(r'^[01]+$').hasMatch(mask) ||
          !mask.contains('1')) {
        skipped++;
        continue;
      }
      final weeks = [
        for (int i = 0; i < mask.length; i++)
          if (mask[i] == '1') i + 1,
      ];
      final room = _text(r['JASMC']), campus = _text(r['XXXQDM_DISPLAY']);
      final location = room.isEmpty
          ? (campus.isEmpty ? '地点待定' : campus)
          : (campus.isEmpty ? room : '$room（$campus）');
      final c = Course(
        name: name,
        teacher: _text(r['SKJS']),
        location: location,
        day: day,
        start: start,
        end: end,
        weeks: weeks,
      );
      final old = merged[c.key];
      merged[c.key] = old == null
          ? c
          : Course(
              name: c.name,
              teacher: c.teacher,
              location: c.location,
              day: c.day,
              start: c.start,
              end: c.end,
              weeks: ({...old.weeks, ...weeks}.toList()..sort()),
            );
    }
    if ((data['rows'] as List).isNotEmpty && merged.isEmpty) {
      throw const FormatException('教务排课未能完整识别，未覆盖旧课表；请重新获取或导入已有 JSON。');
    }
    if (skipped > 0) {
      warnings.add('$skipped 条排课记录缺少有效的时间或周次，未放入日程。');
    }
    final rawDate = _text((data['config'] as Map?)?['XQKSRQ']);
    final date = DateTime.tryParse(rawDate.split(' ').first);
    if (date == null) {
      warnings.add('未获取到开学日期，请设置后查看每日课程。');
    }
    final total = _integer((data['config'] as Map?)?['ZZC']);
    // User-supplied 4+4+3 daily timetable is authoritative for all imports.
    if ((data['slots'] as List? ?? []).isEmpty) {
      warnings.add('作息使用用户指定的 11 节默认作息。');
    }
    final unplaced = <String, UnscheduledCourse>{};
    for (final raw in (data['unscheduled'] as List? ?? [])) {
      final name = _text(raw['KCM']);
      if (name.isNotEmpty && !merged.values.any((c) => c.name == name)) {
        final c = UnscheduledCourse(name, _text(raw['SKJS']));
        unplaced[jsonEncode(c.toJson())] = c;
      }
    }
    final courses = merged.values.toList()
      ..sort(
        (a, b) => a.day == b.day
            ? a.start.compareTo(b.start)
            : a.day.compareTo(b.day),
      );
    return Schedule(
      term: term,
      termName: _text(data['termName']).isEmpty
          ? term
          : _text(data['termName']),
      startDate: date == null ? null : dateOnly(date),
      totalWeeks: total != null && total > 0 ? total : 20,
      courses: courses,
      unscheduled: unplaced.values.toList(),
      slots: defaultSlots,
      updatedAt: DateTime.now(),
      warnings: warnings,
    );
  }
}
