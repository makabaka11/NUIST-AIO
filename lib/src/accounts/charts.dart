// 校园账户数据可视化图表组件。
// 基于 fl_chart 封装余额曲线、电量趋势、月度消费柱状图和消费去向进度条。
// 配色跟随当前主题，支持浅色/深色模式。

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';

import '../campus_ui.dart';

import 'accounts.dart';

/// 通用的时间范围筛选枚举。
enum TimeRange { days7, days30, days90, year1, all }

extension TimeRangeLabel on TimeRange {
  String get label => switch (this) {
    TimeRange.days7 => '7天',
    TimeRange.days30 => '30天',
    TimeRange.days90 => '90天',
    TimeRange.year1 => '1年',
    TimeRange.all => '全部',
  };
  Duration? get cutoff => switch (this) {
    TimeRange.days7 => const Duration(days: 7),
    TimeRange.days30 => const Duration(days: 30),
    TimeRange.days90 => const Duration(days: 90),
    TimeRange.year1 => const Duration(days: 365),
    TimeRange.all => null,
  };
}

// ────────────────────── 余额曲线 ──────────────────────

/// 校园卡余额趋势折线图。接收 [WalletSnapshot] 列表，
/// 按 [range] 筛选时间窗口，绘制带渐变填充的面积折线。
class BalanceTrendChart extends StatelessWidget {
  const BalanceTrendChart({
    super.key,
    required this.snapshots,
    required this.range,
    required this.color,
    this.selectedIndex,
  });
  final List<WalletSnapshot> snapshots;
  final TimeRange range;
  final Color color;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cutoff = range.cutoff;
    final now = DateTime.now();
    final points = snapshots
        .where((s) => cutoff == null || now.difference(s.timestamp) <= cutoff)
        .toList();
    if (points.length < 2) {
      return _chartPlaceholder(context, '采集记录不足，暂无曲线');
    }
    final spots = [
      for (final p in points)
        FlSpot(
          p.timestamp.millisecondsSinceEpoch.toDouble(),
          p.balanceCents / 100,
        ),
    ];
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final padY = (maxY - minY) * 0.15 + 0.5;
    final minX = spots.first.x;
    final maxX = math.max(spots.last.x, minX + 60000);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: (minY - padY).clamp(0, double.infinity),
          maxY: maxY + padY,
          clipData: FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(
              maxY + padY - (minY - padY).clamp(0, double.infinity),
            ),
            getDrawingHorizontalLine: (v) => FlLine(
              color: theme.dividerColor.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize:
                    42 * MediaQuery.textScalerOf(context).scale(10) / 10,
                minIncluded: false,
                maxIncluded: false,
                interval: _niceInterval(
                  maxY + padY - (minY - padY).clamp(0, double.infinity),
                ),
                getTitlesWidget: (value, meta) =>
                    _leftTitle(context, value, meta, '元'),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxX - minX,
                getTitlesWidget: (value, meta) => _bottomDateTitle(
                  context,
                  value,
                  meta,
                  points.cast<DateTimeStamped>(),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: color,
              barWidth: 2.5,
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
              dotData: FlDotData(
                show: selectedIndex != null,
                checkToShowDot: (spot, _) =>
                    selectedIndex! < spots.length &&
                    spot == spots[selectedIndex!],
              ),
              showingIndicators: [spots.length - 1],
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '¥${s.y.toStringAsFixed(2)}',
                      TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

// ────────────────────── 电量趋势 ──────────────────────

/// 宿舍电量趋势折线图。接收 [ElectricitySnapshot] 列表。
class ElectricityTrendChart extends StatelessWidget {
  const ElectricityTrendChart({
    super.key,
    required this.snapshots,
    required this.range,
    required this.color,
  });
  final List<ElectricitySnapshot> snapshots;
  final TimeRange range;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cutoff = range.cutoff;
    final now = DateTime.now();
    final points = snapshots
        .where((s) => cutoff == null || now.difference(s.timestamp) <= cutoff)
        .toList();
    final unit = points.isEmpty ? '度' : points.first.unit;
    if (points.length < 2) {
      return _chartPlaceholder(context, '采集记录不足，暂无趋势');
    }
    final spots = [
      for (final p in points)
        FlSpot(p.timestamp.millisecondsSinceEpoch.toDouble(), p.value),
    ];
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final padY = (maxY - minY) * 0.15 + 0.5;
    final minX = spots.first.x;
    final maxX = math.max(spots.last.x, minX + 60000);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: (minY - padY).clamp(0, double.infinity),
          maxY: maxY + padY,
          clipData: FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(
              maxY + padY - (minY - padY).clamp(0, double.infinity),
            ),
            getDrawingHorizontalLine: (v) => FlLine(
              color: theme.dividerColor.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize:
                    42 * MediaQuery.textScalerOf(context).scale(10) / 10,
                minIncluded: false,
                maxIncluded: false,
                interval: _niceInterval(
                  maxY + padY - (minY - padY).clamp(0, double.infinity),
                ),
                getTitlesWidget: (value, meta) =>
                    _leftTitle(context, value, meta, unit),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxX - minX,
                getTitlesWidget: (value, meta) => _bottomDateTitle(
                  context,
                  value,
                  meta,
                  points.cast<DateTimeStamped>(),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              curveSmoothness: 0.3,
              color: color,
              barWidth: 2.5,
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.15),
              ),
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) => spot == spots.last,
              ),
              showingIndicators: [spots.length - 1],
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(2)} $unit',
                      TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

// ────────────────────── 月度消费柱状图 ──────────────────────

/// 月度消费柱状图。接收 [months]（按时间正序排列的月度汇总），
/// [selectedIndex] 为高亮柱形索引。
class MonthlySpendingChart extends StatelessWidget {
  const MonthlySpendingChart({
    super.key,
    required this.months,
    this.selectedIndex,
    this.onTap,
  });
  final List<MonthlySpending> months;
  final int? selectedIndex;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (months.isEmpty) return _chartPlaceholder(context, '暂无月度消费数据');
    final maxVal = months.map((m) => m.expensesYuan).fold<double>(0, math.max);
    final chartMax = maxVal * 1.2 + 1;
    final color = theme.colorScheme.tertiary;
    final showYears =
        months.map((m) => m.month.substring(0, 4)).toSet().length > 1 ||
        !months.first.month.startsWith('${DateTime.now().year}-');
    final labels = months
        .map(
          (m) =>
              '${showYears ? '${m.month.substring(0, 4)}\n' : ''}${int.parse(m.month.substring(5))}月',
        )
        .toList();
    final style = theme.textTheme.labelSmall!.copyWith(
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        var labelWidth = 0.0, labelHeight = 0.0;
        for (final label in labels) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
          )..layout();
          labelWidth = math.max(labelWidth, painter.width);
          labelHeight = math.max(labelHeight, painter.height);
          painter.dispose();
        }
        // 两端留足文字宽度；按实际字号和绘图区宽度抽稀刻度，不压缩字体。
        final edge = labelWidth / 2 + 6;
        final width = math.max(1.0, constraints.maxWidth - edge * 2);
        final slot = width / months.length;
        final stride = math.max(1, ((labelWidth + 10) / slot).ceil());
        final reserved = labelHeight + 14;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: edge),
          child: SizedBox(
            height: 155 + reserved,
            child: BarChart(
              BarChartData(
                maxY: chartMax,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent && response?.spot != null) {
                      onTap?.call(response!.spot!.touchedBarGroupIndex);
                    }
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final m = months[group.x];
                      return BarTooltipItem(
                        '${m.month}\n${m.hasData ? '¥ ${money(m.expensesCents)}' : '尚未查询'}',
                        TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                    getTooltipColor: (_) =>
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: reserved,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if ((value - i).abs() > .01 ||
                            i < 0 ||
                            i >= months.length ||
                            (i != months.length - 1 &&
                                (i % stride != 0 ||
                                    months.length - 1 - i < stride))) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Semantics(
                            label: months[i].month,
                            child: Text(
                              labels[i],
                              key: ValueKey('month-axis-${months[i].month}'),
                              textAlign: TextAlign.center,
                              style: style.copyWith(
                                color: i == selectedIndex
                                    ? color
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _niceInterval(chartMax),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.dividerColor.withValues(alpha: .2),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: months[i].hasData ? months[i].expensesYuan : 0,
                          color: i == selectedIndex
                              ? color
                              : color.withValues(alpha: .7),
                          width: math.min(18, slot * .55),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 250),
            ),
          ),
        );
      },
    );
  }
}

