import 'dart:math' as math;

import '../campus_ui.dart';

import '../app_state.dart';
import 'schedule.dart';
import 'course_style.dart';
import 'schedule_widgets.dart';

class WeekSchedule extends StatefulWidget {
  const WeekSchedule({super.key, required this.state});
  final AppState state;
  @override
  State<WeekSchedule> createState() => _WeekScheduleState();
}

class _WeekScheduleState extends State<WeekSchedule> {
  int? selectedWeek;
  String? term;
  @override
  Widget build(BuildContext context) {
    final schedule = widget.state.schedule;
    if (schedule == null) return const SizedBox.shrink();
    if (term != schedule.term) {
      term = schedule.term;
      selectedWeek = null;
    }
    final current = schedule.weekAt(DateTime.now());
    final week =
        (selectedWeek ??
                ((current != null &&
                        current >= 1 &&
                        current <= schedule.totalWeeks)
                    ? current
                    : 1))
            .clamp(1, schedule.totalWeeks);
    final monday = schedule.startDate == null
        ? null
        : mondayOf(schedule.startDate!).add(Duration(days: (week - 1) * 7));
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上一周',
              onPressed: week <= 1
                  ? null
                  : () => setState(() => selectedWeek = week - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: week,
                items: [
                  for (var w = 1; w <= schedule.totalWeeks; w++)
                    DropdownMenuItem(
                      value: w,
                      child: Text('第 $w 周${w == current ? ' · 本周' : ''}'),
                    ),
                ],
                onChanged: (v) => setState(() => selectedWeek = v),
              ),
            ),
            IconButton(
              tooltip: '下一周',
              onPressed: week >= schedule.totalWeeks
                  ? null
                  : () => setState(() => selectedWeek = week + 1),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() => selectedWeek = null),
              child: const Text('本周'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.max(
              1.0,
              MediaQuery.textScalerOf(context).scale(12) / 12,
            );
            final gutter = 48.0 * scale,
                header = 52.0 * scale,
                rowHeight = 72.0 * scale,
                    // 每个课程块（泳道）的最小宽度：保证课程名可正常显示。
                    // 同一天时间重叠的课程越多，整周视图越宽，配合横向滑动。
                    laneWidth =
                    64.0 * scale;
            final active = schedule.courses
                .where((c) => c.weeks.contains(week))
                .toList();
            final laneCount = [
              for (var d = 1; d <= 7; d++)
                _dayLaneCount(active.where((c) => c.day == d).toList()),
            ].fold(1, math.max);
            final width = math.max(
                  constraints.maxWidth,
                  gutter + 7 * laneCount * laneWidth,
                ),
                dayWidth = (width - gutter) / 7;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: header + 11 * rowHeight,
                child: Stack(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Positioned(
                        left: gutter + d * dayWidth,
                        top: 0,
                        width: dayWidth,
                        height: header,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            border: Border(
                              left: BorderSide(color: colors.outlineVariant),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '周${const ['一', '二', '三', '四', '五', '六', '日'][d]}',
                                style: Theme.of(context).textTheme.labelLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (monday != null)
                                Text(
                                  '${monday.add(Duration(days: d)).month}/${monday.add(Duration(days: d)).day}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                    for (var n = 1; n <= 11; n++) ...[
                      Positioned(
                        left: 0,
                        top: header + (n - 1) * rowHeight,
                        width: gutter,
                        height: rowHeight,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$n',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              schedule.timeFor(n),
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              schedule.timeFor(n, end: true),
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: gutter,
                        right: 0,
                        top: header + (n - 1) * rowHeight,
                        child: Divider(height: 1, color: colors.outlineVariant),
                      ),
                    ],
                    for (var d = 0; d < 7; d++)
                      Positioned(
                        left: gutter + d * dayWidth,
                        top: header,
                        bottom: 0,
                        child: VerticalDivider(
                          width: 1,
                          color: colors.outlineVariant,
                        ),
                      ),
                    for (final course in active)
                      ..._blocks(
                        context,
                        course,
                        active,
                        schedule,
                        week,
                        gutter,
                        header,
                        rowHeight,
                        dayWidth,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  /// 计算某一天的课程需要划分的泳道数（时间重叠的课程各占一道），
  /// 用于推算整周视图的最小宽度，保证每个课程块都有可读宽度。
  int _dayLaneCount(List<Course> day) {
    final sorted = [...day]
      ..sort(
        (a, b) => a.start == b.start
            ? a.end.compareTo(b.end)
            : a.start.compareTo(b.start),
      );
    final laneEnds = <int>[];
    for (final c in sorted) {
      final i = laneEnds.indexWhere((end) => end < c.start);
      if (i < 0) {
        laneEnds.add(c.end);
      } else {
        laneEnds[i] = c.end;
      }
    }
    return laneEnds.length;
  }

  List<Widget> _blocks(
    BuildContext context,
    Course course,
    List<Course> courses,
    Schedule schedule,
    int week,
    double gutter,
    double header,
    double rowHeight,
    double dayWidth,
  ) {
    // Partition interval overlaps into lanes, so no course hides another.
    final day = courses.where((c) => c.day == course.day).toList()
      ..sort(
        (a, b) => a.start == b.start
            ? a.end.compareTo(b.end)
            : a.start.compareTo(b.start),
      );
    final component = <Course>{course};
    bool changed = true;
    while (changed) {
      changed = false;
      for (final c in day) {
        if (!component.contains(c) &&
            component.any((x) => x.start <= c.end && c.start <= x.end)) {
          component.add(c);
          changed = true;
        }
      }
    }
    final lanes = <List<Course>>[];
    var lane = 0;
    for (final c in day.where(component.contains)) {
      var i = lanes.indexWhere(
        (list) => list.every((x) => x.end < c.start || c.end < x.start),
      );
      if (i < 0) {
        i = lanes.length;
        lanes.add([]);
      }
      lanes[i].add(c);
      if (identical(c, course)) lane = i;
    }
    final scheme = courseScheme(context, course),
        width = (dayWidth - 4) / lanes.length;
    // 块宽不足时收紧排版，把空间让给课程名。
    final compact = width < 76;
    return [
      Positioned(
        left: gutter + (course.day - 1) * dayWidth + lane * width + 2,
        top: header + (course.start - 1) * rowHeight + 3,
        width: width - 3,
        height: (course.end - course.start + 1) * rowHeight - 6,
        child: Semantics(
          button: true,
          label:
              '${course.name}，${course.location}，第${course.start}至${course.end}节',
          child: Material(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showCourseDetails(
                context,
                course,
                schedule,
                state: widget.state,
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 5 : 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      flex: 3,
                      child: Text(
                        course.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.labelMedium
                                    : Theme.of(context).textTheme.labelLarge)
                                ?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Flexible(
                      flex: 2,
                      child: Text(
                        course.location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.tertiary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        '${schedule.timeFor(course.start)}–${schedule.timeFor(course.end, end: true)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
