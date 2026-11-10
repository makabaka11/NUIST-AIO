class StudentProfile {
  const StudentProfile({
    required this.name,
    required this.studentNumber,
    this.college = '',
    this.major = '',
    this.grade = '',
    this.className = '',
  });
  final String name, studentNumber, college, major, grade, className;
  factory StudentProfile.fromJson(Map<String, dynamic> data) {
    String text(String key) =>
        data[key] is String ? (data[key] as String).trim() : '';
    final name = text('name'), number = text('studentNumber');
    if (name.isEmpty || number.isEmpty) {
      throw const FormatException('学生基本资料不完整，请重试。');
    }
    return StudentProfile(
      name: name,
      studentNumber: number,
      college: text('college'),
      major: text('major'),
      grade: text('grade'),
      className: text('className'),
    );
  }
  Map<String, dynamic> toJson() => {
    'name': name,
    'studentNumber': studentNumber,
    'college': college,
    'major': major,
    'grade': grade,
    'className': className,
  };
}
