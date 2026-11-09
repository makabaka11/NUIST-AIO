import 'package:flutter/material.dart';

import 'app_state.dart';
import 'accounts/accounts.dart';
import 'accounts/accounts_page.dart';
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
    final wallet = state.accounts.wallet;
    final bill = state.accounts.currentBills?.month == currentMonth()
        ? state.accounts.currentBills
        : null;
    final power = state.accounts.electricity?.dormKey == state.dorm?.key
        ? state.accounts.electricity
        : null;
    String updated(DateTime? date) => date == null
        ? '尚未同步'
        : '缓存 · ${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
                  child: Text(
                    state.servicesNotice!,
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
        SectionTitle(
          '校园账户',
          trailing: TextButton.icon(
            onPressed: () => openAccounts(context, state, autoSync: true),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('同步'),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in [
                (
                  Icons.local_library_outlined,
                  '图书借阅',
                  '— 册',
                  '借阅与归还提醒',
                  () => showPendingFeature(context, '图书借阅'),
                ),
                (
                  Icons.bolt_outlined,
                  '宿舍电费',
                  power?.display ?? '—',
                  state.dorm == null ? '先选择实际宿舍' : updated(power?.updatedAt),
                  () => openAccounts(
                    context,
                    state,
                    section: AccountSection.electricity,
                  ),
                ),
                (
                  Icons.credit_card_outlined,
                  '校园卡余额',
                  wallet == null || wallet.cards.isEmpty
                      ? '¥ —'
                      : '¥ ${money(wallet.balance)}',
                  wallet == null ? '电子账户余额' : updated(wallet.updatedAt),
                  () => openAccounts(context, state),
                ),
                (
                  Icons.bar_chart_outlined,
                  '本月支出',
                  bill == null ? '¥ —' : '¥ ${money(bill.expensesCents)}',
                  updated(bill?.updatedAt),
                  () => openAccounts(
                    context,
                    state,
                    section: AccountSection.bills,
                  ),
                ),
              ])
                SizedBox(
                  width: box.maxWidth < 280
                      ? box.maxWidth
                      : (box.maxWidth - 12) / 2,
                  child: Card(
                    color: colors.surfaceContainerLow,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: item.$5,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(item.$1, color: colors.primary, size: 26),
                            const SizedBox(height: 14),
                            Text(
                              item.$2,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              item.$3,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(color: colors.onSurface),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.$4,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
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
