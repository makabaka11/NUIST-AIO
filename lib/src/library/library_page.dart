import '../campus_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_state.dart';
import '../academic/official_page.dart';
import '../services/navigation.dart';
import '../services/site_registry.dart';
import '../services/sso_diagnostics.dart';
import '../status_tag.dart';
import '../webview_page_lifecycle.dart';
import '../widgets.dart';

void openLibrary(BuildContext context, AppState state) => Navigator.push<void>(
  context,
  MaterialPageRoute(builder: (_) => LibraryPage(state: state)),
);

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final data = state.libraryLoans, colors = Theme.of(context).colorScheme;
      final today = DateTime.now().toUtc().add(const Duration(hours: 8));
      return Scaffold(
        appBar: AppBar(
          title: const Text('图书借阅'),
          actions: [
            IconButton(
              tooltip: '刷新借阅',
              onPressed: state.syncingLibrary
                  ? null
                  : state.libraryVerified
                  ? state.syncLibrary
                  : state.connectLibrary,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '图书馆官方页面',
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => LibraryLoginPage(state: state),
                ),
              ),
              icon: const Icon(Icons.open_in_browser_outlined),
            ),
          ],
        ),
        body: PageBody(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => launchSchoolBrowser(
                    context,
                    SchoolSites.get(SchoolSiteId.library).officialWebsite!,
                  ),
                  icon: const Icon(Icons.public),
                  label: const Text('图书馆主页'),
                ),
                TextButton.icon(
                  onPressed: () => launchSchoolBrowser(
                    context,
                    Uri.parse(
                      SchoolSites.get(SchoolSiteId.library).features
                          .singleWhere((f) => f.id == 'library_search')
                          .entry!,
                    ),
                  ),
                  icon: const Icon(Icons.search),
                  label: const Text('馆藏检索'),
                ),
              ],
            ),
            if (!state.libraryVerified)
              EmptyCard(
                icon: Icons.local_library_outlined,
                title: '连接图书馆账户',
                message: state.connectedAt == null
                    ? '请先连接校园主账号，再连接图书馆。'
                    : '复用学校统一认证，在借阅接口通过验证后同步。遇到验证码可在官方页面完成。',
                action: FilledButton(
                  onPressed: state.connectedAt == null || state.syncingLibrary
                      ? null
                      : state.connectLibrary,
                  child: const Text('连接并同步借阅'),
                ),
              ),
            if (state.syncingLibrary) const LinearProgressIndicator(),
            if (state.libraryNotice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  state.libraryNotice!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            if (data != null) ...[
              SectionTitle('当前借阅 ${data.books.length} 册'),
              Text(
                '缓存更新：${data.updatedAt.toLocal().toString().substring(0, 16)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (data.books.isEmpty) const Text('当前没有在借图书。'),
              for (final book in data.books)
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.menu_book_outlined,
                      color: book.overdue(today)
                          ? colors.error
                          : colors.primary,
                    ),
                    title: Text(book.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (book.author.isNotEmpty) Text(book.author),
                        if (book.loanDate.isNotEmpty)
                          Text('借阅：${book.loanDate}'),
                        if (book.dueDate.isNotEmpty)
                          Text(
                            '应还：${book.dueDate}',
                            style: TextStyle(
                              color: book.overdue(today)
                                  ? colors.error
                                  : colors.tertiary,
                            ),
                          ),
                        if (book.overdue(today))
                          StatusTag('已逾期', color: colors.error),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class LibraryLoginPage extends StatefulWidget {
  const LibraryLoginPage({super.key, required this.state});
  final AppState state;
  @override
  State<LibraryLoginPage> createState() => _LibraryLoginPageState();
}

class _LibraryLoginPageState extends State<LibraryLoginPage>
    with WebViewPageLifecycle<LibraryLoginPage> {
  late final generation = widget.state.sessionGeneration;
  String? error;
  InAppWebViewController? _controller;

  Uri get officialEntry => SchoolSites.get(SchoolSiteId.library).sessionEntry!;

  Future<void> retryLogin() async {
    setState(() => error = null);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(officialEntry.toString())),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(changed);
  }

  void changed() {
    if (generation != widget.state.sessionGeneration) closeWebViewPage();
  }

  @override
  void dispose() {
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> verify() async {
    await widget.state.connectLibrary();
    if (mounted &&
        generation == widget.state.sessionGeneration &&
        widget.state.libraryVerified) {
      await closeWebViewPage();
    }
  }

  @override
  Widget build(BuildContext context) => guardWebViewPage(
    ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('图书馆官方账户'),
          actions: [
            IconButton(
              tooltip: '重新打开官方账户',
              onPressed: widget.state.syncingLibrary ? null : retryLogin,
              icon: const Icon(Icons.refresh),
            ),
            TextButton(
              onPressed: widget.state.syncingLibrary ? null : verify,
              child: const Text('验证会话'),
            ),
          ],
        ),
        body: Column(
          children: [
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (widget.state.libraryNotice != null)
              Text(
                widget.state.libraryNotice!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: !widget.state.librarySession.available
                  ? const Center(child: Text('当前平台不支持原生图书馆会话。'))
                  : webViewVisible
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(officialEntry.toString()),
                      ),
                      onWebViewCreated: (controller) =>
                          _controller = controller,
                      initialSettings: InAppWebViewSettings(
                        preferredContentMode: UserPreferredContentMode.DESKTOP,
                        useShouldOverrideUrlLoading: true,
                        isInspectable: false,
                        javaScriptCanOpenWindowsAutomatically: false,
                      ),
                      shouldOverrideUrlLoading: (controller, action) async {
                        final uri = Uri.tryParse(action.request.url.toString());
                        if (SchoolNavigation.library(uri)) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        final secure = SchoolNavigation.httpsUpgrade(
                          uri,
                          SchoolNavigation.library,
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
                      onLoadStart: (_, url) {
                        if (mounted) setState(() => error = null);
                        SsoDiagnostics.record(
                          'library',
                          'official_load',
                          location: url == null
                              ? null
                              : Uri.tryParse(url.toString()),
                        );
                      },
                      onReceivedHttpError: (_, request, response) {
                        if (request.isForMainFrame != true) return;
                        SsoDiagnostics.record(
                          'library',
                          'official_http_error',
                          location: Uri.tryParse(request.url.toString()),
                          status: response.statusCode,
                          mainFrame: true,
                        );
                        if (mounted) {
                          setState(
                            () => error = response.statusCode == 403
                                ? '图书馆拒绝了本次认证回调，请点击右上角重新打开官方账户。'
                                : '图书馆页面暂不可用，请稍后重试。',
                          );
                        }
                      },
                      onReceivedError: (_, request, failure) {
                        if (request.isForMainFrame == true &&
                            failure.type != WebResourceErrorType.CANCELLED &&
                            mounted) {
                          setState(() => error = '官方页面暂未加载，可验证已有会话或稍后重试。');
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
