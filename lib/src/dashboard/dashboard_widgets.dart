import 'dart:async';

import '../campus_ui.dart';

import '../app_state.dart';
import '../accounts/accounts.dart';
import '../accounts/accounts_page.dart';
import '../library/library_page.dart';
import '../calendar/calendar_page.dart';
import '../status_tag.dart';
import '../widgets.dart';
import 'dashboard_config.dart';
import 'holiday.dart';

IconData dashboardIcon(DashboardWidgetId id) => switch (id) {
  DashboardWidgetId.library => Icons.local_library_outlined,
  DashboardWidgetId.electricity => Icons.bolt_outlined,
  DashboardWidgetId.wallet => Icons.credit_card_outlined,
  DashboardWidgetId.spending => Icons.bar_chart_outlined,
  DashboardWidgetId.holiday => Icons.beach_access_outlined,
};
void customizeDashboard(BuildContext context, AppState state) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 500,
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(child: Text('自定义首页小组件')),
                      IconButton(
                        tooltip: '关闭小组件设置',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text('开关控制显示，拖动右侧手柄调整顺序。'),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: state.dashboardLayout.order.length,
                    onReorderItem: (oldIndex, newIndex) => unawaited(
                      state.updateDashboard(
                        state.dashboardLayout.reorder(oldIndex, newIndex),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final id = state.dashboardLayout.order[index];
                      return ListTile(
                        key: ValueKey('dashboard-option-${id.name}'),
                        leading: Icon(dashboardIcon(id)),
                        title: Text(id.label),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: !state.dashboardLayout.disabled.contains(
                                id,
                              ),
                              onChanged: (enabled) => unawaited(
                                state.updateDashboard(
                                  state.dashboardLayout.toggle(id, enabled),
                                ),
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

class DashboardWidgets extends StatelessWidget {
  const DashboardWidgets({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    final wallet = state.accounts.wallet;
    final bill = state.accounts.currentBills?.month == currentMonth()
        ? state.accounts.currentBills
        : null;
    final power = state.accounts.electricity?.dormKey == state.dorm?.key
        ? state.accounts.electricity
        : null;
    final loans = state.libraryLoans;
    SchoolHoliday? holiday;
    if (state.schoolCalendar != null || state.publicHolidays.isNotEmpty) {
      try {
        holiday = SchoolHoliday.next(
          state.schoolCalendar ?? {'terms': []},
          today,
          supplement: state.publicHolidays,
        );
      } catch (_) {
        /* Unknown calendar never invents a holiday. */
      }
    }
    String updated(DateTime? date) => date == null
        ? '尚未同步'
        : '缓存 · ${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    ({String value, String detail, VoidCallback open, bool error}) content(
      DashboardWidgetId id,
    ) => switch (id) {
      DashboardWidgetId.library => (
        value: loans == null ? '— 册' : '${loans.books.length} 册',
        detail:
            state.libraryNotice ??
            (loans == null
                ? '连接图书馆读取借阅'
                : loans.books.any((b) => b.overdue(today))
                ? '${loans.books.where((b) => b.overdue(today)).length} 册已逾期'
                : updated(loans.updatedAt)),
        open: () => openLibrary(context, state),
        error:
            state.libraryNotice != null ||
            (loans?.books.any((b) => b.overdue(today)) ?? false),
      ),
      DashboardWidgetId.electricity => (
        value: power?.display ?? '—',
        detail: state.dorm == null ? '先选择实际宿舍' : updated(power?.updatedAt),
        open: () =>
            openAccounts(context, state, section: AccountSection.electricity),
        error: false,
      ),
      DashboardWidgetId.wallet => (
        value: wallet == null || wallet.cards.isEmpty
            ? '¥ —'
            : '¥ ${money(wallet.balance)}',
        detail: wallet == null ? '电子账户余额' : updated(wallet.updatedAt),
        open: () => openAccounts(context, state),
        error: false,
      ),
      DashboardWidgetId.spending => (
        value: bill == null ? '¥ —' : '¥ ${money(bill.expensesCents)}',
        detail: updated(bill?.updatedAt),
        open: () => openAccounts(context, state, section: AccountSection.bills),
        error: false,
      ),
      DashboardWidgetId.holiday => (
        value: holiday == null
            ? '— 天'
            : holiday.active(today)
            ? (holiday.declaredBreak ? '假期中' : '节日当天')
            : '${holiday.daysFrom(today)} 天',
        detail: (holiday != null && holiday.supplemental
            ? '${holiday.name} · ${holiday.start.month}/${holiday.start.day}${holiday.start == holiday.end ? '' : '–${holiday.end.month}/${holiday.end.day}'} · 国务院数据，最终以学校通知为准'
            : state.calendarNotice ??
                  (state.schoolCalendar == null
                      ? '连接门户读取学校校历'
                      : holiday == null
                      ? '校历尚未标注后续小长假'
                      : '${holiday.name} · ${holiday.start.month}/${holiday.start.day}${holiday.declaredBreak ? '' : ' · 放假安排以通知为准'}')),
        open: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => SchoolCalendarPage(state: state)),
        ),
        error: state.calendarNotice != null,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          '数据看板',
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: '同步看板',
                onPressed: state.connectingServices
                    ? null
                    : state.connectCampusServices,
                icon: const Icon(Icons.sync),
              ),
              IconButton(
                tooltip: '自定义首页小组件',
                onPressed: () => customizeDashboard(context, state),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
        if (state.dashboardLayout.enabled.isEmpty)
          OutlinedButton.icon(
            onPressed: () => customizeDashboard(context, state),
            icon: const Icon(Icons.add),
            label: const Text('添加首页小组件'),
          ),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final id in state.dashboardLayout.enabled)
                Builder(
                  builder: (context) {
                    final data = content(id),
                        accent = data.error
                            ? colors.error
                            : categoryAccent(context, id.name);
                    return SizedBox(
                      key: ValueKey('dashboard-${id.name}'),
                      width: box.maxWidth < 280
                          ? box.maxWidth
                          : (box.maxWidth - 12) / 2,
                      child: Card(
                        color: colors.surfaceContainerLow,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: data.open,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  dashboardIcon(id),
                                  color: accent,
                                  size: 26,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  id.label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  data.value,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  data.detail,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: data.error
                                            ? colors.error
                                            : colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