/// 月度消费汇总。
class MonthlySpending {
  const MonthlySpending(
    this.month,
    this.expensesCents,
    this.incomeCents,
    this.transactionCount, {
    this.hasData = true,
  });
  final bool hasData;
  final String month; // "2026-10"
  final int expensesCents, incomeCents, transactionCount;
  double get expensesYuan => expensesCents / 100;
  double get incomeYuan => incomeCents / 100;

  /// 显示用短标签 "10月" 或 "2025-12"。
  String get label {
    final parts = month.split('-');
    return parts[0] == DateTime.now().year.toString() ? '${parts[1]}月' : month;
  }
}

// ────────────────────── 消费去向进度条 ──────────────────────

/// 消费去向——按描述聚合后的水平进度条列表。
class SpendingBreakdown extends StatelessWidget {
  const SpendingBreakdown({
    super.key,
    required this.items,
    required this.color,
    this.limit = 5,
  });
  final List<SpendingCategory> items;
  final Color color;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = [...items]
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
    final shown = top.take(limit).toList();
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '暂无消费分类数据',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final maxAmount = shown.first.amountCents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _BreakdownRow(
            index: i + 1,
            label: shown[i].label,
            amountCents: shown[i].amountCents,
            fraction: maxAmount == 0 ? 0 : shown[i].amountCents / maxAmount,
            color: color,
          ),
        ],
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.index,
    required this.label,
    required this.amountCents,
    required this.fraction,
    required this.color,
  });
  final int index;
  final String label;
  final int amountCents;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackColor = theme.colorScheme.surfaceContainerHighest;
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            index.toString().padLeft(2, '0'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '¥ ${money(amountCents)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: trackColor,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 消费分类汇总。
class SpendingCategory {
  const SpendingCategory(this.label, this.amountCents);
  final String label;
  final int amountCents;
}

// ────────────────────── 辅助函数 ──────────────────────

double _niceInterval(double range) {
  if (range <= 0) return 1;
  final magnitude = (range / 4).clamp(0.1, double.infinity);
  if (magnitude >= 100) return (magnitude / 50).round() * 50;
  if (magnitude >= 10) return (magnitude / 5).round() * 5;
  if (magnitude >= 1) return (magnitude / 0.5).round() * 0.5;
  return (magnitude * 10).round() / 10;
}

Widget _chartPlaceholder(BuildContext context, String message) {
  final theme = Theme.of(context);
  return SizedBox(
    height: 180,
    child: Center(
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

Widget _leftTitle(
  BuildContext context,
  double value,
  TitleMeta meta,
  String unit,
) {
  final theme = Theme.of(context);
  final text = unit == '元'
      ? '¥${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}'
      : value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  return SideTitleWidget(
    meta: meta,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
    ),
  );
}

Widget _bottomDateTitle(
  BuildContext context,
  double value,
  TitleMeta meta,
  List<DateTimeStamped> points,
) {
  if ((value - meta.min).abs() > 1 && (value - meta.max).abs() > 1) {
    return const SizedBox.shrink();
  }
  final theme = Theme.of(context);
  DateTimeStamped? nearest;
  double minDist = double.infinity;
  for (final p in points) {
    final d = (p.timestamp.millisecondsSinceEpoch.toDouble() - value).abs();
    if (d < minDist) {
      minDist = d;
      nearest = p;
    }
  }
  final dt = nearest?.timestamp;
  final sameDay =
      points.isNotEmpty &&
      DateUtils.isSameDay(points.first.timestamp, points.last.timestamp);
  final text = dt == null
      ? ''
      : sameDay
      ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
      : '${dt.month}-${dt.day.toString().padLeft(2, '0')}';
  return SideTitleWidget(
    meta: meta,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
    ),
  );
}
