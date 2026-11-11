import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../campus_ui.dart';
import '../app_state.dart' show UiStyle;
import '../ui_style_scope.dart';
import '../widgets.dart';
import 'update_model.dart';
import 'update_service.dart';

final updateRouteObserver = RouteObserver<ModalRoute<dynamic>>();

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateController updates,
  AppRelease release,
) async {
  updates.markPresented(release);
  final package = release.packageFor(updates.runtime);
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('发现新版本 ${release.tag}'),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialog).height * .48,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '下载源：${release.source.label}',
                  style: Theme.of(dialog).textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                SelectableText(release.notes),
                if (package == null) ...[
                  const SizedBox(height: 16),
                  const Text('该版本未提供当前平台的安装包，下载按钮将打开版本发布页。'),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              if (await launchUrl(
                package ?? release.page,
                mode: LaunchMode.externalApplication,
              )) {
                if (dialog.mounted) Navigator.pop(dialog);
                return;
              }
            } catch (_) {}
            if (dialog.mounted) {
              showCampusSnackBar(
                dialog,
                const SnackBar(content: Text('无法打开下载链接，请检查系统浏览器。')),
              );
            }
          },
          child: const Text('下载'),
        ),
      ],
    ),
  );
}

class UpdateSettingsPage extends StatefulWidget {
  const UpdateSettingsPage({super.key, required this.updates});
  final UpdateController updates;
  @override
  State<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends State<UpdateSettingsPage> {
  bool loadingVersion = true;
  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      await widget.updates.loadInstalled();
    } catch (_) {
    } finally {
      if (mounted) setState(() => loadingVersion = false);
    }
  }

  Future<void> check() async {
    final result = await widget.updates.check();
    if (mounted && result != null && result.source == widget.updates.source) {
      await showUpdateDialog(context, widget.updates, result);
    }
  }

  Future<void> save(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showCampusSnackBar(
          context,
          const SnackBar(content: Text('设置未能保存，请稍后重试。')),
        );
      }
    }
  }

  Future<void> source() async {
    final selected = await showDialog<UpdateSource>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('下载源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in UpdateSource.values)
              ListTile(
                title: Text(s.label),
                trailing: s == widget.updates.source
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(dialog, s),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected != null) await save(() => widget.updates.setSource(selected));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.updates,
    builder: (context, _) {
      final u = widget.updates,
          miuix = UiStyleScope.of(context) == UiStyle.miuix;
      return Scaffold(
        appBar: AppBar(title: miuix ? null : const Text('更新设置')),
        body: PageBody(
          children: [
            if (miuix)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 20,
                ),
                child: Text(
                  '更新设置',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
            PreferenceGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前版本',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          u.current?.label ??
                              (loadingVersion ? '正在读取版本…' : '版本信息暂不可用'),
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('检查更新'),
                  subtitle: Text(u.statusText),
                  trailing: u.status == UpdateCheckStatus.checking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: u.status == UpdateCheckStatus.checking ? null : check,
                ),
              ],
            ),
            const SectionTitle('更多设置'),
            PreferenceGroup(
              children: [
                ListTile(
                  title: const Text('下载源'),
                  subtitle: const Text('选择应用更新的下载仓库'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(u.source.label),
                      const SizedBox(width: 4),
                      const Icon(Icons.unfold_more),
                    ],
                  ),
                  onTap: source,
                ),
              ],
            ),
            const SizedBox(height: 16),
            PreferenceGroup(
              children: [
                PreferenceSwitchRow(
                  title: '自动检查更新',
                  subtitle: '启动时自动检查是否有新版本',
                  value: u.autoCheck,
                  onChanged: (v) => save(() => u.setAutomatic(v)),
                ),
                PreferenceSwitchRow(
                  title: '更新提醒',
                  subtitle: '发现新版本时弹出提醒',
                  value: u.remind,
                  onChanged: (v) => save(() => u.setReminder(v)),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Starts only after the first frame, within the application's themed home
/// route. Route awareness prevents a late result interrupting official login.
class UpdateStartupGate extends StatefulWidget {
  const UpdateStartupGate({
    super.key,
    required this.updates,
    required this.child,
  });
  final UpdateController updates;
  final Widget child;
  @override
  State<UpdateStartupGate> createState() => _UpdateStartupGateState();
}

class _UpdateStartupGateState extends State<UpdateStartupGate>
    with RouteAware, WidgetsBindingObserver {
  AppRelease? pending;
  ModalRoute<dynamic>? route;
  bool showing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.updates.claimStartup()) unawaited(_check());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context);
    if (current != route) {
      if (route != null) updateRouteObserver.unsubscribe(this);
      route = current;
      if (current != null) updateRouteObserver.subscribe(this, current);
    }
  }

  Future<void> _check() async {
    final result = await widget.updates.check();
    if (!mounted) return;
    pending = result;
    _maybeShow();
  }

  void _maybeShow() {
    final release = pending, u = widget.updates;
    if (!mounted || showing || release == null) return;
    if (!u.autoCheck ||
        !u.remind ||
        release.source != u.source ||
        u.wasPresented(release)) {
      pending = null;
      return;
    }
    if (route?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive) {
      return;
    }
    pending = null;
    showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (route?.isCurrent != true) {
        pending = release;
        showing = false;
        return;
      }
      if (u.autoCheck &&
          u.remind &&
          u.source == release.source &&
          !u.wasPresented(release)) {
        await showUpdateDialog(context, u, release);
      }
      showing = false;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didPopNext() => _maybeShow();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeShow();
  }

  @override
  void dispose() {
    updateRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
