import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/navigation.dart';
import '../webview_page_lifecycle.dart';

Future<void> launchSchoolBrowser(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开浏览器，请检查默认浏览器设置。')));
  }
}

class OfficialAcademicPage extends StatefulWidget {
  const OfficialAcademicPage({
    super.key,
    required this.entry,
    required this.title,
  });
  final Uri entry;
  final String title;
  @override
  State<OfficialAcademicPage> createState() => _OfficialAcademicPageState();
}

class _OfficialAcademicPageState extends State<OfficialAcademicPage>
    with WebViewPageLifecycle<OfficialAcademicPage> {
  String? error;
  @override
  Widget build(BuildContext context) => guardWebViewPage(
    Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: closeWebViewPage),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () => launchSchoolBrowser(context, widget.entry),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: webViewVisible
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.entry.toString()),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      useHybridComposition: false,
                      preferredContentMode: UserPreferredContentMode.DESKTOP,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    ),
                    shouldOverrideUrlLoading: (controller, action) async {
                      final uri = Uri.tryParse(
                        action.request.url?.toString() ?? '',
                      );
                      if (SchoolNavigation.schedule(uri)) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      final secure = SchoolNavigation.httpsUpgrade(
                        uri,
                        SchoolNavigation.schedule,
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
                    onReceivedError: (_, request, _) {
                      if (request.isForMainFrame == true && mounted) {
                        setState(() => error = '网页加载失败，请稍后重试。');
                      }
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}
