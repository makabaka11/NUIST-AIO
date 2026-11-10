import '../campus_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../academic/official_page.dart';
import '../services/navigation.dart';
import '../webview_page_lifecycle.dart';

class VpnLoginPage extends StatefulWidget {
  const VpnLoginPage({super.key});
  @override
  State<VpnLoginPage> createState() => _VpnLoginPageState();
}

class _VpnLoginPageState extends State<VpnLoginPage>
    with WebViewPageLifecycle<VpnLoginPage> {
  double progress = 0;
  @override
  Widget build(BuildContext context) => guardWebViewPage(
    Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: closeWebViewPage),
        title: const Text('连接学校 WebVPN'),
        actions: [
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () =>
                launchSchoolBrowser(context, SchoolNavigation.vpnEntry),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 1) LinearProgressIndicator(value: progress),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '优先使用已登录的统一认证会话；如需密码、验证码或通行密钥，请在学校页面自行完成。系统浏览器会话与 App 独立。',
            ),
          ),
          Expanded(
            child: webViewVisible
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(SchoolNavigation.vpnCasEntry.toString()),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      useHybridComposition: false,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    ),
                    onProgressChanged: (_, p) {
                      if (mounted) setState(() => progress = p / 100);
                    },
                    shouldOverrideUrlLoading: (controller, action) async {
                      final uri = Uri.tryParse(
                        action.request.url?.toString() ?? '',
                      );
                      if (SchoolNavigation.vpn(uri)) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      final secure = SchoolNavigation.httpsUpgrade(
                        uri,
                        SchoolNavigation.vpn,
                      );
                      if (secure != null) {
                        await controller.loadUrl(
                          urlRequest: URLRequest(
                            url: WebUri(secure.toString()),
                          ),
                        );
                      }
                      return NavigationActionPolicy.CANCEL;
                    },
                  )
                : const SizedBox.shrink(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => closeWebViewPage(),
                icon: const Icon(Icons.check),
                label: const Text('已完成登录，返回验证'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
