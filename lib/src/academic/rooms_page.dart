import '../campus_ui.dart';

import '../app_state.dart';
import '../auth/login_page.dart';
import '../widgets.dart';
import 'academic.dart';
import 'official_page.dart';
import 'room_availability.dart';

class RoomAvailabilityPage extends StatefulWidget {
  const RoomAvailabilityPage({super.key, required this.state});
  final AppState state;
  @override
  State<RoomAvailabilityPage> createState() => _RoomAvailabilityPageState();
}

class _RoomAvailabilityPageState extends State<RoomAvailabilityPage> {
  DateTime date = DateTime.now();
  String? building, error;
  String search = '';
  List<Map<String, dynamic>> buildings = [];
  List<RoomSlot> slots = [];
  List<RoomAvailability> rooms = [];
  bool busy = false, loaded = false;
  int revision = 0;
  late int generation;
  Uri get entry => AcademicFeature.rooms.entry;
  @override
  void initState() {
    super.initState();
    generation = widget.state.sessionGeneration;
    widget.state.addListener(accountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) initialize();
    });
  }

  void accountChanged() {
    if (generation == widget.state.sessionGeneration) return;
    generation = widget.state.sessionGeneration;
    revision++;
    setState(() {
      busy = false;
      rooms = [];
      slots = [];
      buildings = [];
      building = null;
      loaded = false;
      error = '账号已变化，请重新连接后加载教学楼。';
    });
  }

  @override
  void dispose() {
    revision++;
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  String get dateCode =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  Future<void> initialize() async {
    if (busy || widget.state.connectedAt == null) return;
    final id = ++revision, account = widget.state.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await widget.state.teachingSession.query('roomsOptions', {});
      if (!mounted ||
          id != revision ||
          account != widget.state.sessionGeneration) {
        return;
      }
      if (d['ok'] != true) {
        throw FormatException('${d['error'] ?? '教学楼清单加载失败。'}');
      }
      setState(() {
        buildings = (d['buildings'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
      });
    } catch (e) {
      if (mounted && id == revision) {
        setState(
          () => error = e is FormatException ? e.message : '教学楼清单加载失败，请重试。',
        );
      }
    } finally {
      if (mounted && id == revision) setState(() => busy = false);
    }
  }

  Future<void> query() async {
    if (busy || building == null || widget.state.connectedAt == null) return;
    final id = ++revision, account = widget.state.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
      loaded = false;
      rooms = [];
      slots = [];
    });
    try {
      final d = await widget.state.teachingSession.query('rooms', {
        'params': {'date': dateCode, 'building': building},
      });
      if (!mounted ||
          id != revision ||
          account != widget.state.sessionGeneration) {
        return;
      }
      if (d['ok'] != true) {
        throw FormatException('${d['error'] ?? '全天空闲情况查询失败。'}');
      }
      setState(() {
        slots = (d['slots'] as List)
            .map((x) => RoomSlot.fromJson(Map<String, dynamic>.from(x)))
            .toList();
        rooms = (d['rows'] as List)
            .map((x) => RoomAvailability.fromJson(Map<String, dynamic>.from(x)))
            .toList();
        loaded = true;
      });
    } catch (e) {
      if (mounted && id == revision) {
        setState(
          () => error = e is FormatException ? e.message : '全天空闲情况查询失败，请重试。',
        );
      }
    } finally {
      if (mounted && id == revision) setState(() => busy = false);
    }
  }

  String label(RoomUse use) => switch (use) {
    RoomUse.free => '空闲',
    RoomUse.busy => '占用',
    RoomUse.partial => '部分空闲',
    RoomUse.unknown => '未知',
  };
  String symbol(RoomUse use) => switch (use) {
    RoomUse.free => '空',
    RoomUse.busy => '占',
    RoomUse.partial => '半',
    RoomUse.unknown => '?',
  };
  Color fill(RoomUse use) {
    final c = Theme.of(context).colorScheme;
    return switch (use) {
      RoomUse.free => c.primaryContainer,
      RoomUse.busy => c.surfaceContainerHighest,
      RoomUse.partial => c.tertiaryContainer,
      RoomUse.unknown => c.errorContainer,
    };
  }

  Color ink(RoomUse use) {
    final c = Theme.of(context).colorScheme;
    return switch (use) {
      RoomUse.free => c.onPrimaryContainer,
      RoomUse.busy => c.onSurfaceVariant,
      RoomUse.partial => c.onTertiaryContainer,
      RoomUse.unknown => c.onErrorContainer,
    };
  }

  void details(
    RoomAvailability room,
    RoomSlot slot,
  ) => showModalBottomSheet<void>(
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
            Text(
              '${room.name} · ${slot.label}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('$dateCode · ${slot.from}–${slot.to}'),
            Text('${room.type} · ${creditNumber(room.seats)} 座'),
            for (final p in room.during(slot))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.state == RoomUse.free
                      ? Icons.check_circle_outline
                      : Icons.event_busy_outlined,
                ),
                title: Text('第 ${p.period} 节 · ${label(p.state)}'),
                subtitle: p.types.isEmpty
                    ? null
                    : Text(
                        '占用类型：${p.types.map((code) => const {'01': '教学', '02': '考试', '03': '调课（待审核）', '04': '借用', '05': '屏蔽', '06': '实验教学', '07': '实验借用'}[code] ?? '其他占用').join('、')}',
                      ),
              ),
            const Text('“部分空闲”表示该大节中只有部分节次空闲。实际使用请遵守学校管理安排。'),
          ],
        ),
      ),
    ),
  );
  Widget grid(List<RoomAvailability> shown) => LayoutBuilder(
    builder: (context, constraints) {
      const roomWidth = 90.0, gap = 6.0;
      final cell = ((constraints.maxWidth - roomWidth) / slots.length - gap)
          .clamp(38.0, 60.0);
      final width = roomWidth + (cell + gap) * slots.length;
      Widget row(Widget room, List<Widget> cells) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: roomWidth, child: room),
          for (final c in cells)
            Padding(
              padding: const EdgeInsets.only(right: gap),
              child: SizedBox(width: cell, child: c),
            ),
        ],
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              row(const Text('教室'), [
                for (final s in slots)
                  Tooltip(
                    message: '${s.from}–${s.to}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        s.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ]),
              for (final room in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: row(
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '${creditNumber(room.seats)} 座',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    [
                      for (final s in slots)
                        Builder(
                          builder: (context) {
                            final use = room.stateFor(s);
                            return Semantics(
                              button: true,
                              label:
                                  '${room.name}，${s.label}，${label(use)}，点击查看逐节详情',
                              child: Tooltip(
                                message:
                                    '${room.name} · ${s.label} · ${label(use)}',
                                child: Material(
                                  color: fill(use),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => details(room, s),
                                    child: SizedBox(
                                      height: cell,
                                      child: Center(
                                        child: Text(
                                          symbol(use),
                                          style: TextStyle(
                                            color: ink(use),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
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
          ),
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    final connected = widget.state.connectedAt != null;
    final shown = rooms
        .where(
          (r) =>
              search.isEmpty ||
              r.name.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('空闲教室'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: busy || !connected
                ? null
                : () => building == null ? initialize() : query(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () => launchSchoolBrowser(context, entry),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: PageBody(
        children: [
          if (!connected) ...[
            const EmptyCard(
              icon: Icons.account_circle_outlined,
              title: '请先连接校园账号',
              message: '登录后选择教学楼，查看全天教室空闲情况。',
            ),
            FilledButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LoginPage(state: widget.state),
                  ),
                );
                if (mounted) initialize();
              },
              child: const Text('连接校园账号'),
            ),
          ],
          if (connected) ...[
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final v = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 366),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 366)),
                      );
                      if (v != null && mounted) {
                        setState(() => date = v);
                        if (building != null) query();
                      }
                    },
              icon: const Icon(Icons.event),
              label: Text('${date.year}年${date.month}月${date.day}日'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('$building:${buildings.length}'),
              initialValue: building,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '教学楼',
                hintText: '请选择教学楼',
              ),
              items: [
                for (final b in buildings)
                  DropdownMenuItem(
                    value: '${b['JXLDM']}',
                    child: Text(
                      '${b['JXLMC']} · ${b['XXXQDM_DISPLAY'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy || buildings.isEmpty
                  ? null
                  : (v) {
                      setState(() => building = v);
                      query();
                    },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final use in RoomUse.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: fill(use),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          symbol(use),
                          style: TextStyle(color: ink(use), fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(label(use)),
                    ],
                  ),
              ],
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (buildings.isEmpty && !busy)
              TextButton(onPressed: initialize, child: const Text('重新加载教学楼')),
            if (!busy && building == null && buildings.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('选择教学楼后显示该楼全天所有教室的空闲情况。'),
              ),
            if (loaded) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: '搜索教室名称',
                  ),
                  onChanged: (v) => setState(() => search = v.trim()),
                ),
              ),
              SectionTitle('全天空闲情况 · ${shown.length} 间教室'),
              if (shown.isEmpty)
                const Text('该教学楼没有匹配的教室。')
              else if (slots.isNotEmpty)
                grid(shown),
            ],
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    OfficialAcademicPage(entry: entry, title: '空闲教室'),
              ),
            ),
            icon: const Icon(Icons.language),
            label: const Text('打开应用内原网页 / 完成额外认证'),
          ),
        ],
      ),
    );
  }
}
