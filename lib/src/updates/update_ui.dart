import 'dart:async';
import 'dart:io';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_miuix/miuix.dart';
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
  final miuix = UiStyleScope.of(context) == UiStyle.miuix;
  if (miuix) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 320),
        reverseDuration: Duration(milliseconds: 240),
      ),
      builder: (_) => _UpdateDialog(
        updates: updates,
        release: release,
        miuix: true,
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(
        updates: updates,
        release: release,
        miuix: false,
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.updates,
    required this.release,
    required this.miuix,
  });
  final UpdateController updates;
  final AppRelease release;
  final bool miuix;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  late final download = widget.updates.downloader();
  bool busy = false;
  int received = 0;
  int? total;
  File? file;
  String? message;

  @override
  void dispose() {
    download.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final asset = widget.release.assetFor(widget.updates.runtime);
    if (asset == null || busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      file ??= await download.download(
        asset,
        onProgress: (bytes, length) {
          if (mounted) {
            setState(() {
              received = bytes;
              total = length;
            });
          }
        },
      );
      if (!mounted) return;
      if (widget.updates.runtime.platform == TargetPlatform.android) {
        final result = await widget.updates.installer(file!);
        message = result == 'permissionRequired'
            ? '请允许此应用安装更新，返回后将自动请求安装；也可点击"安装"重试。'
            : '已请求系统安装，请在系统界面确认。';
      } else {
        message = '下载完成：${file!.path}';
      }
    } catch (e) {
      message = e is FormatException
          ? e.message
          : '下载或打开安装包失败，请检查网络、存储空间及系统权限后重试。';
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> _primaryAction() async {
    final android = widget.updates.runtime.platform == TargetPlatform.android;
    if (file != null && !android) {
      try {
        if (!await launchUrl(file!.uri)) {
          throw const FormatException('无法打开文件');
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            message = '无法打开文件，请前往下载目录手动打开：${file!.path}';
          });
        }
      }
    } else {
      await start();
    }
  }

  String get _primaryLabel {
    if (busy) return '下载中';
    if (file == null) return '下载';
    return widget.updates.runtime.platform == TargetPlatform.android
        ? '安装'
        : '打开文件';
  }

  String get _secondaryLabel {
    if (busy) return '取消下载';
    return file == null ? '取消' : '关闭';
  }

  /// 更新日志的 Markdown 样式，与公告页保持一致的行高与标题层级。
  MarkdownStyleSheet _notesStyle(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      height: 1.6,
      color: colors.onSurface,
    );
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      a: body?.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        backgroundColor: colors.surfaceContainerHighest,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _releaseNotes(BuildContext context) => MarkdownBody(
    data: widget.release.notes,
    selectable: true,
    styleSheet: _notesStyle(context),
  );

  /// 下载进度与结果消息，两种布局共用。
  Widget _progressSection() {
    if (!busy && message == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: total == null
                ? null
                : (received / total!).clamp(0, 1),
          ),
          const SizedBox(height: 8),
          Text(
            total == null
                ? '已下载 ${(received / 1048576).toStringAsFixed(1)} MB'
                : '${(received / total! * 100).toStringAsFixed(0)}% · ${(received / 1048576).toStringAsFixed(1)} / ${(total! / 1048576).toStringAsFixed(1)} MB',
          ),
        ],
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.miuix ? _buildMiuix(context) : _buildMaterial(context);

  // ── MD3：标准 AlertDialog ──────────────────────────────────
  Widget _buildMaterial(BuildContext context) {
    final asset = widget.release.assetFor(widget.updates.runtime);
    return AlertDialog(
      title: Text('发现新版本 ${widget.release.tag}'),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .48,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '下载源：${widget.release.source.label}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                _releaseNotes(context),
                const SizedBox(height: 16),
                if (asset == null)
                  const Text('该版本未提供适合当前平台与架构的安装包。'),
                if (asset != null) Text(asset.name),
                _progressSection(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(_secondaryLabel),
        ),
        FilledButton(
          onPressed: asset == null || busy ? null : _primaryAction,
          child: Text(_primaryLabel),
        ),
      ],
    );
  }

  // ── MIUIX：底部表 + squircle 容器 + 两个大按钮 ────────────
  Widget _buildMiuix(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final theme = MiuixTheme.of(context);
    final asset = widget.release.assetFor(widget.updates.runtime);
    return AnimatedPadding(
      padding: MediaQuery.of(context).viewInsets,
      duration: const Duration(milliseconds: 200),
      // 下载进行时不允许下滑或点击遮罩关闭，避免中断。
      child: PopScope(
        canPop: !busy,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: ShapeDecoration(
            color: colors.surfaceContainer,
            shape: MiuixSquircleBorder(cornerRadius: 28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixText(
                  '发现新版本 ${widget.release.tag}',
                  style: theme.textStyles.title2,
                  color: colors.onSurfaceContainer,
                ),
                const SizedBox(height: 8),
                MiuixText(
                  '下载源：${widget.release.source.label}',
                  style: theme.textStyles.body2,
                  color: colors.onSurfaceContainerVariant,
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .40,
                  ),
                  child: SingleChildScrollView(
                    child: _releaseNotes(context),
                  ),
                ),
                const SizedBox(height: 16),
                if (asset == null)
                  MiuixText(
                    '该版本未提供适合当前平台与架构的安装包。',
                    style: theme.textStyles.body2,
                    color: colors.onSurfaceContainerVariant,
                  )
                else
                  MiuixText(
                    asset.name,
                    style: theme.textStyles.body2,
                    color: colors.onSurfaceContainerVariant,
                  ),
                _progressSection(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: MiuixTextButton(
                        _secondaryLabel,
                        onPressed: busy ? null : () => Navigator.pop(context),
                        colors: MiuixButtonColors(
                          color: colors.surfaceContainerHighest,
                          disabledColor: colors.surfaceContainerHighest,
                          contentColor: colors.onSurfaceContainer,
                          disabledContentColor: colors.onSurfaceContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MiuixTextButton(
                        _primaryLabel,
                        onPressed:
                            asset == null || busy ? null : _primaryAction,
                        colors: MiuixButtonColors(
                          color: colors.primary,
                          disabledColor: colors.primary,
                          contentColor: colors.onPrimary,
                          disabledContentColor: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
                  subtitle: Text(
                    u.source == UpdateSource.github
                        ? '已内置 GitHub 镜像加速，自动使用'
                        : '选择应用更新的下载仓库',
                  ),
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
