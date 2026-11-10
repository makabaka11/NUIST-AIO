import '../campus_ui.dart';

import '../app_state.dart';
import '../theme_settings.dart';
import 'course_style.dart';
import 'schedule.dart';

class CourseEditorPage extends StatefulWidget {
  const CourseEditorPage({
    super.key,
    required this.state,
    required this.course,
    required this.schedule,
  });
  final AppState state;
  final Course course;
  final Schedule schedule;
  @override
  State<CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<CourseEditorPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.course.name),
      teacher = TextEditingController(text: widget.course.teacher),
      location = TextEditingController(text: widget.course.location),
      weeks = TextEditingController(text: weekRanges(widget.course.weeks));
  late int day = widget.course.day,
      start = widget.course.start,
      end = widget.course.end;
  late Color color = courseSeed(widget.course);
  late final int generation;
  @override
  void initState() {
    super.initState();
    generation = widget.state.sessionGeneration;
  }

  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    teacher.dispose();
    location.dispose();
    weeks.dispose();
    super.dispose();
  }

  List<int>? parseWeeks() {
    final result = <int>{};
    for (final token
        in weeks.text.replaceAll('周', '').split(RegExp(r'[,，、\s]+'))) {
      if (token.isEmpty) continue;
      final p = token.split(RegExp('[-–~至]'));
      final from = int.tryParse(p[0]), to = int.tryParse(p.last);
      if (p.length > 2 ||
          from == null ||
          to == null ||
          from < 1 ||
          to > widget.schedule.totalWeeks ||
          from > to) {
        return null;
      }
      result.addAll([for (var n = from; n <= to; n++) n]);
    }
    return result.isEmpty ? null : (result.toList()..sort());
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (start > end) {
      showCampusSnackBar(context, const SnackBar(content: Text('开始节次不能晚于结束节次。')));
      return;
    }
    setState(() => busy = true);
    await uiAction(context, () async {
      if (widget.state.sessionGeneration != generation ||
          !identical(widget.state.schedule, widget.schedule)) {
        throw const FormatException('课表或账号已变化，请重新打开课程。');
      }
      final c = Course(
        name: name.text.trim(),
        teacher: teacher.text.trim(),
        location: location.text.trim(),
        day: day,
        start: start,
        end: end,
        weeks: parseWeeks()!,
        colorValue: color.toARGB32(),
      );
      await widget.state.saveSchedule(
        widget.schedule.replaceCourse(widget.course, c),
        generation: generation,
      );
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('编辑课程安排'),
      actions: [
        TextButton(onPressed: busy ? null : save, child: const Text('保存')),
      ],
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('只修改这条安排的地点和周次，不影响同名课程在其他地点的安排。更改仅保存在本机，重新获取教务课表会替换本机修改。'),
          const SizedBox(height: 20),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: '课程名称'),
            validator: (v) => v == null || v.trim().isEmpty ? '请输入课程名称' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: teacher,
            decoration: const InputDecoration(labelText: '教师'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: location,
            decoration: const InputDecoration(labelText: '上课地点'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: day,
            decoration: const InputDecoration(labelText: '星期'),
            items: [
              for (var i = 1; i <= 7; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    '星期${const ['一', '二', '三', '四', '五', '六', '日'][i - 1]}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => day = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: start,
                  decoration: const InputDecoration(labelText: '开始节次'),
                  items: [
                    for (var i = 1; i <= 11; i++)
                      DropdownMenuItem(value: i, child: Text('第 $i 节')),
                  ],
                  onChanged: (v) => setState(() => start = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: end,
                  decoration: const InputDecoration(labelText: '结束节次'),
                  items: [
                    for (var i = 1; i <= 11; i++)
                      DropdownMenuItem(value: i, child: Text('第 $i 节')),
                  ],
                  onChanged: (v) => setState(() => end = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: weeks,
            decoration: InputDecoration(
              labelText: '上课周次',
              helperText: '例如 2-4、6、8-10；范围为 1–${widget.schedule.totalWeeks} 周',
            ),
            validator: (_) => parseWeeks() == null ? '请输入有效周次' : null,
          ),
          const SizedBox(height: 20),
          const Text('课程颜色'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final value in [
                Colors.blue,
                Colors.teal,
                Colors.green,
                Colors.orange,
                Colors.purple,
                Colors.pink,
                Colors.indigo,
                Colors.brown,
              ])
                Semantics(
                  button: true,
                  selected: color == value,
                  label:
                      '课程颜色 ${const {0xff2196f3: '蓝色', 0xff009688: '青色', 0xff4caf50: '绿色', 0xffff9800: '橙色', 0xff9c27b0: '紫色', 0xffe91e63: '粉色', 0xff3f51b5: '靛蓝', 0xff795548: '棕色'}[value.toARGB32()] ?? '自定义'}',
                  child: InkWell(
                    onTap: () => setState(() => color = value),
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      backgroundColor: value,
                      child: color == value
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? '正在保存…' : '保存本机修改'),
          ),
        ],
      ),
    ),
  );
}
