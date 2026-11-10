import '../campus_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_state.dart';
import '../status_tag.dart';
import '../academic/official_page.dart';
import '../network/campus_network.dart';
import '../network/network_settings.dart';
import '../services/navigation.dart';
import '../webview_page_lifecycle.dart';

String _today() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);

class BulletinPage extends StatefulWidget {
  const BulletinPage({super.key, required this.state});
  final AppState state;
  @override
  State<BulletinPage> createState() => _BulletinPageState();
}

class _BulletinPageState extends State<BulletinPage> {
  final rows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> categories = [];
  String? category, next, error;
  String search = '';
  bool todayOnly = true, busy = false;
  CampusResponse? response;
  int revision = 0;
  late CampusNetworkMode mode;
  late int accountGeneration;
  @override
  void initState() {
    super.initState();
    mode = widget.state.networkMode;
    accountGeneration = widget.state.sessionGeneration;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (mode == widget.state.networkMode &&
        accountGeneration == widget.state.sessionGeneration) {
      return;
    }
    mode = widget.state.networkMode;
    accountGeneration = widget.state.sessionGeneration;
    load();
  }

  @override
  void dispose() {
    revision++;
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && (busy || next == null)) return;
    final token = ++revision;
    setState(() {
      busy = true;
      error = null;
      if (!more) {
        rows.clear();
        next = null;
        response = null;
      }
    });
    try {
      final result = await widget.state.bulletins.query(
        mode,
        'list',
        url: Uri.parse(
          more ? next! : category ?? 'https://bulletin.nuist.edu.cn/index.htm',
        ),
      );
      if (!mounted || token != revision) return;
      final data = result.data;
      setState(() {
        response = result;
        final seen = rows.map((r) => r['url']).toSet();
        for (final r in (data['rows'] as List)) {
          final row = Map<String, dynamic>.from(r as Map);
          if (seen.add(row['url'])) rows.add(row);
        }
        if (!more) {
          categories = [
            for (final c in (data['categories'] as List? ?? []))
              Map<String, dynamic>.from(c as Map),
          ];
        }
        next = data['next'] as String?;
      });
    } on FormatException catch (e) {
      if (mounted && token == revision) setState(() => error = e.message);
    } catch (_) {
      if (mounted && token == revision) {
        setState(() => error = '公告读取失败，请检查网络设置后重试。');
      }
    } finally {
      if (mounted && token == revision) setState(() => busy = false);
    }
  }

  Uri routed(Uri uri) => response?.route?.resolve(uri) ?? uri;
  @override
  Widget build(BuildContext context) {
    final day = _today();
    final visible = rows
        .where(
          (r) =>
              (!todayOnly || r['date'] == day || r['pinned'] == true) &&
              '${r['title']} ${r['department']}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('学校公告'),
        actions: [
          IconButton(
            tooltip: '网络设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => NetworkSettingsPage(state: widget.state),
              ),
            ),
            icon: const Icon(Icons.settings_ethernet),
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () => launchSchoolBrowser(
              context,
              routed(
                Uri.parse(
                  category ?? 'https://bulletin.nuist.edu.cn/index.htm',
                ),
              ),
            ),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索已加载的标题、发布部门',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('今天 · $day'),
                  selected: todayOnly,
                  onSelected: (_) => setState(() => todayOnly = true),
                ),
                ChoiceChip(
                  label: const Text('近期公告'),
                  selected: !todayOnly,
                  onSelected: (_) => setState(() => todayOnly = false),
                ),
              ],
            ),
            if (categories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: '公告分类'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('全部分类'),
                    ),
                    for (final c in categories.where(
                      (c) =>
                          !['全部', '首页', '上页', '下页', '尾页'].contains(c['name']),
                    ))
                      DropdownMenuItem(
                        value: c['url'] as String,
                        child: Text(c['name'] as String),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          category = v;
                          load();
                        },
                ),
              ),
            const SizedBox(height: 12),
            Text(
              '已加载 ${rows.length} 条 · 今日 ${rows.where((r) => r['date'] == day).length} 条${response == null
                  ? ''
                  : response!.path == CampusPath.vpn
                  ? ' · WebVPN'
                  : ' · 直连'}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Text(
              '统计仅覆盖已加载页面；置顶公告保留原发布日期。',
              style: TextStyle(fontSize: 12),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: () => load(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            if (!busy && error == null && visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('已加载页面中没有符合条件的公告，可查看近期公告或加载更多。'),
              ),
            for (final row in visible)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Icon(
                    row['pinned'] == true
                        ? Icons.push_pin_outlined
                        : Icons.article_outlined,
                  ),
                  title: Text(row['title'] as String),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusTag(
                              row['category'] as String,
                              color: categoryAccent(
                                context,
                                row['category'] as String,
                              ),
                            ),
                            if (row['pinned'] == true)
                              StatusTag(
                                '置顶',
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            Text(
                              row['date'] as String,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(row['department'] as String),
                      ],
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BulletinDetailPage(
                        state: widget.state,
                        row: row,
                        initialRoute: response?.route,
                      ),
                    ),
                  ),
                ),
              ),
            if (next != null)
              OutlinedButton(
                onPressed: busy ? null : () => load(more: true),
                child: const Text('加载下一页'),
              ),
          ],
        ),
      ),
    );
  }
}

