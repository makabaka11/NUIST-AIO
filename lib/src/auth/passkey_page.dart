import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../campus_ui.dart';
import '../app_state.dart';
import '../services/navigation.dart';
import '../webview_page_lifecycle.dart';

Future<void> offerPasskey(BuildContext context, AppState state) async {
  if (state.passkeyEnabled || state.connectedAt == null) return;
  final enable = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('开启通行密钥自动登录？'),
      content: const Text(
        '密钥仅在本机加密保存，可在统一认证失效时自动登录，增强连接稳定性。创建时可能需要在学校页面再次验证身份。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('稍后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('开启'),
        ),
      ],
    ),
  );
  if (enable == true && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => PasskeyPage(state: state)),
    );
  }
}

class PasskeyPage extends StatefulWidget {
  const PasskeyPage({super.key, required this.state});
  final AppState state;
  @override
  State<PasskeyPage> createState() => _PasskeyPageState();
}

class _PasskeyPageState extends State<PasskeyPage>
    with WebViewPageLifecycle<PasskeyPage> {
  Timer? poll;
  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  String hint = '请在学校页面完成身份验证。密钥仅在本机加密保存；不保存登录密码。';
  bool saving = false, complete = false;
  late final generation = widget.state.sessionGeneration;
  final deviceName = '信大AIO_${DateTime.now().millisecondsSinceEpoch}';
  Future<void> inject(InAppWebViewController c) async {
    final uri = Uri.tryParse((await c.getUrl())?.toString() ?? '');
    if (!mounted ||
        !webViewVisible ||
        complete ||
        !SchoolNavigation.trusted(uri, {'authserver.nuist.edu.cn'}) ||
        !uri!.path.toLowerCase().contains('personcenter')) {
      return;
    }
    final script =
        (await rootBundle.loadString('assets/js/nuist_passkey_register.js'))
            .replaceFirst('__DEVICE_NAME__', jsonEncode(deviceName))
            .replaceFirst(
              '__PORTAL_ALLOWED_ORIGIN__',
              jsonEncode('https://authserver.nuist.edu.cn'),
            );
    await c.evaluateJavascript(
      source:
          '''window.__aioPasskeyMessages ??= []; window.NuistPasskey = {postMessage: function(message) {if (window === top && location.origin === 'https://authserver.nuist.edu.cn') {window.__aioPasskeyMessages.push(message); if (window.__aioPasskeyMessages.length > 20) window.__aioPasskeyMessages.shift();}}};\n$script''',
    );
  }

  Future<void> receive(InAppWebViewController c, String message) async {
    if (!mounted ||
        !webViewVisible ||
        saving ||
        complete ||
        generation != widget.state.sessionGeneration) {
      return;
    }
    final uri = Uri.tryParse((await c.getUrl())?.toString() ?? '');
    if (!SchoolNavigation.trusted(uri, {'authserver.nuist.edu.cn'}) ||
        !uri!.path.toLowerCase().contains('personcenter')) {
      return;
    }
    try {
      final data = jsonDecode(message) as Map;
      if (data['type'] == 'error') {
        setState(() => hint = '创建未完成，请重新进入本页重试，或在学校页面完成额外验证。');
      } else if (data['type'] == 'status') {
        setState(
          () => hint = data['stage'] == 'verifying'
              ? '请打开“生物识别”，开启生物识别登录并点击“绑定当前设备”，在学校页面完成密码与验证码验证。'
              : '正在创建通行密钥，请稍候…',
        );
      } else if (data['type'] == 'success') {
        saving = true;
        final bundle = Map<String, dynamic>.from(data['bundle'] as Map);
        final owner = await widget.state.sessions.accountKey();
        // Verify the credential's user against the bound account digest.
        final match = await c.callAsyncJavaScript(
          functionBody: '''
          if (location.origin !== 'https://authserver.nuist.edu.cn') return false;
          const id = new TextDecoder('utf-8', {fatal:true}).decode(Uint8Array.from(atob(userId.replaceAll('-','+').replaceAll('_','/')), c => c.charCodeAt(0)));
          const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('nuistaio:portal:' + id));
          return Array.from(new Uint8Array(hash), b => b.toString(16).padStart(2,'0')).join('') === owner;
        ''',
          arguments: {'userId': bundle['userId'], 'owner': owner},
        );
        if (match?.value != true ||
            owner == null ||
            generation != widget.state.sessionGeneration) {
          throw const FormatException();
        }
        await widget.state.sessions.savePasskey(bundle, owner: owner);
        if (generation != widget.state.sessionGeneration) {
          await widget.state.sessions.deletePasskey();
          return;
        }
        await widget.state.refreshPasskey();
        if (mounted) {
          setState(() {
            complete = true;
            hint = '通行密钥已加密保存，自动登录已开启。';
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => hint = '无法保存通行密钥，请确认当前学校账号与绑定账号一致后重试。');
    } finally {
      saving = false;
    }
  }

  @override
  Widget build(BuildContext context) => guardWebViewPage(
    Scaffold(
      appBar: AppBar(title: const Text('开启通行密钥自动登录')),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(hint)),
          if (complete)
            FilledButton(onPressed: closeWebViewPage, child: const Text('完成')),
          if (!complete)
            Expanded(
              child: webViewVisible
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(
                          'https://authserver.nuist.edu.cn/authserver/login',
                        ),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        useShouldOverrideUrlLoading: true,
                        preferredContentMode: UserPreferredContentMode.DESKTOP,
                        useHybridComposition: false,
                        mixedContentMode:
                            MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                      ),
                      onWebViewCreated: (c) {
                        poll = Timer.periodic(const Duration(seconds: 1), (
                          _,
                        ) async {
                          if (!mounted ||
                              !webViewVisible ||
                              complete ||
                              saving) {
                            return;
                          }
                          try {
                            final messages = await c.callAsyncJavaScript(
                              functionBody: "if (window !== top || location.origin !== 'https://authserver.nuist.edu.cn' || !location.pathname.toLowerCase().includes('personcenter')) return []; return (window.__aioPasskeyMessages ?? []).splice(0);",
                            );
                            if (messages?.value is List) {
                              for (final message in messages!.value as List) {
                                if (message is String) {
                                  await receive(c, message);
                                }
                              }
                            }
                          } catch (_) {
                            /* Navigation replaces the document. */
                          }
                        });
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = Uri.tryParse(
                          action.request.url?.toString() ?? '',
                        );
                        bool allowed(Uri? u) => SchoolNavigation.trusted(u, {
                          'authserver.nuist.edu.cn',
                        });
                        if (allowed(uri)) return NavigationActionPolicy.ALLOW;
                        final secure = SchoolNavigation.httpsUpgrade(
                          uri,
                          allowed,
                        );
                        if (secure != null) {
                          await c.loadUrl(
                            urlRequest: URLRequest(
                              url: WebUri(secure.toString()),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      },
                      onLoadStop: (c, _) => inject(c),
                      onUpdateVisitedHistory: (c, _, _) => inject(c),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    ),
  );
}
