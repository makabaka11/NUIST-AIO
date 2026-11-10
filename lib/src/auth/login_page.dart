import 'package:flutter/foundation.dart';

import '../campus_ui.dart';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_state.dart';
import '../widgets.dart';
import '../webview_page_lifecycle.dart';
import 'session_store.dart';
import '../services/sso_diagnostics.dart';
import '../services/navigation.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.state,
    this.initializeServices = true,
  });
  final AppState state;
  final bool initializeServices;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with WebViewPageLifecycle<LoginPage> {
  InAppWebViewController? controller;
  double progress = 0;
  String host = 'authserver.nuist.edu.cn';
  String? error;
  bool capturing = false;
  bool complete = false;
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  Future<void> inspect({bool manual = false}) async {
    if (capturing || complete || !mounted || !webViewVisible) return;
    setState(() {
      capturing = true;
      if (manual) error = null;
    });
    try {
      final url = await controller?.getUrl();
      if (url == null ||
          !SessionStore.isPortalLanding(Uri.parse(url.toString()))) {
        if (manual && mounted) {
          setState(() => error = '尚未进入融合门户，请先完成登录并等待跳转。');
        }
        return;
      }
      final script = await rootBundle.loadString(
        'assets/js/nuist_portal_probe.js',
      );
      final result = await controller!
          .callAsyncJavaScript(functionBody: script)
          .timeout(const Duration(seconds: 15));
      SsoDiagnostics.record(
        'portal',
        'profile_probe',
        ok: result?.error == null && result?.value is Map,
      );
      final profile = result?.value;
      final accountKey = profile is Map ? profile['accountKey'] : null;
      final displayName = profile is Map && profile['displayName'] is String
          ? profile['displayName'] as String
          : '';
      if (accountKey is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(accountKey) ||
          result?.error != null) {
        if (manual && mounted) {
          setState(() => error = '门户尚未返回有效登录状态。请等待页面加载完成后重试，或重新登录。');
        }
        return;
      }
      if (await widget.state.sessions.accountChanged(accountKey)) {
        await widget.state.clearPrivateData();
        await widget.state.resetServiceSessions();
      }
      final saved = await widget.state.sessions.capturePortalSession(
        accountKey: accountKey,
        displayName: displayName,
      );
      if (!saved) throw StateError('Session persistence failed');
      if (!mounted || !webViewVisible) return;
      // Rechecking the same login must not discard imported courses or dorm choice.
      await widget.state.sessionChanged();
      SsoDiagnostics.record(
        'portal',
        'session_saved',
        ok: widget.state.connectedAt != null,
      );
      if (widget.state.connectedAt == null) {
        throw StateError('Session persistence failed');
      }
      if (!mounted || !webViewVisible) return;
      setState(() => complete = true);
      if (widget.initializeServices) {
        final connection = widget.state.connectCampusServices();
        setState(() {});
        await connection;
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => error = '未能读取或保存登录状态，请检查网络并重新检查。');
      }
    } finally {
      if (mounted) setState(() => capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return guardWebViewPage(
      Scaffold(
        appBar: AppBar(
          title: const Text('连接校园账号'),
          actions: [
            if (supported && !complete)
              IconButton(
                tooltip: '重新加载',
                icon: const Icon(Icons.refresh),
                onPressed: capturing
                    ? null
                    : () {
                        setState(() => error = null);
                        controller?.loadUrl(
                          urlRequest: URLRequest(
                            url: WebUri(SessionStore.loginUri.toString()),
                          ),
                        );
                      },
              ),
          ],
        ),
        body: !supported
            ? const PageBody(
                children: [
                  EmptyCard(
                    icon: Icons.phone_android_outlined,
                    title: '当前平台不支持内嵌认证',
                    message: '请使用 Android、iOS 或 macOS 客户端，在学校官方页面完成统一认证。',
                  ),
                ],
              )
            : complete
            ? PageBody(
                children: [
                  const SizedBox(height: 32),
                  EmptyCard(
                    icon: Icons.verified_user_outlined,
                    title: '校园账号已连接',
                    loading:
                        widget.initializeServices &&
                        widget.state.connectingServices,
                    message: widget.initializeServices
                        ? widget.state.servicesNotice ?? '门户会话已保存。'
                        : '门户登录已完成，返回向导后将初始化各校园服务。',
                    action: FilledButton(
                      onPressed: closeWebViewPage,
                      child: Text(
                        widget.state.connectingServices ? '返回，后台继续连接' : '完成',
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: colors.surfaceContainerLow,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            host,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        const Text('学校官方页面'),
                      ],
                    ),
                  ),
                  if (progress < 1)
                    LinearProgressIndicator(
                      value: progress == 0 ? null : progress,
                    ),
                  if (error != null)
                    MaterialBanner(
                      content: Text(error!),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            setState(() => error = null);
                            await inspect(manual: true);
                          },
                          child: const Text('重新检查'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => error = null),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: !webViewVisible
                        ? const SizedBox.shrink()
                        : InAppWebView(
                            initialUrlRequest: URLRequest(
                              url: WebUri(SessionStore.loginUri.toString()),
                            ),
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                              useHybridComposition: false,
                              preferredContentMode:
                                  UserPreferredContentMode.DESKTOP,
                              useShouldOverrideUrlLoading: true,
                              supportMultipleWindows: false,
                              javaScriptCanOpenWindowsAutomatically: false,
                              mixedContentMode:
                                  MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                              isInspectable: false,
                            ),
                            onWebViewCreated: (value) => controller = value,
                            shouldOverrideUrlLoading: (_, action) async {
                              final uri = action.request.url;
                              if (action.isForMainFrame == false) {
                                return uri?.toString() == 'about:blank' ||
                                        SessionStore.isAllowedNavigation(
                                          uri == null
                                              ? null
                                              : Uri.tryParse(uri.toString()),
                                        )
                                    ? NavigationActionPolicy.ALLOW
                                    : NavigationActionPolicy.CANCEL;
                              }
                              if (SessionStore.isAllowedNavigation(
                                uri == null ? null : Uri.parse(uri.toString()),
                              )) {
                                return NavigationActionPolicy.ALLOW;
                              }
                              final secure = SchoolNavigation.httpsUpgrade(
                                uri == null
                                    ? null
                                    : Uri.tryParse(uri.toString()),
                                SessionStore.isAllowedNavigation,
                              );
                              if (secure != null) {
                                await controller?.loadUrl(
                                  urlRequest: URLRequest(
                                    url: WebUri(secure.toString()),
                                  ),
                                );
                                return NavigationActionPolicy.CANCEL;
                              }
                              if (mounted) {
                                setState(
                                  () =>
                                      error = '此链接不在当前认证范围内，请使用学号与密码等页面内登录方式。',
                                );
                              }
                              return NavigationActionPolicy.CANCEL;
                            },
                            onProgressChanged: (_, value) {
                              if (mounted) {
                                setState(() => progress = value / 100);
                              }
                            },
                            onLoadStart: (_, url) {
                              if (mounted && url != null) {
                                setState(() {
                                  host = url.host;
                                  error = null;
                                });
                              }
                            },
                            onLoadStop: (_, _) => inspect(),
                            onUpdateVisitedHistory: (_, _, _) => inspect(),
                            onReceivedError: (_, request, _) {
                              if (request.isForMainFrame == true && mounted) {
                                setState(() => error = '页面暂时无法加载，请检查网络后重新加载。');
                              }
                            },
                            onReceivedHttpError: (_, request, response) {
                              if (request.isForMainFrame == true && mounted) {
                                setState(
                                  () => error =
                                      '学校服务器暂时无法响应（${response.statusCode}），请稍后重试。',
                                );
                              }
                            },
                            // Keep platform certificate validation. Overriding the
                            // iOS trust challenge would also intercept valid TLS.
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextButton.icon(
                        onPressed: capturing
                            ? null
                            : () => inspect(manual: true),
                        icon: capturing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(capturing ? '正在检查登录状态…' : '我已登录，尝试获取状态'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
