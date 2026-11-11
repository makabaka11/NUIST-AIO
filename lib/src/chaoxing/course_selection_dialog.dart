import 'dart:async';

import '../campus_ui.dart';
import 'chaoxing.dart';
import 'course_selection.dart';

final chaoxingSelectionRoutes = RouteObserver<ModalRoute<dynamic>>();

/// Lives on the home route, so automatic login completion cannot accidentally
/// pop a confirmation dialog while closing its official WebView route.
class ChaoxingSelectionHost extends StatefulWidget {
  const ChaoxingSelectionHost({
    super.key,
    required this.repository,
    required this.child,
  });
  final ChaoxingRepository repository;
  final Widget child;
  @override
  State<ChaoxingSelectionHost> createState() => _ChaoxingSelectionHostState();
}

class _ChaoxingSelectionHostState extends State<ChaoxingSelectionHost>
    with RouteAware {
  ModalRoute<dynamic>? _home;
  DialogRoute<Set<String>>? _dialog;
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(ChaoxingSelectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_changed);
      widget.repository.addListener(_changed);
      _changed();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_home != route) {
      chaoxingSelectionRoutes.unsubscribe(this);
      _home = route;
      if (route != null) chaoxingSelectionRoutes.subscribe(this, route);
    }
    _changed();
  }

  @override
  void didPopNext() => _changed();

  void _changed() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final pending = widget.repository.pendingSelection;
      final dialog = _dialog;
      if (pending == null && dialog != null && dialog.isActive) {
        dialog.navigator?.removeRoute(dialog);
      } else if (pending != null &&
          dialog == null &&
          _home?.isCurrent == true) {
        unawaited(_present(pending));
      }
    });
  }

  Future<void> _present(ChaoxingCourseSelection pending) async {
    final repository = widget.repository;
    final dialog = DialogRoute<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChaoxingSelectionDialog(
        selection: pending,
        selected: repository.selectedCourseKeys,
      ),
    );
    _dialog = dialog;
    final chosen = await Navigator.of(context).push(dialog);
    _dialog = null;
    if (mounted && identical(repository.pendingSelection, pending)) {
      repository.confirmCourseSelection(chosen);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_changed);
    chaoxingSelectionRoutes.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ChaoxingSelectionDialog extends StatefulWidget {
  const ChaoxingSelectionDialog({
    super.key,
    required this.selection,
    required this.selected,
  });
  final ChaoxingCourseSelection selection;
  final Set<String> selected;
  @override
  State<ChaoxingSelectionDialog> createState() =>
      _ChaoxingSelectionDialogState();
}

class _ChaoxingSelectionDialogState extends State<ChaoxingSelectionDialog> {
  late final selected = widget.selected.intersection(widget.selection.keys);
  @override
  Widget build(BuildContext context) {
    final proposal = widget.selection, colors = Theme.of(context).colorScheme;
    final options = [...proposal.options]
      ..sort(
        (a, b) => a.automatic == b.automatic
            ? a.name.compareTo(b.name)
            : a.automatic
            ? -1
            : 1,
      );
    final mismatch = selected.length != proposal.teaching.length;
    return AlertDialog(
      title: const Text('确认学习通课程'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .58,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(proposal.term),
                Text(
                  '教务 ${proposal.teaching.length} 门 · 学习通可选 ${proposal.options.length} 门',
                ),
                Text(
                  '自动匹配 ${proposal.automatic.length} 门 · 已勾选 ${selected.length} 门',
                  style: TextStyle(
                    color: mismatch ? colors.error : colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text('仅扫描勾选的课程。请逐门核对，未匹配课程可手动补选；已排除选课指导。'),
                if (mismatch)
                  Text(
                    '勾选数量与教务不一致；两端课程可能并非一一对应，请核对后确认。',
                    style: TextStyle(color: colors.error),
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('查看教务本学期课程与教师'),
                  children: [
                    for (final course in proposal.teaching)
                      ListTile(
                        title: Text(course.name),
                        subtitle: Text(
                          course.teacher.isEmpty ? '教务未提供教师' : course.teacher,
                        ),
                      ),
                  ],
                ),
                for (final course in options)
                  Semantics(
                    checked: selected.contains(course.key),
                    child: ListTile(
                      title: Text(course.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (course.alias.isNotEmpty &&
                              course.alias != course.name)
                            Text(course.alias),
                          Text(
                            course.teacher.isNotEmpty
                                ? '学习通教师：${course.teacher}'
                                : course.referenceTeachers.isNotEmpty
                                ? '教务参考教师：${course.referenceTeachers}（学习通未提供）'
                                : '任课老师：未提供',
                          ),
                          Text(
                            course.automatic ? '自动匹配' : '未自动匹配',
                            style: TextStyle(
                              color: course.automatic
                                  ? colors.primary
                                  : colors.tertiary,
                            ),
                          ),
                        ],
                      ),
                      trailing: Icon(
                        selected.contains(course.key)
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: selected.contains(course.key)
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      onTap: () => setState(() {
                        if (!selected.add(course.key)) {
                          selected.remove(course.key);
                        }
                      }),
                    ),
                  ),
                if (options.isEmpty) const Text('没有可选择的学习通课程。'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            selected
              ..clear()
              ..addAll(proposal.automatic);
          }),
          child: const Text('恢复自动匹配'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected.toSet()),
          child: Text('确认并扫描 ${selected.length} 门'),
        ),
      ],
    );
  }
}
