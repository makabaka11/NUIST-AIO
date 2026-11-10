import 'dart:math' as math;

import '../campus_ui.dart';

import '../app_state.dart';
import '../academic/official_page.dart';
import '../services/site_registry.dart';

class SchoolCalendarPage extends StatefulWidget {
  const SchoolCalendarPage({super.key, required this.state});
  final AppState state;
  @override
  State<SchoolCalendarPage> createState() => _SchoolCalendarPageState();
}

class _SchoolCalendarPageState extends State<SchoolCalendarPage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  int term = 0, revision = 0;
  late int generation;
  static final entry = Uri.parse(
    SchoolSites.get(SchoolSiteId.portal).features
        .singleWhere((f) => f.id == 'calendar')
        .entry!,
  );
  @override
  void initState() {
    super.initState();
    generation = widget.state.sessionGeneration;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (generation != widget.state.sessionGeneration) {
      generation = widget.state.sessionGeneration;
      revision++;
      setState(() {
        data = null;
        busy = false;
        error = '账号已变化，请重新加载校历。';
      });
    }
  }

  @override
  void dispose() {
    revision++;
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> load([int? year]) async {
    final token = ++revision;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await widget.state.portalSession.query('calendar', {
        'params': {'year': ?year},
      });
      if (!mounted || token != revision) return;
      if (d['ok'] != true ||
          d['year'] is! int ||
          d['terms'] is! List ||
          (d['terms'] as List).length != 2) {
        throw const FormatException('校历数据不完整。');
      }
      setState(() => data = d);
    } on FormatException catch (e) {
      if (mounted && token == revision) setState(() => error = e.message);
    } catch (_) {
      if (mounted && token == revision) {
        setState(() => error = '校历读取失败，请确认门户登录或打开原网页。');
      }
    } finally {
      if (mounted && token == revision) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme, year = data?['year'] as int?;
    final selected = data == null
        ? null
        : Map<String, dynamic>.from((data!['terms'] as List)[term]);
    final today = DateUtils.dateOnly(
      DateTime.now().toUtc().add(const Duration(hours: 8)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('校历'),
        actions: [
          IconButton(
            tooltip: '刷新校历',
            onPressed: busy ? null : () => load(year),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () => launchSchoolBrowser(context, entry),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上一学年',
                onPressed: busy || year == null || year <= 1900
                    ? null
                    : () => load(year - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  year == null ? '学校学年校历' : '$year–${year + 1} 学年',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '下一学年',
                onPressed: busy || year == null || year >= 2200
                    ? null
                    : () => load(year + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('第一学期')),
              ButtonSegment(value: 1, label: Text('第二学期')),
            ],
            selected: {term},
            onSelectionChanged: (v) => setState(() => term = v.single),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error!, style: TextStyle(color: colors.error)),
                    TextButton(
                      onPressed: busy ? null : () => load(year),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            const Text('周次、寒暑假及事件均以学校校历为准。点击日期查看详情。'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final width = math.max(
                  constraints.maxWidth,
                  420 * scale.clamp(1, 1.5),
                );
                Widget box(String value, {bool header = false}) => SizedBox(
                  width: 48 * scale.clamp(1, 1.5),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      value,
                      textAlign: TextAlign.center,
                      style: header
                          ? Theme.of(context).textTheme.labelMedium
                          : Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width.toDouble(),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            box('周次', header: true),
                            for (final d in ['一', '二', '三', '四', '五', '六', '日'])
                              Expanded(
                                child: Text(d, textAlign: TextAlign.center),
                              ),
                          ],
                        ),
                        for (final raw in selected['weeks'] as List)
                          Builder(
                            builder: (context) {
                              final week = Map<String, dynamic>.from(
                                raw as Map,
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    box('${week['week']}'),
                                    for (final item in week['days'] as List)
                                      Expanded(
                                        child: item == null
                                            ? SizedBox(height: 72 * scale)
                                            : Builder(
                                                builder: (context) {
                                                  final day =
                                                          Map<
                                                            String,
                                                            dynamic
                                                          >.from(item as Map),
                                                      date = DateTime.parse(
                                                        day['date'] as String,
                                                      );
                                                  final isToday =
                                                          DateUtils.isSameDay(
                                                            today,
                                                            date,
                                                          ),
                                                      event =
                                                          '${day['event'] ?? ''}',
                                                      lunar =
                                                          '${day['lunar'] ?? ''}';
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.all(1),
                                                    child: Material(
                                                      color: isToday
                                                          ? colors
                                                                .primaryContainer
                                                          : event.isNotEmpty
                                                          ? colors
                                                                .tertiaryContainer
                                                          : colors
                                                                .surfaceContainerLow,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        onTap: () => showDialog<void>(
                                                          context: context,
                                                          builder: (_) => AlertDialog(
                                                            title: Text(
                                                              '${date.year}年${date.month}月${date.day}日',
                                                            ),
                                                            content: Text(
                                                              '${year!}–${year + 1} 学年 · 第${term + 1}学期\n${RegExp(r"^\d+$").hasMatch('${week['week']}') ? '第${week['week']}周' : week['week']}\n$lunar${event.isEmpty ? '' : '\n$event'}',
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      context,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      '知道了',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        child: SizedBox(
                                                          height: 72 * scale,
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Text(
                                                                '${date.month}/${date.day}',
                                                                style:
                                                                    Theme.of(
                                                                      context,
                                                                    ).textTheme.labelMedium?.copyWith(
                                                                      fontWeight:
                                                                          isToday
                                                                          ? FontWeight.bold
                                                                          : null,
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              Text(
                                                                event.isEmpty
                                                                    ? lunar
                                                                    : event,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: Theme.of(
                                                                  context,
                                                                ).textTheme.labelSmall,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if ('${selected['remarks'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SelectableText('${selected['remarks']}'),
              ),
          ],
        ],
      ),
    );
  }
}
