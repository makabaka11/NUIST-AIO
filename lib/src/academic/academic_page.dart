import 'package:flutter/material.dart';

import '../app_state.dart';
import '../auth/login_page.dart';
import '../schedule/schedule.dart';
import '../widgets.dart';
import 'academic.dart';
import 'official_page.dart';
import 'rooms_page.dart';

void openAcademic(
  BuildContext context,
  AppState state,
  AcademicFeature feature,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => AcademicPage(state: state, feature: feature),
  ),
);

class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key, required this.state, required this.feature});
  final AppState state;
  final AcademicFeature feature;
  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> {
  bool busy = false;
  String? error, term, plan;
  List<Semester> terms = [];
  List<Map<String, dynamic>> plans = [], rows = [];
  Map<String, dynamic>? result;
  String keyword = '', gradeTerm = '';
  int request = 0;
  late int generation;
  AcademicFeature get feature => widget.feature;
  List<Map<String, dynamic>> maps(Object? value) => (value as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map))
      .toList();
  @override
  void initState() {
    super.initState();
    generation = widget.state.sessionGeneration;
    widget.state.addListener(accountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && feature != AcademicFeature.rooms) load(initialize: true);
    });
  }

  void accountChanged() {
    if (generation == widget.state.sessionGeneration) return;
    generation = widget.state.sessionGeneration;
    request++;
    setState(() {
      rows = [];
      plans = [];
      terms = [];
      result = null;
      term = null;
      plan = null;
      busy = false;
      error = '账号已变化，请重新查询。';
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    request++;
    super.dispose();
  }

  Future<void> load({bool initialize = false}) async {
    if (busy || widget.state.connectedAt == null) return;
    final id = ++request, account = widget.state.sessionGeneration;
    setState(() {
      busy = true;
      error = null;
      rows = [];
      result = null;
    });
    bool valid() =>
        mounted && request == id && widget.state.sessionGeneration == account;
    try {
      final session = widget.state.teachingSession;
      if (!session.available) {
        throw const FormatException('当前环境不支持校园 WebView，请使用右上角浏览器入口。');
      }
      Map<String, dynamic> data;
      if (feature == AcademicFeature.exams && (initialize || terms.isEmpty)) {
        final d = await session.query('semesters', {});
        if (!valid()) return;
        terms = maps(d['terms']).map(Semester.fromJson).toList();
        term = terms.any((s) => s.code == d['current'])
            ? '${d['current']}'
            : terms.firstOrNull?.code;
      }
      if (feature == AcademicFeature.credits && (initialize || plans.isEmpty)) {
        final d = await session.query('creditPlans', {});
        if (!valid()) return;
        plans = maps(d['plans']);
        plan = plans.firstOrNull?['value']?.toString();
        if (plan == null) throw const FormatException('学校尚未返回培养方案，请查看原网页。');
      }
      data = await session.query(feature.id, {
        'params': {'term': term, 'plan': plan},
      });
      if (!valid()) return;
      if (data['ok'] != true) {
        throw FormatException('${data['error'] ?? '教务查询失败，请重试。'}');
      }
      setState(() {
        result = data;
        rows = maps(data['rows']);
      });
    } catch (e) {
      if (valid()) {
        setState(
          () => error = e is FormatException ? e.message : '教务查询未完成，请重试或打开原网页。',
        );
      }
    } finally {
      if (valid()) setState(() => busy = false);
    }
  }

  Widget dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => SizedBox(
    width: 240,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value:${options.keys.join()}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(
                e.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: busy
          ? null
          : (v) {
              if (v != null) change(v);
            },
    ),
  );
  Widget summary(String label, Object? value) =>
      Chip(label: Text('$label ${creditNumber(value)}'));
  Widget record(
    String title,
    String subtitle, {
    String? trailing,
    List<String> details = const [],
  }) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ExpansionTile(
      title: Text(title.isEmpty ? '未命名' : title),
      subtitle: Text(subtitle),
      trailing: trailing == null
          ? null
          : Text(trailing, style: Theme.of(context).textTheme.titleMedium),
      children: [
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(alignment: Alignment.centerLeft, child: Text(detail)),
          ),
      ],
    ),
  );
  Widget creditTree(Map<String, dynamic> node, [int depth = 0]) {
    final required = academicNumber(node['creditsRequired']),
        earned = academicNumber(node['creditsEarned']);
    final children = maps(node['children']);
    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 12, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${node['name'] ?? '学分要求'} · 已获 ${creditNumber(earned)} / 要求 ${creditNumber(required)} 学分',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (required != null && required > 0 && earned != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                value: (earned / required).clamp(0, 1),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          if (children.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看分类要求'),
              children: children.map((x) => creditTree(x, depth + 1)).toList(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (feature == AcademicFeature.rooms) {
      return RoomAvailabilityPage(state: widget.state);
    }
    final connected = widget.state.connectedAt != null;
    var shown = rows
        .where(
          (r) =>
              (gradeTerm.isEmpty || r['XNXQDM'] == gradeTerm) &&
              (keyword.isEmpty ||
                  [
                    'KCM',
                    'KCH',
                    'JASMC',
                    'JXLDM_DISPLAY',
                    'XXXQDM_DISPLAY',
                  ].any(
                    (k) => academicText(
                      r,
                      k,
                    ).toLowerCase().contains(keyword.toLowerCase()),
                  )),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(feature.label),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: busy || !connected ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () => launchSchoolBrowser(context, feature.entry),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: PageBody(
        children: [
          if (!connected)
            EmptyCard(
              icon: Icons.account_circle_outlined,
              title: '请先连接校园账号',
              message: '登录后可复用教务会话查询${feature.label}。',
            ),
          if (!connected)
            FilledButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LoginPage(state: widget.state),
                  ),
                );
                if (mounted && feature != AcademicFeature.rooms) {
                  load(initialize: true);
                }
              },
              child: const Text('连接校园账号'),
            ),
          if (connected) ...[
            if (feature == AcademicFeature.exams && terms.isNotEmpty)
              dropdown('学年学期', term!, {for (final t in terms) t.code: t.name}, (
                v,
              ) {
                setState(() => term = v);
                load();
              }),
            if (feature == AcademicFeature.credits && plans.isNotEmpty)
              dropdown(
                '培养方案',
                plan!,
                {for (final p in plans) '${p['value']}': '${p['label']}'},
                (v) {
                  setState(() => plan = v);
                  load();
                },
              ),
            if (feature == AcademicFeature.grades && rows.isNotEmpty) ...[
              dropdown('学年学期', gradeTerm, {
                '': '全部学期',
                for (final r in rows)
                  if (r['XNXQDM'] != null)
                    '${r['XNXQDM']}': '${r['XNXQDM_DISPLAY'] ?? r['XNXQDM']}',
              }, (v) => setState(() => gradeTerm = v)),
              const SizedBox(height: 12),
              const Text('显示教务有效成绩及每门课程绩点。学校统计 GPA 可在“学业监测”的学期统计中查看。'),
            ],
            if (feature == AcademicFeature.grades)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: '搜索课程名 / 课程号',
                  ),
                  onChanged: (v) => setState(() => keyword = v.trim()),
                ),
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
            if (!busy && result != null) ...[
              if (feature == AcademicFeature.credits &&
                  result!['report'] is Map) ...[
                const SectionTitle('学分完成情况'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    summary('方案内已获', result!['completed']),
                    summary('方案外已获', result!['outside']),
                  ],
                ),
                const SizedBox(height: 12),
                creditTree(Map<String, dynamic>.from(result!['report'])),
                Text('学校计算时间：${result!['calculatedTime'] ?? '未提供'}'),
                const SectionTitle('学期学分与 GPA'),
              ] else if (result!.containsKey('rows'))
                SectionTitle('查询结果 · ${shown.length} 条'),
              if (result!.containsKey('rows') && shown.isEmpty)
                const EmptyCard(
                  icon: Icons.inbox_outlined,
                  title: '暂无查询结果',
                  message: '可调整查询条件或通过右上角核对原网页。',
                ),
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: switch (feature) {
                    AcademicFeature.rooms => const SizedBox.shrink(),
                    AcademicFeature.grades => record(
                      academicText(r, 'KCM'),
                      '${academicText(r, 'XNXQDM_DISPLAY')} · ${academicText(r, 'XF')} 学分\n绩点 ${creditNumber(r['XFJD'])}',
                      trailing: academicText(r, 'XSZCJMC').isNotEmpty
                          ? academicText(r, 'XSZCJMC')
                          : academicText(r, 'ZCJ'),
                      details: [
                        '课程号：${academicText(r, 'KCH')}',
                        '课程性质：${academicText(r, 'KCXZDM_DISPLAY')}',
                        '修读：${academicText(r, 'CXCKDM_DISPLAY')} · ${academicText(r, 'SFJG_DISPLAY')}',
                        '考试日期：${academicText(r, 'SJKSRQ')}',
                      ],
                    ),
                    AcademicFeature.exams => record(
                      academicText(r, 'KCM'),
                      '${academicText(r, 'KSRQ')} · ${academicText(r, 'KSSJMS')}\n${academicText(r, 'XXXQMC')} ${academicText(r, 'JXLMC')} ${academicText(r, 'JASMC')}',
                      details: [
                        '考试：${academicText(r, 'KSMC')}',
                        '座位号：${academicText(r, 'ZWH')}',
                        '${academicText(r, 'SFAPSJ_DISPLAY')} · ${academicText(r, 'BZ')}',
                      ],
                    ),
                    AcademicFeature.credits => record(
                      academicText(r, 'XNXQDM_DISPLAY'),
                      '已修 ${creditNumber(r['YXXF'])} · 已获 ${creditNumber(r['YHXF'])} 学分',
                      details: [
                        '学期 GPA：${creditNumber(r['XQGPA'])} · 累计 GPA：${creditNumber(r['LJGPA'])}',
                        '未通过 ${creditNumber(r['BJGXF'])} · 未录成绩 ${creditNumber(r['WLCJXF'])} 学分',
                      ],
                    ),
                  },
                ),
            ],
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => OfficialAcademicPage(
                    entry: feature.entry,
                    title: feature.label,
                  ),
                ),
              );
              if (mounted && connected) load(initialize: true);
            },
            icon: const Icon(Icons.language),
            label: const Text('打开应用内原网页 / 完成额外认证'),
          ),
          const Text('右上角可使用系统浏览器打开学校页面；系统浏览器与本应用的登录会话相互独立。'),
        ],
      ),
    );
  }
}
