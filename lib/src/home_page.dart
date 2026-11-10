import 'campus_ui.dart';

import 'app_state.dart';
import 'dashboard/dashboard_widgets.dart';
import 'schedule/schedule_widgets.dart';
import 'widgets.dart';

class CampusHomePage extends StatelessWidget {
  const CampusHomePage({
    super.key,
    required this.state,
    required this.onLogin,
    required this.onLearning,
    required this.onFeatures,
  });
  final AppState state;
  final VoidCallback onLogin, onLearning, onFeatures;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 11
        ? '早上好'
        : hour < 14
        ? '中午好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    final icon = hour < 6 || hour >= 18
        ? Icons.dark_mode_outlined
        : Icons.wb_sunny_outlined;
    return PageBody(
      children: [
        if (state.startupNotice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              state.startupNotice!,
              style: TextStyle(color: colors.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting，${state.displayName == null ? '同学' : '${state.displayName} 同学'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '看看今天的安排，校园日常从容开始。',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              CircleAvatar(
                radius: 27,
                backgroundColor: colors.secondaryContainer,
                child: Icon(icon, color: colors.onSecondaryContainer, size: 27),
              ),
            ],
          ),
        ),
        if (state.servicesNotice != null &&
            (state.connectingServices || state.servicesNotice!.contains('未')))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: LoadingText(
                    state.servicesNotice!,
                    loading: state.connectingServices,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
                if (!state.connectingServices)
                  TextButton(
                    onPressed: state.connectCampusServices,
                    child: const Text('重试'),
                  ),
              ],
            ),
          ),
        DayScheduleCard(state: state),
        if (state.schedule == null && state.connectedAt == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('连接校园账号'),
              ),
            ),
          ),
        DashboardWidgets(state: state),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: onLearning,
              icon: const Icon(Icons.auto_stories_outlined, size: 18),
              label: const Text('查看完整课表'),
            ),
            TextButton.icon(
              onPressed: onFeatures,
              icon: const Icon(Icons.widgets_outlined, size: 18),
              label: const Text('全部功能'),
            ),
          ],
        ),
      ],
    );
  }
}
