import 'package:flutter/material.dart';

import '../app_state.dart';
import '../academic/academic.dart';
import '../academic/academic_page.dart';
import '../widgets.dart';
import 'schedule_widgets.dart';
import 'week_schedule.dart';

class LearningPage extends StatefulWidget {
  const LearningPage({super.key, required this.state});
  final AppState state;
  @override
  State<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<LearningPage> {
  bool scheduleTab = true;
  @override
  Widget build(BuildContext context) {
    final schedule = widget.state.schedule,
        colors = Theme.of(context).colorScheme;
    return PageBody(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('课程安排'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('学业服务'),
                icon: Icon(Icons.school_outlined),
              ),
            ],
            selected: {scheduleTab},
            onSelectionChanged: (v) => setState(() => scheduleTab = v.first),
          ),
        ),
        const SizedBox(height: 20),
        if (scheduleTab) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '周课表',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: '获取课表',
                onPressed: () => openScheduleImport(context, widget.state),
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => openScheduleImport(context, widget.state),
                icon: const Icon(Icons.sync),
                label: Text(schedule == null ? '获取我的课表' : '重新获取 / 更换学期'),
              ),
              OutlinedButton.icon(
                onPressed: () => importScheduleJson(context, widget.state),
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('导入课表 JSON'),
              ),
              if (schedule != null)
                TextButton.icon(
                  onPressed: () => chooseStartDate(context, widget.state),
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('开学日期'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (schedule == null)
            const EmptyCard(
              icon: Icons.calendar_month_outlined,
              title: '还没有课表',
              message: '连接学校获取课表，或导入已有课表 JSON。每天使用 11 节作息，首页显示当天时间轴。',
            )
          else ...[
            Text(
              schedule.termName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (schedule.localEdits)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('包含本机编辑或文件导入；重新获取前会提示替换。'),
              ),
            if (schedule.startDate == null) const Text('请先设置开学日期，以正确显示各周日期。'),
            WeekSchedule(state: widget.state),
            for (final warning in schedule.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  warning,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            if (schedule.unscheduled.isNotEmpty) ...[
              const SectionTitle('时间待定的课程'),
              for (final c in schedule.unscheduled)
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text(c.name),
                  subtitle: Text(c.teacher.isEmpty ? '教务暂未安排时间' : c.teacher),
                ),
            ],
          ],
        ] else ...[
          for (final feature in AcademicFeature.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: colors.surfaceContainerLow,
                child: ListTile(
                  leading: Icon(switch (feature) {
                    AcademicFeature.rooms => Icons.meeting_room_outlined,
                    AcademicFeature.credits => Icons.school_outlined,
                    AcademicFeature.exams => Icons.edit_calendar_outlined,
                    AcademicFeature.grades => Icons.assessment_outlined,
                  }),
                  title: Text(feature.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openAcademic(context, widget.state, feature),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
