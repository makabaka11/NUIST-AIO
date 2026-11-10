import '../campus_ui.dart';
import 'accounts.dart';
import 'charts.dart';

/// 账单概览与柱状图共用选中月，缺少缓存的月份不显示为零消费。
class MonthlySpendingReport extends StatelessWidget {
  const MonthlySpendingReport({
    super.key,
    required this.months,
    this.selectedIndex,
    required this.onSelected,
  });
  final List<MonthlySpending> months;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const Text('暂无月度消费数据');
    var index = selectedIndex;
    if (index == null || index < 0 || index >= months.length) {
      index = months.lastIndexWhere((m) => m.hasData);
      if (index < 0) index = months.length - 1;
    }
    final selected = months[index];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${selected.month.substring(0, 4)}年${int.parse(selected.month.substring(5))}月',
          key: const ValueKey('report-selected-month'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              selected.hasData ? '¥ ${money(selected.expensesCents)}' : '—',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              selected.hasData
                  ? '${selected.transactionCount} 笔交易'
                  : '该月账单尚未查询',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 16),
        MonthlySpendingChart(
          months: months,
          selectedIndex: index,
          onTap: onSelected,
        ),
        const SizedBox(height: 8),
        Text('月支出 · 元　点击柱形查看当月', style: theme.textTheme.bodySmall),
        if (selected.hasData) ...[
          const Divider(height: 28),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _ReportValue('支出', '¥ ${money(selected.expensesCents)}'),
              _ReportValue('收入', '¥ ${money(selected.incomeCents)}'),
              _ReportValue('交易笔数', '${selected.transactionCount}'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '仅展示已查询月份的学校汇总；未查询月份不计作零消费。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ReportValue extends StatelessWidget {
  const _ReportValue(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class BalanceHistoryReport extends StatefulWidget {
  const BalanceHistoryReport({
    super.key,
    required this.snapshots,
    required this.range,
    required this.color,
  });
  final List<WalletSnapshot> snapshots;
  final TimeRange range;
  final Color color;
  @override
  State<BalanceHistoryReport> createState() => _BalanceHistoryReportState();
}

class _BalanceHistoryReportState extends State<BalanceHistoryReport> {
  int? selected;
  @override
  void didUpdateWidget(BalanceHistoryReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range != widget.range ||
        oldWidget.snapshots != widget.snapshots) {
      selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final points =
        widget.snapshots
            .where(
              (s) =>
                  widget.range.cutoff == null ||
                  now.difference(s.timestamp) <= widget.range.cutoff!,
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (points.isEmpty) return const Text('所选时间范围暂无采集记录');
    final index = (selected ?? points.length - 1).clamp(0, points.length - 1);
    final point = points[index];
    final time = point.timestamp.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            ),
            Text(
              '¥ ${money(point.balanceCents)}',
              key: const ValueKey('selected-wallet-balance'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: widget.color),
            ),
          ],
        ),
        const SizedBox(height: 12),
        BalanceTrendChart(
          snapshots: points,
          range: TimeRange.all,
          color: widget.color,
          selectedIndex: index,
        ),
        if (points.length > 1)
          Slider(
            value: index.toDouble(),
            min: 0,
            max: (points.length - 1).toDouble(),
            divisions: points.length - 1,
            label: '第 ${index + 1} 次采集',
            onChanged: (value) => setState(() => selected = value.round()),
          ),
        Text(
          points.length == 1
              ? '已采集 1 次，继续采集后显示趋势。'
              : '拖动查看各次采集余额 · 区间 ${points.length} 次',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
