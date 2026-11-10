import 'dart:async';

import '../campus_ui.dart';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../status_tag.dart';
import '../services/site_registry.dart';
import '../webview_page_lifecycle.dart';
import 'chaoxing.dart';

Future<void> openChaoxingLogin(BuildContext context, AppState state) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ChaoxingLoginPage(state: state)),
    );

class ChaoxingAccountTile extends StatelessWidget {
  const ChaoxingAccountTile({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.chaoxing,
    builder: (context, _) => ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: const Text('学习通登录'),
      subtitle: Text(
        state.chaoxing.verified ? '课程接口已验证' : '待接入验证 · 在学习通官方页面登录',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openChaoxingLogin(context, state),
    ),
  );
}

class ChaoxingLoginPage extends StatefulWidget {
  const ChaoxingLoginPage({super.key, required this.state});
  final AppState state;
  @override
  State<ChaoxingLoginPage> createState() => _ChaoxingLoginPageState();
}

class _ChaoxingLoginPageState extends State<ChaoxingLoginPage>
    with WebViewPageLifecycle<ChaoxingLoginPage> {
  late final repository = widget.state.chaoxing;
  late int generation;
  bool resetting = false;
  bool verifying = false, automaticProbeAttempted = false;
  String? error;
  InAppWebViewController? loginController;
  @override
  void initState() {
    super.initState();
    generation = widget.state.sessionGeneration;
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (generation != widget.state.sessionGeneration) {
      closeWebViewPage();
    }
  }

  Future<void> connect({bool automatic = false}) async {
    if (!mounted ||
        verifying ||
        repository.busy ||
        (automatic && automaticProbeAttempted)) {
      return;
    }
    if (automatic) automaticProbeAttempted = true;
    setState(() {
      verifying = true;
      error = null;
    });
    final connected = await widget.state.connectChaoxing();
    if (!mounted || generation != widget.state.sessionGeneration) return;
    setState(() => verifying = false);
    if (connected) await closeWebViewPage();
  }

  Future<void> reset() async {
    // Only an explicit account change clears the current native session.
    setState(() {
      resetting = true;
      automaticProbeAttempted = false;
      error = null;
    });
    try {
      await repository.close(clearCookies: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          resetting = false;
          error = '学习通会话清理失败，请重试切换账号。';
        });
      }
      return;
    }
    if (mounted) setState(() => resetting = false);
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    return loginContent(context);
  }

  Widget loginContent(BuildContext context) => guardWebViewPage(
    ListenableBuilder(
      listenable: repository,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('连接学习通'),
          actions: [
            if (!repository.verified && repository.supported)
              IconButton(
                tooltip: '重新加载官方页面',
                onPressed: repository.busy
                    ? null
                    : () async {
                        setState(() => error = null);
                        await loginController?.loadUrl(
                          urlRequest: URLRequest(
                            url: WebUri(
                              SchoolSites.get(SchoolSiteId.chaoxing).authEntry
                                  .toString(),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.refresh),
              ),
            if (repository.verified)
              TextButton(onPressed: closeWebViewPage, child: const Text('完成')),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '学习通官方页面 · passport2.chaoxing.com\n密码与验证码仅在网页输入。登录后自动验证并刷新本学期作业和考试；也可以点击下方按钮继续。',
                  ),
                  if (repository.notice != null)
                    Text(
                      repository.notice!,
                      style: TextStyle(
                        color: repository.noticeIsError
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed:
                            repository.busy ||
                                resetting ||
                                !repository.supported
                            ? null
                            : () => connect(),
                        child: LoadingText(
                          repository.busy ? '正在验证…' : '我已登录，验证会话',
                          loading: repository.busy,
                        ),
                      ),
                      if (repository.verified || error != null)
                        TextButton(
                          onPressed: repository.busy || resetting
                              ? null
                              : reset,
                          child: const Text('重新登录 / 切换账号'),
                        ),
                      TextButton(
                        onPressed: repository.busy
                            ? null
                            : () async {
                                await repository.close(clearCookies: true);
                                if (mounted) await closeWebViewPage();
                              },
                        child: const Text('移除学习通会话'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: repository.verified
                  ? Center(
                      child: LoadingText(
                        repository.busy ? '学习通会话已验证，正在自动刷新本学期项目。' : '学习通会话已验证。',
                        loading: repository.busy,
                      ),
                    )
                  : !repository.supported
                  ? const Center(child: Text('当前平台不支持内嵌学习通登录。'))
                  : resetting
                  ? const Center(child: CircularProgressIndicator())
                  : webViewVisible
                  ? InAppWebView(
                      onWebViewCreated: (controller) =>
                          loginController = controller,
                      initialUrlRequest: URLRequest(
                        url: WebUri(
                          SchoolSites.get(SchoolSiteId.chaoxing).authEntry
                              .toString(),
                        ),
                      ),
                      initialSettings: InAppWebViewSettings(
                        useShouldOverrideUrlLoading: true,
                        isInspectable: false,
                        javaScriptCanOpenWindowsAutomatically: false,
                      ),
                      shouldOverrideUrlLoading: (controller, action) async {
                        final uri = Uri.tryParse(action.request.url.toString());
                        if (chaoxingNavigation(uri)) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        final secure = chaoxingHttpsUpgrade(uri);
                        if (secure != null && action.isForMainFrame != false) {
                          if (mounted) setState(() => error = null);
                          await controller.loadUrl(
                            urlRequest: URLRequest(
                              url: WebUri(secure.toString()),
                            ),
                          );
                          return NavigationActionPolicy.CANCEL;
                        }
                        if (mounted && action.isForMainFrame != false) {
                          setState(() => error = '登录跳转暂未支持，请稍后重试。');
                        }
                        return NavigationActionPolicy.CANCEL;
                      },
                      onLoadStop: (_, url) {
                        if ({
                          'i.mooc.chaoxing.com',
                          'i.chaoxing.com',
                        }.contains(url?.host)) {
                          unawaited(connect(automatic: true));
                        }
                      },
                      onReceivedError: (_, r, failure) {
                        if (failure.type == WebResourceErrorType.CANCELLED) {
                          return;
                        }
                        if (r.isForMainFrame == true && mounted) {
                          final target = Uri.tryParse(r.url.toString());
                          if ({
                            'i.mooc.chaoxing.com',
                            'i.chaoxing.com',
                          }.contains(target?.host)) {
                            // A failed post-login landing page does not imply
                            // failed authentication; verify the business API.
                            unawaited(connect(automatic: true));
                          } else {
                            setState(() => error = '官方页面暂未加载，可重载页面或验证已有会话。');
                          }
                        }
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> launchChaoxingItem(Uri url, {bool browserOnly = false}) async {
  if (!chaoxingItemLink(url)) return false;
  if (!browserOnly) {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        if (await const MethodChannel('nuistaio/chaoxing')
                .invokeMethod<bool>('openItem', url.toString()) ==
            true) {
          return true;
        }
      } else if (await launchUrl(
        url,
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return true;
      }
    } catch (_) {
      /* browser fallback */
    }
  }
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class ChaoxingPanel extends StatelessWidget {
  const ChaoxingPanel({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => _ChaoxingTaskList(state: state);
}

class _ChaoxingTaskList extends StatefulWidget {
  const _ChaoxingTaskList({required this.state});
  final AppState state;
  @override
  State<_ChaoxingTaskList> createState() => _ChaoxingPanelState();
}

class _ChaoxingPanelState extends State<_ChaoxingTaskList> {
  AppState get state => widget.state;
  String? filter;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          state.chaoxing.verified &&
          !state.chaoxing.busy &&
          state.chaoxing.updatedAt == null) {
        unawaited(state.refreshChaoxing());
      }
    });
  }

  static const groups = {
    'todo': '未完成',
    'grading': '待批改',
    'done': '已完成',
    'expired': '已过期',
  };
  Color groupColor(BuildContext context, String group) {
    final colors = Theme.of(context).colorScheme,
        dark = Theme.of(context).brightness == Brightness.dark;
    return switch (group) {
      'grading' => dark ? Colors.amber.shade200 : Colors.brown.shade700,
      'done' => dark ? Colors.green.shade200 : Colors.green.shade800,
      'expired' => colors.error,
      _ => colors.primary,
    };
  }

  Future<void> open(
    BuildContext context,
    ChaoxingItem item, {
    bool browserOnly = false,
  }) async {
    final ok =
        item.url != null &&
        await launchChaoxingItem(item.url!, browserOnly: browserOnly);
    if (context.mounted && !ok) {
      showCampusSnackBar(
        context,
        SnackBar(
          content: Text(
            '没有可打开的项目链接，请在学习通官方页面查看。',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.chaoxing,
    builder: (context, _) {
      final r = state.chaoxing, colors = Theme.of(context).colorScheme;
      final visible = r.items
          .where((item) => filter == null || item.group == filter)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '作业与考试',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '连接学习通',
                onPressed: () => openChaoxingLogin(context, state),
                icon: const Icon(Icons.manage_accounts_outlined),
              ),
              IconButton(
                tooltip: '刷新作业与考试',
                onPressed: r.verified && !r.busy ? state.refreshChaoxing : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (!r.verified) Card(child: ChaoxingAccountTile(state: state)),
          if (r.scanTerm != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusTag(r.scanTerm!, color: colors.primary),
                  StatusTag(
                    '本学期 ${r.selectedCourseCount} / 全部 ${r.totalCourseCount} 门',
                    color: colors.tertiary,
                  ),
                ],
              ),
            ),
          if (r.updatedAt != null)
            Text(
              '上次读取：${r.updatedAt!.toLocal().toString().substring(0, 16)}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('全部 ${r.items.length}'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null),
              ),
              for (final entry in groups.entries)
                ChoiceChip(
                  label: Text(
                    '${entry.value} ${r.items.where((item) => item.group == entry.key).length}',
                  ),
                  selected: filter == entry.key,
                  selectedColor: groupColor(
                    context,
                    entry.key,
                  ).withValues(alpha: .18),
                  labelStyle: TextStyle(color: groupColor(context, entry.key)),
                  onSelected: (_) => setState(() => filter = entry.key),
                ),
            ],
          ),
          if (r.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            LoadingText(r.progress.isEmpty ? '正在读取课程…' : r.progress),
          ],
          if (r.notice != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (r.noticeIsError ? colors.error : colors.primary)
                    .withValues(alpha: .09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    r.noticeIsError ? Icons.error_outline : Icons.info_outline,
                    color: r.noticeIsError ? colors.error : colors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.notice!,
                      style: TextStyle(
                        color: r.noticeIsError
                            ? colors.error
                            : colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (r.verified && visible.isEmpty && !r.busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                r.updatedAt == null
                    ? '点击刷新，读取本学期学习通作业和考试。'
                    : filter == null
                    ? '本学期未读取到作业或考试项目。'
                    : '没有${groups[filter]}的项目。',
              ),
            ),
          for (final item in visible)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor:
                      (item.kind == 'work' ? colors.primary : colors.tertiary)
                          .withValues(alpha: .12),
                  child: Icon(
                    item.kind == 'work'
                        ? Icons.assignment_outlined
                        : Icons.quiz_outlined,
                    color: item.kind == 'work'
                        ? colors.primary
                        : colors.tertiary,
                  ),
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusTag(
                            item.kind == 'work' ? '作业' : '考试',
                            color: item.kind == 'work'
                                ? colors.primary
                                : colors.tertiary,
                          ),
                          StatusTag(
                            item.status,
                            color: groupColor(context, item.group),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.course,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (item.time.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            item.time,
                            style: TextStyle(
                              color: item.group == 'expired'
                                  ? colors.error
                                  : colors.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                onTap: () => open(context, item),
                trailing: IconButton(
                  tooltip: '在浏览器打开',
                  onPressed: () => open(context, item, browserOnly: true),
                  icon: const Icon(Icons.open_in_browser_outlined),
                ),
              ),
            ),
        ],
      );
    },
  );
}
