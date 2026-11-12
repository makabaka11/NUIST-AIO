import '../campus_ui.dart';

import '../app_state.dart';
import '../chaoxing/chaoxing_page.dart';
import 'site_registry.dart';

class ServiceInitializationPanel extends StatelessWidget {
  const ServiceInitializationPanel({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final sites = SchoolSites.all;
      final active = SchoolSites.automatic.toList();
      final finished = active
          .where(
            (s) => {
              SitePhase.ready,
              SitePhase.failed,
              // Optional sessions with no saved login were checked and skipped.
              SitePhase.planned,
            }.contains(state.sitePhase(s)),
          )
          .length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.connectedAt == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('尚未登录校园账号，连接后即可初始化。也可以稍后在“我的”中重新运行设置向导。'),
            ),
          if (state.connectedAt != null) ...[
            LinearProgressIndicator(
              value: active.isEmpty ? 1 : finished / active.length,
            ),
            const SizedBox(height: 8),
            Text('已检查 $finished / ${active.length} 个已接入子站点'),
            const SizedBox(height: 12),
          ],
          for (final site in sites)
            if (site.id == SchoolSiteId.chaoxing)
              Card(child: ChaoxingAccountTile(state: state))
            else
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.sitePhase(site) == SitePhase.connecting)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          switch (state.sitePhase(site)) {
                            SitePhase.ready => Icons.check_circle_outline,
                            SitePhase.failed => Icons.error_outline,
                            SitePhase.planned => Icons.schedule_outlined,
                            _ => Icons.radio_button_unchecked,
                          },
                          size: 22,
                          color: state.sitePhase(site) == SitePhase.failed
                              ? colors.error
                              : colors.primary,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(switch (state.sitePhase(site)) {
                              SitePhase.ready =>
                                state.siteMessages[site.id] ?? '主账号会话已保存',
                              SitePhase.connecting =>
                                state.siteMessages[site.id] ?? '正在连接…',
                              SitePhase.failed =>
                                state.siteMessages[site.id] ?? '初始化未完成，请重试',
                              SitePhase.planned =>
                                site.browserOnly
                                    ? '仅在系统浏览器打开，不获取凭据'
                                    : '待接入，暂不获取凭据',
                              SitePhase.waiting =>
                                site.onDemand
                                    ? '按网络路径按需连接'
                                    : state.connectedAt == null
                                    ? '等待主账号登录'
                                    : '等待初始化',
                            }, style: Theme.of(context).textTheme.bodySmall),
                            if (site.features.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                site.features
                                    .map(
                                      (f) => f.implemented
                                          ? f.label
                                          : '${f.label}（待接入）',
                                    )
                                    .join(' · '),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (state.connectedAt != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: state.connectingServices
                    ? null
                    : () => state.connectCampusServices(synchronizeData: false),
                icon: const Icon(Icons.refresh),
                label: const Text('重新初始化'),
              ),
            ),
        ],
      );
    },
  );
}