class BulletinDetailPage extends StatefulWidget {
  const BulletinDetailPage({
    super.key,
    required this.state,
    required this.row,
    this.initialRoute,
  });
  final AppState state;
  final Map<String, dynamic> row;
  final CampusRoute? initialRoute;
  @override
  State<BulletinDetailPage> createState() => _BulletinDetailPageState();
}

class _BulletinDetailPageState extends State<BulletinDetailPage> {
  CampusResponse? response;
  bool invalidated = false;
  String? error;
  int revision = 0;
  late CampusNetworkMode mode;
  late int accountGeneration;
  Uri get canonical => Uri.parse(widget.row['url'] as String);
  Uri routed(Uri url) =>
      (response == null ? widget.initialRoute : response!.route)?.resolve(
        url,
      ) ??
      url;
  @override
  void initState() {
    super.initState();
    mode = widget.state.networkMode;
    accountGeneration = widget.state.sessionGeneration;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (mode == widget.state.networkMode &&
        accountGeneration == widget.state.sessionGeneration) {
      return;
    }
    revision++;
    mode = widget.state.networkMode;
    accountGeneration = widget.state.sessionGeneration;
    // Close this account's article instead of retaining private content on a new account.
    if (mounted) {
      setState(() {
        response = null;
        invalidated = true;
        error = '账号或网络路径已变化，请返回公告列表重新打开。';
      });
    }
  }

  @override
  void dispose() {
    revision++;
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> load() async {
    final token = ++revision;
    try {
      final data = await widget.state.bulletins.query(
        mode,
        'detail',
        url: canonical,
      );
      if (mounted && token == revision) setState(() => response = data);
    } on FormatException catch (e) {
      if (mounted && token == revision) setState(() => error = e.message);
    } catch (_) {
      if (mounted && token == revision) {
        setState(() => error = '正文读取失败，请在原网页查看。');
      }
    }
  }

  void original(Uri url) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => BulletinWebPage(
        entry: routed(url),
        route: response == null ? widget.initialRoute : response!.route,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => invalidated
      ? Scaffold(
          appBar: AppBar(title: const Text('公告正文')),
          body: const Padding(
            padding: EdgeInsets.all(24),
            child: Text('账号或网络路径已变化，请返回公告列表重新打开。'),
          ),
        )
      : Scaffold(
          appBar: AppBar(
            title: const Text('公告正文'),
            actions: [
              IconButton(
                tooltip: '在浏览器中打开',
                onPressed: () =>
                    launchSchoolBrowser(context, routed(canonical)),
                icon: const Icon(Icons.open_in_browser_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.row['title'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('${widget.row['date']} · ${widget.row['department']}'),
              const SizedBox(height: 20),
              if (response == null && error == null)
                const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (response != null)
                SelectableText(response!.data['body'] as String? ?? ''),
              const SizedBox(height: 20),
              for (final link in response?.data['links'] as List? ?? [])
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(link['name'] as String),
                  onTap: () => original(Uri.parse(link['url'] as String)),
                ),
              OutlinedButton.icon(
                onPressed: () => original(canonical),
                icon: const Icon(Icons.language),
                label: const Text('在应用内查看原网页 / 图片与附件'),
              ),
              const Text(
                '系统浏览器使用独立会话，打开后可能需要重新登录。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
}

class BulletinWebPage extends StatefulWidget {
  const BulletinWebPage({super.key, required this.entry, this.route});
  final Uri entry;
  final CampusRoute? route;
  @override
  State<BulletinWebPage> createState() => _BulletinWebPageState();
}

class _BulletinWebPageState extends State<BulletinWebPage>
    with WebViewPageLifecycle<BulletinWebPage> {
  @override
  Widget build(BuildContext context) => guardWebViewPage(
    Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: closeWebViewPage),
        title: const Text('公告原网页'),
        actions: [
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: () => launchSchoolBrowser(context, widget.entry),
            icon: const Icon(Icons.open_in_browser_outlined),
          ),
        ],
      ),
      body: webViewVisible
          ? InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.entry.toString()),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                useHybridComposition: false,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
              ),
              shouldOverrideUrlLoading: (_, action) async {
                final uri = Uri.tryParse(action.request.url?.toString() ?? '');
                return (widget.route == null
                        ? SchoolNavigation.bulletin(uri)
                        : (widget.route!.accepts(uri) ||
                              SchoolNavigation.vpnResourceAuth(uri)))
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              },
            )
          : const SizedBox.shrink(),
    ),
  );
}
