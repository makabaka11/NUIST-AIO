import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import '../campus_ui.dart';

import '../app_state.dart';
import '../theme_settings.dart';
import 'import_page.dart';
import 'schedule.dart';
import 'course_style.dart';
import 'course_editor.dart';
import 'json_import.dart';

Future<void> openScheduleImport(BuildContext context, AppState state) async {
  if (!await confirmScheduleReplacement(context, state)) return;
  if (!context.mounted) return;
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => ScheduleImportPage(state: state)),
  );
  if (context.mounted && result == true) {
    showCampusSnackBar(context, const SnackBar(content: Text('课表已保存，可离线查看。')));
  }
}

Future<bool> confirmScheduleReplacement(
  BuildContext context,
  AppState state,
) async {
  if (state.schedule?.localEdits != true) return true;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('替换本机课表？'),
          content: const Text('本机编辑和删除的信息会被新课表替换。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续替换'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> importScheduleJson(BuildContext context, AppState state) async {
  if (!await confirmScheduleReplacement(context, state) || !context.mounted) {
    return;
  }
  final generation = state.sessionGeneration;
  await uiAction(context, () async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '课表 JSON',
          extensions: ['json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (file == null) return;
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('课表文件超过 2MB，请检查文件。');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('请选择有效的课表 JSON 文件。');
    }
    final schedule = ScheduleJsonImport.parse(data);
    if (generation != state.sessionGeneration) {
      throw const FormatException('账号已变化，请重新导入。');
    }
    await state.saveSchedule(schedule, generation: generation);
    if (context.mounted) {
      showCampusSnackBar(context,
        SnackBar(
          content: Text('已导入 ${schedule.courses.length} 条安排，使用 11 节作息。'),
        ),
      );
    }
  });
}

Future<void> chooseStartDate(BuildContext context, AppState state) async {
  final schedule = state.schedule;
  if (schedule == null) {
    return;
  }
  final date = await showDatePicker(
    context: context,
    initialDate: schedule.startDate ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    helpText: '设置第 1 周的开学日期',
  );
  if (date != null && context.mounted) {
    await uiAction(
      context,
      () => state.saveSchedule(
        schedule.withStart(date),
        generation: state.sessionGeneration,
      ),
    );
  }
}

class DayScheduleCard extends StatefulWidget {
  const DayScheduleCard({super.key, required this.state, this.initialDate});
  final AppState state;
  final DateTime? initialDate;
  @override
  State<DayScheduleCard> createState() => _DayScheduleCardState();
}

class _DayScheduleCardState extends State<DayScheduleCard> {
  late DateTime selected = dateOnly(widget.initialDate ?? DateTime.now());
  static const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final schedule = widget.state.schedule;
    final week = schedule?.weekAt(selected);
    final courses = schedule?.onDate(selected) ?? [];
    final monday = mondayOf(selected);
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selected.month}月${selected.day}日  星期${weekdays[selected.weekday - 1]}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        schedule == null
                            ? '校园日程'
                            : week == null
                            ? '请设置开学日期'
                            : week < 1 || week > schedule.totalWeeks
                            ? '非教学周'
                            : '${schedule.termName} · 第 $week 周',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '上一周',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                    () => selected = selected.subtract(const Duration(days: 7)),
                  ),
                ),
                IconButton(
                  tooltip: '选择日期',
                  icon: const Icon(Icons.event_outlined),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selected,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null && mounted) {
                      setState(() => selected = dateOnly(date));
                    }
                  },
                ),
                IconButton(
                  tooltip: '下一周',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                    () => selected = selected.add(const Duration(days: 7)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: _dateCell(context, monday.add(Duration(days: i))),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            if (schedule == null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('导入课表，今天的课程就会出现在这里。'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => openScheduleImport(context, widget.state),
                icon: const Icon(Icons.download_outlined),
                label: const Text('获取我的课表'),
              ),
            ] else if (week == null) ...[
              const Text('需要开学日期来计算周次，避免把课程放错日期。'),
              TextButton(
                onPressed: () => chooseStartDate(context, widget.state),
                child: const Text('设置开学日期'),
              ),
            ] else if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Icon(Icons.free_breakfast_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        week < 1 || week > schedule.totalWeeks
                            ? '这一天不在当前学期教学周内。'
                            : '这一天没有已安排的课程。',
                      ),
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < courses.length; i++)
                _CourseTimeline(
                  first: i == 0,
                  course: courses[i],
                  schedule: schedule,
                  date: selected,
                  state: widget.state,
                ),
            if (schedule != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    Text(
                      '本机课表 · ${schedule.updatedAt.month}/${schedule.updatedAt.day} 更新',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (schedule.unscheduled.isNotEmpty)
                      Text(
                        ' · ${schedule.unscheduled.length} 门课程时间待定',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dateCell(BuildContext context, DateTime date) {
    final colors = Theme.of(context).colorScheme;
    final active = date == selected;
    final today = date == dateOnly(DateTime.now());
    return Semantics(
      selected: active,
      button: true,
      label: '${date.month}月${date.day}日 星期${weekdays[date.weekday - 1]}',
      child: Material(
        color: active ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => selected = date),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  weekdays[date.weekday - 1],
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: today ? colors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseTimeline extends StatelessWidget {
  const _CourseTimeline({
    required this.first,
    required this.course,
    required this.schedule,
    required this.date,
    required this.state,
  });
  final bool first;
  final Course course;
  final Schedule schedule;
  final DateTime date;
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final courseColors = courseScheme(context, course);
    final now = DateTime.now();
    final startTime = schedule.timeFor(course.start),
        endTime = schedule.timeFor(course.end, end: true);
    DateTime? at(String time) {
      if (!TimeSlot.validTime(time)) {
        return null;
      }
      final p = time.split(':');
      return DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(p[0]),
        int.parse(p[1]),
      );
    }

    final start = at(startTime), end = at(endTime);
    final String status = now.isBefore(dateOnly(date))
        ? '课程'
        : dateOnly(now).isAfter(date)
        ? '已结束'
        : start == null || end == null
        ? '课程'
        : now.isAfter(end)
        ? '已结束'
        : now.isBefore(start)
        ? '待上课'
        : '进行中';
    return Stack(
      children: [
        Positioned(
          left: 4,
          top: first ? 20 : 0,
          bottom: 0,
          child: Container(width: 1.5, color: colors.outlineVariant),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 19, right: 8),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: courseColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    startTime,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colors.primary),
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  key: ValueKey('home-course-${course.name}-${course.start}'),
                  color: courseColors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showCourseDetails(
                      context,
                      course,
                      schedule,
                      state: state,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  course.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: courseColors.onPrimaryContainer,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                status,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: course.location,
                                  style: TextStyle(
                                    color: courseColors.tertiary,
                                  ),
                                ),
                                TextSpan(
                                  text: ' · $startTime–$endTime',
                                  style: TextStyle(
                                    color: courseColors.secondary,
                                  ),
                                ),
                                if (course.teacher.isNotEmpty)
                                  TextSpan(
                                    text: ' · ${course.teacher}',
                                    style: TextStyle(
                                      color: courseColors.onPrimaryContainer,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void showCourseDetails(
  BuildContext context,
  Course course,
  Schedule schedule, {
  AppState? state,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(course.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text(course.teacher.isEmpty ? '教师待定' : '教师：${course.teacher}'),
            const SizedBox(height: 10),
            Text('地点：${course.location}'),
            const SizedBox(height: 10),
            Text(
              '星期${const ['一', '二', '三', '四', '五', '六', '日'][course.day - 1]} · 第 ${course.start}–${course.end} 节',
            ),
            const SizedBox(height: 10),
            Text(
              '${schedule.timeFor(course.start)}–${schedule.timeFor(course.end, end: true)}',
            ),
            const SizedBox(height: 10),
            Text('上课周次：${weekRanges(course.weeks)} 周'),
            if (schedule.courses.any(
              (c) => c.name == course.name && c.location != course.location,
            )) ...[
              const SizedBox(height: 16),
              const Text('这门课程的其他地点安排'),
              for (final other in schedule.courses.where(
                (c) => c.name == course.name && c.location != course.location,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '第 ${weekRanges(other.weeks)} 周 · ${other.location}',
                  ),
                ),
            ],
            if (state != null) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CourseEditorPage(
                            state: state,
                            course: course,
                            schedule: schedule,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final generation = state.sessionGeneration;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('删除这条课程安排？'),
                          content: Text(
                            '${course.name}\n第 ${weekRanges(course.weeks)} 周 · ${course.location}\n只从本机删除，不影响同名课程的其他安排。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      await uiAction(context, () async {
                        if (state.sessionGeneration != generation ||
                            !identical(state.schedule, schedule)) {
                          throw const FormatException('课表已变化，请重新打开课程。');
                        }
                        final next = schedule.replaceCourse(course, null);
                        await state.saveSchedule(next, generation: generation);
                        if (context.mounted) Navigator.pop(context);
                      });
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除本机安排'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
