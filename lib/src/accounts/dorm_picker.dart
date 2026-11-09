import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets.dart';
import 'accounts.dart';

Future<void> openDormPicker(BuildContext context, AppState state) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => DormPickerPage(state: state)),
    );

class DormPickerPage extends StatefulWidget {
  const DormPickerPage({super.key, required this.state});
  final AppState state;
  @override
  State<DormPickerPage> createState() => _DormPickerPageState();
}

class _DormPickerPageState extends State<DormPickerPage> {
  final loading = DormCatalog.load();
  DormService? service;
  List<DormNode> path = [];
  bool initialized = false, saving = false;
  String? error;
  Future<void> save() async {
    if (service == null || path.length != service!.codes.length || saving) {
      return;
    }
    setState(() => saving = true);
    final selected = DormSelection(service!.id, service!.label, {
      for (int i = 0; i < path.length; i++) service!.codes[i]: path[i].value,
    }, path.map((n) => n.name).toList());
    try {
      await widget.state.setDorm(selected);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => error = '未能保存宿舍，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> choose(int level, List<DormNode> options) async {
    final selected = await showModalBottomSheet<DormNode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _OptionSheet(title: service!.levelNames[level], options: options),
    );
    if (selected != null && mounted) {
      setState(() => path = [...path.take(level), selected]);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('选择实际宿舍')),
    body: FutureBuilder<DormCatalog>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const PageBody(
            children: [
              EmptyCard(
                icon: Icons.error_outline,
                title: '目录加载失败',
                message: '请返回后重试。',
              ),
            ],
          );
        }
        final catalog = snapshot.data;
        if (catalog == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!initialized) {
          initialized = true;
          final old = widget.state.dorm;
          if (old != null && catalog.contains(old)) {
            service = catalog.services.firstWhere((s) => s.id == old.serviceId);
            var nodes = service!.nodes;
            for (final code in service!.codes) {
              final n = nodes.firstWhere((n) => n.value == old.fields[code]);
              path.add(n);
              nodes = n.children;
            }
          }
        }
        var nodes = service?.nodes ?? <DormNode>[];
        final levels = <Widget>[];
        if (service != null) {
          for (int i = 0; i < service!.codes.length; i++) {
            final options = nodes;
            final selected = path.length > i ? path[i] : null;
            levels.add(
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  child: ListTile(
                    title: Text(service!.levelNames[i]),
                    subtitle: Text(
                      selected?.name ?? (options.isEmpty ? '请先选择上一级' : '点击选择'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: options.isEmpty || saving
                        ? null
                        : () => choose(i, options),
                  ),
                ),
              ),
            );
            nodes = selected?.children ?? [];
          }
        }
        return PageBody(
          children: [
            const SizedBox(height: 8),
            Text(
              '先选服务范围，再选园区、楼栋与房间。沁园 42/43 使用独立入口，请勿与本部同名楼栋混选。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SectionTitle('电费服务范围'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in catalog.services)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: service?.id == s.id,
                    onSelected: saving
                        ? null
                        : (_) => setState(() {
                            service = s;
                            path = [];
                          }),
                  ),
              ],
            ),
            ...levels,
            const SizedBox(height: 24),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton.icon(
              onPressed:
                  service != null &&
                      path.length == service!.codes.length &&
                      !saving
                  ? save
                  : null,
              icon: const Icon(Icons.check),
              label: Text(saving ? '正在保存…' : '保存宿舍'),
            ),
            if (widget.state.dorm != null)
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        try {
                          await widget.state.setDorm(null);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (mounted) setState(() => error = '未能清除，请重试。');
                        }
                      },
                child: const Text('清除已选宿舍'),
              ),
            const SizedBox(height: 20),
            Text(
              '目录更新于 ${catalog.updated}。如房间不在列表中，请先检查服务范围，勿选择相近房号代替。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    ),
  );
}

class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.title, required this.options});
  final String title;
  final List<DormNode> options;
  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where((n) => n.name.contains(search.trim()))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择${widget.title}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: '搜索${widget.title}',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (s) => setState(() => search = s),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: options.isEmpty
                    ? const Center(child: Text('没有匹配项，请检查搜索内容。'))
                    : ListView.builder(
                        itemCount: options.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(options[index].name),
                          onTap: () => Navigator.pop(context, options[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
