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
