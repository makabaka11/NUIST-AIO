import 'schedule.dart';

/// Supported export format supplied by the user. Never evaluate file content.
class ScheduleJsonImport {
  static Schedule parse(Map<String, dynamic> json) {
    final settings = Map<String, dynamic>.from(json['settings'] as Map? ?? {});
    final total = (settings['total_weeks'] as num?)?.toInt() ?? 20;
    if (total < 1 || total > 60 || json['courses'] is! List) {
      throw const FormatException('课表文件格式不正确。');
    }
    final reorganization = settings['teaching_week_reorganizations'];
    if (reorganization is Map &&
        (reorganization['rules'] as List? ?? []).isNotEmpty) {
      throw const FormatException('此文件含调休规则，当前尚不支持导入，请先移除规则或使用教务获取。');
    }
    final date = DateTime.tryParse(
      '${settings['class_start_time']}'.replaceAll('/', '-'),
    );
    if (date == null) throw const FormatException('课表缺少有效开学日期。');
    final merged = <String, Course>{};
    for (final raw in json['courses']) {
      final r = Map<String, dynamic>.from(raw as Map);
      if (r['isCustomTime'] == true) {
        throw const FormatException('暂不支持自定义时刻，请把课程转换为节次后导入。');
      }
      final name = '${r['name'] ?? ''}'.trim();
      final day = (r['dayOfWeek'] as num?)?.toInt(),
          start = (r['startSection'] as num?)?.toInt(),
          end = (r['endSection'] as num?)?.toInt();
      if (name.isEmpty ||
          day == null ||
          day < 1 ||
          day > 7 ||
          start == null ||
          end == null ||
          start < 1 ||
          end > 11 ||
          start > end) {
        throw const FormatException('文件含无效的课程名称、星期或节次。');
      }
      var weeks =
          (r['selectedWeeks'] as List? ?? [])
              .map((x) => (x as num).toInt())
              .toSet()
              .toList()
            ..sort();
      if (weeks.isEmpty) {
        if ((r['weekType'] ?? 0) != 0) {
          throw const FormatException('此文件的单双周编码尚未确认，请先改用明确的上课周次后导入。');
        }
        final from = (r['startWeek'] as num?)?.toInt() ?? 1,
            to = (r['endWeek'] as num?)?.toInt() ?? total;
        weeks = [for (var w = from; w <= to; w++) w];
      }
      if (weeks.isEmpty || weeks.any((w) => w < 1 || w > total)) {
        throw const FormatException('课程周次超出学期范围。');
      }
      final c = Course(
        name: name,
        teacher: '${r['teacher'] ?? ''}',
        location: '${r['classroom'] ?? ''}',
        day: day,
        start: start,
        end: end,
        weeks: weeks,
        colorValue: (r['colorRes'] as num?)?.toInt(),
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
              colorValue: c.colorValue,
            );
    }
    return Schedule(
      term: 'local',
      termName: '${json['schedule_name'] ?? '导入课表'}',
      startDate: date,
      totalWeeks: total,
      courses: merged.values.toList(),
      unscheduled: const [],
      slots: ScheduleParser.defaultSlots,
      updatedAt: DateTime.now(),
      localEdits: true,
    );
  }
}
