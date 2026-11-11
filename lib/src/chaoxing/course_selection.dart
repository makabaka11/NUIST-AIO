import 'dart:convert';

import 'current_term.dart';

String chaoxingCourseKey(Map<String, dynamic> course) =>
    '${course['courseId']}:${course['classId']}';

class ChaoxingCourseOption {
  const ChaoxingCourseOption({
    required this.key,
    required this.name,
    required this.alias,
    required this.teacher,
    required this.referenceTeachers,
    required this.automatic,
  });
  final String key, name, alias, teacher, referenceTeachers;
  final bool automatic;
}

/// Contains display data only; never course entry encodings or cookies.
class ChaoxingCourseSelection {
  ChaoxingCourseSelection(
    ChaoxingTermScope scope,
    List<Map<String, dynamic>> raw,
  ) : term = scope.term,
      teaching = {
        for (final c in scope.courses)
          '${ChaoxingTermScope.normalize(c.name)}|${ChaoxingTermScope.normalize(c.teacher)}':
              c,
      }.values.toList(),
      options = raw
          .where(
            (c) => ![c['title'], c['alias'] ?? ''].any(
              (name) =>
                  ChaoxingTermScope.normalize(name as String).contains('选课指导'),
            ),
          )
          .map((c) {
            final name = c['title'] as String;
            final references = scope.courses.where(
              (t) =>
                  ChaoxingTermScope.weakMatch(name, t.name) ||
                  (ChaoxingTermScope.normalize(t.name).length >= 4 &&
                      ChaoxingTermScope.normalize(c['alias'] as String? ?? '')
                          .contains(ChaoxingTermScope.normalize(t.name))),
            );
            return ChaoxingCourseOption(
              key: chaoxingCourseKey(c),
              name: name,
              alias: c['alias'] as String? ?? '',
              teacher: c['teacher'] as String? ?? '',
              referenceTeachers: references
                  .map((t) => t.teacher.trim())
                  .where((t) => t.isNotEmpty)
                  .toSet()
                  .join('、'),
              automatic: scope.includes(c),
            );
          })
          .toList();

  final String term;
  final List<({String name, String teacher})> teaching;
  final List<ChaoxingCourseOption> options;
  Set<String> get automatic =>
      options.where((c) => c.automatic).map((c) => c.key).toSet();
  Set<String> get keys => options.map((c) => c.key).toSet();

  // Stable against server ordering; changes to either roster require review.
  String get fingerprint {
    final left = teaching.map((t) => jsonEncode([t.name, t.teacher])).toList()
      ..sort();
    final right =
        options
            .map(
              (c) =>
                  jsonEncode([c.key, c.name, c.alias, c.teacher, c.automatic]),
            )
            .toList()
          ..sort();
    return jsonEncode([term, left, right]);
  }
}
