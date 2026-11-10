import '../services/script_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../campus_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_state.dart';
import '../widgets.dart';
import '../webview_page_lifecycle.dart';
import '../services/navigation.dart';
import 'schedule.dart';

class ScheduleImportPage extends StatefulWidget {
  const ScheduleImportPage({super.key, required this.state});
  final AppState state;
  static final entry = SchoolNavigation.scheduleEntry;
  static bool allowed(Uri? uri) => SchoolNavigation.schedule(uri);
  @override
  State<ScheduleImportPage> createState() => _ScheduleImportPageState();
}

class _ScheduleImportPageState extends State<ScheduleImportPage>
    with WebViewPageLifecycle<ScheduleImportPage> {
  InAppWebViewController? controller;
  List<Semester> terms = [];
  Semester? selected;
  bool busy = false, ready = false, autoAttempted = false;
  String? error;
  String host = 'jwxt.nuist.edu.cn';
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  Future<Map<String, dynamic>> request(String task) async {
    final url = await controller?.getUrl();
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'jwxt.nuist.edu.cn') {
      throw const FormatException('请先在学校官方页面完成登录。');
    }
    final script = await rootBundle.loadString('assets/js/nuist_schedule.js');
    final result = await controller!
        .callAsyncJavaScript(
          functionBody: schoolScriptBody(script),
          arguments: {
            'task': task,
            'term': selected?.code ?? '',
            'termName': selected?.name ?? '',
          },
        )
        .timeout(const Duration(seconds: 120));
    final value = result?.value;
    if (value == null || result?.error != null) {
      throw const FormatException('课表读取失败，请重新加载教务页面后重试。');
    }
    final data = Map<String, dynamic>.from(
      (value is String ? jsonDecode(value) : value) as Map,
    );
    if (data['ok'] != true) {
      throw FormatException(data['error'] as String? ?? '课表获取失败。');
    }
    return data;
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '未能完成读取或保存，请检查网络后重试。');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> loadTerms() => run(() async {
    final data = await request('semesters');
    final list = (data['terms'] as List)
        .map((t) => Semester.fromJson(Map<String, dynamic>.from(t)))
        .where((t) => RegExp(r'^\d{4}-\d{4}-[123]$').hasMatch(t.code))
        .toList();
    final unique = {for (final t in list) t.code: t}.values.toList();
    if (unique.isEmpty) {
      throw const FormatException('没有获取到可用学期，请确认已进入课表页面。');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      terms = unique;
      selected = unique.firstWhere(
        (t) => t.code == data['current'],
        orElse: () => unique.first,
      );
    });
  });
  Future<void> import() => run(() async {
    final generation = widget.state.sessionGeneration;
    final data = await request('schedule');
    final schedule = ScheduleParser.parse(
      Map<String, dynamic>.from(data['data']),
    );
    if (!mounted) {
      return;
    }
    await widget.state.saveSchedule(schedule, generation: generation);
    if (!mounted) {
      return;
    }
    if (generation != widget.state.sessionGeneration) {
      throw const FormatException('账号状态已改变，请重新导入。');
    }
    await closeWebViewPage(true);
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return guardWebViewPage(
      Scaffold(
        appBar: AppBar(
          title: const Text('从教务系统获取课表'),
          actions: [
            IconButton(
              tooltip: '重新加载',
              onPressed: busy
                  ? null
                  : () {
                      setState(() {
                        error = null;
                        ready = false;
                        autoAttempted = false;
                        terms = [];
                        selected = null;
                      });
                      controller?.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri(ScheduleImportPage.entry.toString()),
                        ),
                      );
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !supported
            ? const PageBody(
                children: [
                  EmptyCard(
                    icon: Icons.phone_android_outlined,
                    title: '当前平台不支持课表导入',
                    message: '在 Android、iOS 或 macOS 客户端登录学校教务页面，即可读取课表。系统浏览器的登录不会自动共享给 App。',
                  ),
                ],
              )
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: colors.surfaceContainerLow,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock_outline, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  host,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ready
                                ? '选择学期后获取课表，原有课表将在成功后更新。'
                                : '请在学校官方页面完成登录；如提示选择角色，请选择学生。',
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                error!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          if (terms.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: DropdownButtonFormField<String>(
                                initialValue: selected?.code,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '学期',
                                ),
                                items: terms
                                    .map(
                                      (t) => DropdownMenuItem(
                                        value: t.code,
                                        child: Text(t.name),
                                      ),
                                    )
                                    .toList(),
                                onChanged: busy
                                    ? null
                                    : (code) => setState(
                                        () => selected = terms.firstWhere(
                                          (t) => t.code == code,
                                        ),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (busy) const LinearProgressIndicator(),
                    Expanded(
                      child: !webViewVisible
                          ? const SizedBox.shrink()
                          : InAppWebView(
                              initialUrlRequest: URLRequest(
                                url: WebUri(
                                  ScheduleImportPage.entry.toString(),
                                ),
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
                                final raw = action.request.url;
                                if (action.isForMainFrame == false) {
                                  return raw?.toString() == 'about:blank' ||
                                          ScheduleImportPage.allowed(
                                            raw == null
                                                ? null
                                                : Uri.tryParse(raw.toString()),
                                          )
                                      ? NavigationActionPolicy.ALLOW
                                      : NavigationActionPolicy.CANCEL;
                                }
                                final uri = raw == null
                                    ? null
                                    : Uri.tryParse(raw.toString());
                                if (ScheduleImportPage.allowed(uri)) {
                                  return NavigationActionPolicy.ALLOW;
                                }
                                final secure = SchoolNavigation.httpsUpgrade(
                                  uri,
                                  ScheduleImportPage.allowed,
                                );
                                if (secure != null) {
                                  await controller?.loadUrl(
                                    urlRequest: URLRequest(
                                      url: WebUri(secure.toString()),
                                    ),
                                  );
                                } else if (mounted) {
                                  setState(
                                    () =>
                                        error = '当前链接不在教务认证范围内，请使用学校页面内的登录方式。',
                                  );
                                }
                                return NavigationActionPolicy.CANCEL;
                              },
                              onLoadStart: (_, url) {
                                if (mounted && url != null) {
                                  setState(() {
                                    host = url.host;
                                    ready = false;
                                  });
                                }
                              },
                              onLoadStop: (_, url) async {
                                if (!mounted || url == null) {
                                  return;
                                }
                                final onSchedule =
                                    url.scheme == 'https' &&
                                    url.host == 'jwxt.nuist.edu.cn' &&
                                    url.path.startsWith('/jwapp/sys/wdkb/');
                                setState(() => ready = onSchedule);
                                if (onSchedule && !autoAttempted && !busy) {
                                  autoAttempted = true;
                                  await loadTerms();
                                }
                              },
                              onReceivedError: (_, request, _) {
                                if (mounted && request.isForMainFrame == true) {
                                  setState(
                                    () => error = '教务页面加载失败，请检查网络后重新加载。',
                                  );
                                }
                              },
                              onReceivedHttpError: (_, request, _) {
                                if (mounted && request.isForMainFrame == true) {
                                  setState(() => error = '教务服务器暂时不可用，请稍后重试。');
                                }
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: busy
                              ? null
                              : terms.isEmpty
                              ? loadTerms
                              : import,
                          icon: Icon(
                            terms.isEmpty
                                ? Icons.sync
                                : Icons.download_outlined,
                          ),
                          label: Text(
                            busy
                                ? '正在读取并保存…'
                                : terms.isEmpty
                                ? '已进入课表页，读取学期'
                                : '获取所选学期课表',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
