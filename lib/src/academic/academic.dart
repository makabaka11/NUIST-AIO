import '../services/site_registry.dart';

enum AcademicFeature {
  rooms('rooms', '空闲教室'),
  credits('credits', '学业监测'),
  exams('exams', '考试安排'),
  grades('grades', '成绩查询');

  const AcademicFeature(this.id, this.label);
  final String id, label;
  Uri get entry => Uri.parse(
    SchoolSites.get(SchoolSiteId.teaching).features
        .singleWhere((f) => f.id == id)
        .entry!,
  );
}

String academicText(Map<String, dynamic> row, String field) =>
    row[field]?.toString().trim() ?? '';

/// School exam times are in China Standard Time, independent of device zone.
bool? examCompleted(Map<String, dynamic> row, DateTime now) {
  final date = academicText(row, 'KSRQ');
  var end = academicText(row, 'KSJSSJ');
  if (end.isEmpty) {
    final times = RegExp(r'\d{1,2}:\d{2}(?::\d{2})?')
        .allMatches(academicText(row, 'KSSJMS'))
        .toList();
    if (times.length == 2) end = times.last.group(0)!;
  }
  if (RegExp(r'^\d{1,2}:\d{2}(?::\d{2})?$').hasMatch(end)) {
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(date)?.group(0);
    if (day == null) return null;
    end = '${day}T${end.padLeft(5, '0')}';
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}').hasMatch(end)) return null;
  if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(end)) end = '$end+08:00';
  final time = DateTime.tryParse(end);
  return time == null ? null : !time.isAfter(now);
}

/// Includes genuine zero scores/GPA; never treats missing values as zero.
double? academicNumber(Object? value) {
  final n = value == null ? null : double.tryParse('$value');
  return n != null && n.isFinite ? n : null;
}

String creditNumber(Object? value) {
  final n = academicNumber(value);
  if (n == null) return '—';
  if (n == n.roundToDouble()) return n.toStringAsFixed(0);
  return n.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

Uri get gradeAnalysisEntry => Uri.parse(
  SchoolSites.get(SchoolSiteId.teaching).features
      .singleWhere((feature) => feature.id == 'gradeAnalysis')
      .entry!,
);

/// Keep the official GPA precision (e.g. three decimal places), including zero.
String gpaNumber(Object? value) {
  if (value is! String && value is! num) return '—';
  final text = '$value'.trim();
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(text) ||
      academicNumber(text) == null) {
    return '—';
  }
  return value is String
      ? text
      : text.endsWith('.0')
      ? text.substring(0, text.length - 2)
      : text;
}
