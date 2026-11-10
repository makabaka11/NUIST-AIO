import '../schedule/schedule.dart';

/// Teaching's server-selected current term, never inferred from device date or
/// the timetable currently selected for viewing/importing in the UI.
class ChaoxingTermScope {
  ChaoxingTermScope(this.schedule);
  factory ChaoxingTermScope.fromData(Map<String, dynamic> data) {
    final term = data['term'];
    if (term is! String ||
        !RegExp(r'^\d{4}-\d{4}-[123]$').hasMatch(term) ||
        data['rows'] is! List ||
        (data['unscheduled'] != null && data['unscheduled'] is! List)) {
      throw const FormatException('本学期课程名单格式不完整。');
    }
    final courses = <UnscheduledCourse>[];
    for (final row in [
      ...data['rows'] as List,
      ...?data['unscheduled'] as List?,
    ]) {
      if (row is! Map ||
          row['KCM'] is! String ||
          (row['KCM'] as String).trim().isEmpty) {
        throw const FormatException('本学期课程名单缺少课程名称。');
      }
      courses.add(
        UnscheduledCourse(
          (row['KCM'] as String).trim(),
          row['SKJS']?.toString() ?? '',
        ),
      );
    }
    return ChaoxingTermScope(
      Schedule(
        term: term,
        termName: data['termName']?.toString() ?? term,
        startDate: null,
        totalWeeks: 0,
        courses: const [],
        unscheduled: courses,
        slots: const [],
        updatedAt: DateTime.now(),
      ),
    );
  }
  final Schedule schedule;
  String get term => schedule.term;
  List<({String name, String teacher})> get courses => [
    ...schedule.courses.map((c) => (name: c.name, teacher: c.teacher)),
    ...schedule.unscheduled.map((c) => (name: c.name, teacher: c.teacher)),
  ];
  static String normalize(String value) {
    var text = String.fromCharCodes(
      value.runes.map((c) => c >= 0xff01 && c <= 0xff5e ? c - 0xfee0 : c),
    );
    for (final entry in {
      'Ⅰ': 'I',
      'Ⅱ': 'II',
      'Ⅲ': 'III',
      'Ⅳ': 'IV',
      'Ⅴ': 'V',
      'Ⅵ': 'VI',
      'Ⅶ': 'VII',
      'Ⅷ': 'VIII',
      'Ⅸ': 'IX',
      'Ⅹ': 'X',
    }.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.toUpperCase().replaceAll(
      RegExp(r'''[\s\u3000·・,，。、;；:：!！?？'"“”‘’()（）\[\]【】<>《》/\\|+*#\-]'''),
      '',
    );
  }

  static String? explicitTerm(String text) {
    final m = RegExp(
      r'(?:^|[^\d])((?:20)?\d{2})\s*[-–—]\s*((?:20)?\d{2})\s*(?:[-–—]\s*|学年\s*第?\s*)([12一二])(?:学期)?(?!\d)',
    ).firstMatch(text);
    if (m == null) return null;
    final first = int.parse(m[1]!), second = int.parse(m[2]!);
    final y1 = first < 100 ? 2000 + first : first,
        y2 = second < 100 ? 2000 + second : second;
    if (y2 != y1 + 1) return null;
    final part = {'一': '1', '二': '2'}[m[3]] ?? m[3]!;
    return '$y1-$y2-$part';
  }

  static bool weakMatch(String left, String right) {
    // Remove descriptive bracket qualifiers, then compare names loosely. Keep
    // explicit course sequence numbers distinct (English I is not English II).
    String base(String s) =>
        normalize(s.replaceAll(RegExp(r'[（(][^）)]*[）)]'), ' '));
    final originalLeft = normalize(left), originalRight = normalize(right);
    String? ordinal(String s) {
      final m = RegExp(r'(VIII|VII|III|VI|IV|IX|II|V|X|I|[1-9一二三四五六上下])$')
          .firstMatch(s);
      if (m == null) return null;
      return {
            'I': '1',
            'II': '2',
            'III': '3',
            'IV': '4',
            'V': '5',
            'VI': '6',
            'VII': '7',
            'VIII': '8',
            'IX': '9',
            'X': '10',
            '一': '1',
            '二': '2',
            '三': '3',
            '四': '4',
            '五': '5',
            '六': '6',
            '上': '1',
            '下': '2',
          }[m[1]] ??
          m[1];
    }

    final aOrdinal = ordinal(originalLeft), bOrdinal = ordinal(originalRight);
    if (aOrdinal != null && bOrdinal != null && aOrdinal != bOrdinal) {
      return false;
    }
    if (originalLeft == originalRight) return true;
    final a = base(left), b = base(right);
    if (a.length < 2 || b.length < 2) return false;
    if (a == b) return true;
    if (a.length >= 3 && b.length >= 3 && (a.contains(b) || b.contains(a))) {
      return true;
    }
    var prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }
    final longer = a.length > b.length ? a.length : b.length;
    return prefix >= 4 && prefix / longer >= .5;
  }

  bool includes(Map<String, dynamic> course) {
    final title = course['title'] as String,
        alias = course['alias'] as String? ?? '';
    if ([title, alias].any((name) => normalize(name).contains('选课指导'))) {
      return false;
    }
    for (final text in [title, alias]) {
      final value = explicitTerm(text);
      if (value != null && value != term) return false;
    }
    return courses.any(
      (c) =>
          weakMatch(title, c.name) ||
          (normalize(c.name).length >= 4 &&
              normalize(alias).contains(normalize(c.name))),
    );
  }
}
