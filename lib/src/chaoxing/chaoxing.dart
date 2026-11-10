import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/site_registry.dart';
import '../services/sso_diagnostics.dart';
import 'current_term.dart';

const chaoxingHosts = {
  'passport2.chaoxing.com',
  'mooc1-api.chaoxing.com',
  'mooc1.chaoxing.com',
  'mooc2-ans.chaoxing.com',
  'i.chaoxing.com',
  'i.mooc.chaoxing.com',
};
bool chaoxingNavigation(Uri? u) =>
    u != null &&
    u.scheme == 'https' &&
    chaoxingHosts.contains(u.host) &&
    u.userInfo.isEmpty &&
    u.port == 443;

/// Observed in the official login page and native login callbacks: the default
/// successful-login destination is the legacy HTTP i.mooc root. Never load it
/// in cleartext, and never upgrade arbitrary hosts, ports or credential URLs.
Uri? chaoxingHttpsUpgrade(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host != 'i.mooc.chaoxing.com' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 80 ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  final secure = uri.replace(scheme: 'https', port: 443);
  return chaoxingNavigation(secure) ? secure : null;
}

bool chaoxingItemLink(Uri? u) =>
    chaoxingNavigation(u) &&
    {
      'mooc1.chaoxing.com',
      'mooc1-api.chaoxing.com',
      'mooc2-ans.chaoxing.com',
    }.contains(u!.host);

/// The school displays China Standard Time. Start times are never deadlines.
DateTime? chaoxingDeadline(String text, {DateTime? now}) {
  final instant = (now ?? DateTime.now()).toUtc();
  if (text.contains('剩余')) {
    var minutes = 0, found = false;
    for (final entry in {'天': 1440, '小时': 60, '分': 1}.entries) {
      final m = RegExp('(\\d+)\\s*${entry.key}').firstMatch(text);
      if (m != null) {
        minutes += int.parse(m[1]!) * entry.value;
        found = true;
      }
    }
    if (found) return instant.add(Duration(minutes: minutes));
  }
  if (text.contains('开始') && !text.contains('结束') && !text.contains('截止')) {
    return null;
  }
  final end = RegExp('结束时间|截止时间|结束|截止').firstMatch(text);
  if (end == null) return null;
  final part = text.substring(end.end);
  final m = RegExp(r'(?:(\d{4})-)?(\d{1,2})-(\d{1,2})[\sT]+(\d{1,2}):(\d{2})')
      .firstMatch(part);
  if (m == null) return null;
  final month = int.parse(m[2]!),
      day = int.parse(m[3]!),
      hour = int.parse(m[4]!),
      minute = int.parse(m[5]!);
  final year = m[1] == null
      ? instant.add(const Duration(hours: 8)).year
      : int.parse(m[1]!);
  DateTime? candidate(int y) {
    if (month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59) {
      return null;
    }
    final d = DateTime.utc(y, month, day, hour, minute);
    if (d.year != y || d.month != month || d.day != day) return null;
    return d.subtract(const Duration(hours: 8));
  }

  final candidates = [
    for (final y in m[1] == null ? [year - 1, year, year + 1] : [year])
      candidate(y),
  ].whereType<DateTime>().toList();
  candidates.sort(
    (a, b) => a
        .difference(instant)
        .inSeconds
        .abs()
        .compareTo(b.difference(instant).inSeconds.abs()),
  );
  return candidates.isEmpty ? null : candidates.first;
}

class ChaoxingItem {
  ChaoxingItem.fromJson(
    Map<String, dynamic> j,
    this.course, {
    this.courseKey = '',
  }) : kind = j['kind'] as String,
       title = j['title'] as String,
       status = j['status'] as String,
       time = j['time'] as String,
       url = Uri.tryParse(j['url'] as String),
       state = j['state'] as String,
       deadline = chaoxingDeadline(j['time'] as String);
  final String kind, title, status, time, course, state, courseKey;
  final Uri? url;
  final DateTime? deadline;
  String get group {
    if (RegExp('已过期|已结束|已截止|已超时').hasMatch(status) ||
        {'ended', 'expired'}.contains(state)) {
      return 'expired';
    }
    if (RegExp('待批阅|待批改|未批阅').hasMatch(status) || state == 'grading') {
      return 'grading';
    }
    final pending = RegExp('未交|未完成|未提交|未开始|待提交|待完成|待互评|进行中').hasMatch(status);
    if (!pending && state == 'done') return 'done';
    if (deadline?.isBefore(DateTime.now()) == true) return 'expired';
    return 'todo';
  }
}

/// No automatic traffic: official login, explicit read-only verification, then
/// separate manual scan. Native WebView owns cookies; cache is memory only.
class ChaoxingRepository extends ChangeNotifier {
  ChaoxingRepository({
    this.documentReader,
    this.currentTerm,
    this.courseGap = const Duration(milliseconds: 1800),
  }) {
    // Plugin debug callbacks otherwise include full URLs and document results.
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  }
  @visibleForTesting
  final Future<Map<String, dynamic>> Function(Uri, String)? documentReader;
  final Duration courseGap;
  Future<ChaoxingTermScope> Function()? currentTerm;
  String? scanTerm;
  int totalCourseCount = 0, selectedCourseCount = 0;
  bool _loadFailed = false;
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Completer<void>? _pending;
  int generation = 0;
  bool verified = false, busy = false, disposed = false;
  String? notice;
  bool noticeIsError = false;
  String progress = '';
  List<ChaoxingItem> items = [];
  DateTime? updatedAt, busyUntil;
  List<Map<String, dynamic>> _courses = [];
  bool get supported =>
      !kIsWeb &&
      InAppWebViewPlatform.instance != null &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  void changed() {
    if (!disposed) notifyListeners();
  }

  void check(int token) {
    if (token != generation || disposed) {
      throw const FormatException('账号已变化，请重新连接。');
    }
  }

  Future<void> _open() async {
    if (_controller != null) return;
    if (!supported) throw const FormatException('请在支持 WebView 的客户端连接学习通。');
    final token = generation, ready = Completer<void>();
    final view = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        // The scanner parses the desktop course/work/exam documents on phones
        // too. Login keeps its existing separate WebView and native cookie jar.
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        useShouldOverrideUrlLoading: true,
        isInspectable: false,
        useOnNavigationResponse: true,
        javaScriptCanOpenWindowsAutomatically: false,
      ),
      onWebViewCreated: (c) {
        if (token == generation) _controller = c;
        ready.complete();
      },
      shouldOverrideUrlLoading: (_, action) async {
        final uri = Uri.tryParse(action.request.url.toString());
        final allowed = chaoxingNavigation(uri);
        if (!allowed) {
          SsoDiagnostics.record(
            'chaoxing',
            'navigation_blocked',
            location: uri,
            mainFrame: action.isForMainFrame,
          );
        }
        return allowed
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (_, url) {
        if (url?.scheme == 'about') return;
        SsoDiagnostics.record(
          'chaoxing',
          'load_stop',
          location: url == null ? null : Uri.tryParse(url.toString()),
        );
        if (_pending?.isCompleted == false) _pending!.complete();
      },
      onReceivedError: (_, r, failure) {
        if (failure.type == WebResourceErrorType.CANCELLED) return;
        if (r.isForMainFrame == true) {
          SsoDiagnostics.record(
            'chaoxing',
            'load_error',
            location: Uri.tryParse(r.url.toString()),
            type: failure.type.toString(),
          );
        }
        if (r.isForMainFrame == true && _pending?.isCompleted == false) {
          _loadFailed = true;
          _pending!.complete();
        }
      },
      onNavigationResponse: (_, navigation) async {
        if (!navigation.isForMainFrame) return NavigationResponseAction.ALLOW;
        final status = navigation.response?.statusCode;
        if (status == 202 || status == 429) {
          busyUntil = DateTime.now().add(const Duration(minutes: 15));
        }
        if (status != null && (status == 202 || status >= 400)) {
          _loadFailed = true;
          if (_pending?.isCompleted == false) _pending!.complete();
          return NavigationResponseAction.CANCEL;
        }
        return NavigationResponseAction.ALLOW;
      },
      onReceivedHttpError: (_, r, response) {
        if (r.isForMainFrame != true) return;
        SsoDiagnostics.record(
          'chaoxing',
          'http_error',
          location: Uri.tryParse(r.url.toString()),
          status: response.statusCode,
        );
        if (response.statusCode == 202 || response.statusCode == 429) {
          busyUntil = DateTime.now().add(const Duration(minutes: 15));
        }
        if (response.statusCode != 200 && _pending?.isCompleted == false) {
          _loadFailed = true;
          _pending!.complete();
        }
      },
    );
    _view = view;
    await view.run().timeout(const Duration(seconds: 10));
    await ready.future.timeout(const Duration(seconds: 10));
    check(token);
  }

  Future<Map<String, dynamic>> _read(Uri url, String task, int token) async {
    check(token);
    SsoDiagnostics.record('chaoxing', 'read_start', task: task, location: url);
    if (!chaoxingNavigation(url)) throw const FormatException('学习通地址不受支持。');
    if (busyUntil?.isAfter(DateTime.now()) == true) {
      throw const FormatException('学习通请求受限，请15分钟后重试。');
    }
    if (documentReader != null) {
      final result = await documentReader!(url, task);
      check(token);
      if (result['ok'] != true) {
        if (result['code'] == 'auth') verified = false;
        if (result['code'] == 'busy') {
          busyUntil = DateTime.now().add(const Duration(minutes: 15));
        }
        throw const FormatException('学习通读取失败。');
      }
      return result;
    }
    await _open();
    check(token);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    check(token);
    final pending = Completer<void>();
    _pending = pending;
    _loadFailed = false;
    try {
      await _controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url.toString())),
      );
      await pending.future.timeout(const Duration(seconds: 25));
      check(token);
      if (_loadFailed) throw const FormatException('学习通页面加载失败，请稍后重试。');
      final script = await rootBundle.loadString('assets/js/nuist_chaoxing.js');
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (true) {
        check(token);
        final nativeUrl = (await _controller!.getUrl()).toString();
        final current = Uri.tryParse(nativeUrl);
        check(token);
        if (!chaoxingNavigation(current) ||
            current!.host == 'passport2.chaoxing.com') {
          verified = false;
          throw const FormatException('学习通登录已失效，请重新登录。');
        }
        Map<String, dynamic>? data;
        try {
          final result = await _controller!
              .callAsyncJavaScript(
                functionBody: script,
                arguments: {
                  'task': task,
                  'expectedUrl': nativeUrl,
                  'requestedCourseId':
                      url.queryParameters['courseid'] ??
                      url.queryParameters['courseId'] ??
                      '',
                  'requestedClassId':
                      url.queryParameters['clazzid'] ??
                      url.queryParameters['classId'] ??
                      '',
                  'requestedCpi': url.queryParameters['cpi'] ?? '',
                },
              )
              .timeout(Duration(seconds: task == 'meta' ? 2 : 5));
          check(token);
          SsoDiagnostics.record(
            'chaoxing',
            'document_result',
            task: task,
            location: current,
            type: result?.value.runtimeType.toString(),
            ok: result?.error == null,
          );
          if (result?.value is Map && result?.error == null) {
            data = Map<String, dynamic>.from(result!.value as Map);
          }
        } catch (failure) {
          check(token);
          SsoDiagnostics.record(
            'chaoxing',
            'document_error',
            task: task,
            location: current,
            type: failure.runtimeType.toString(),
          );
          // A document replacement can discard the JS bridge mid-evaluation.
        }
        SsoDiagnostics.record(
          'chaoxing',
          'document_parse',
          task: task,
          location: current,
          ok: data?['ok'] == true,
          type:
              const {'pending', 'auth', 'busy', 'parse'}.contains(data?['code'])
              ? data!['code'] as String
              : null,
        );
        if (const {
          'TypeError',
          'ReferenceError',
          'SyntaxError',
          'URIError',
          'Error',
        }.contains(data?['reason'])) {
          SsoDiagnostics.record(
            'chaoxing',
            'parse_error_type',
            task: task,
            location: current,
            type: data!['reason'] as String,
          );
        }
        if (task == 'meta' &&
            data?['shape'] is String &&
            RegExp(r'^domEnc:\d{1,3},urlEnc:\d{1,3},workEnc:\d{1,3}$')
                .hasMatch(data!['shape'] as String)) {
          SsoDiagnostics.record(
            'chaoxing',
            'metadata_shape',
            task: task,
            location: current,
            type: data['shape'] as String,
          );
        }
        if (const {
              'origin',
              'http_status',
              'meta_path',
            }.contains(data?['stage']) ||
            (task == 'meta' && data?['httpStatus'] is int)) {
          SsoDiagnostics.record(
            'chaoxing',
            'metadata_validation',
            task: task,
            location: current,
            type:
                const {
                  'origin',
                  'http_status',
                  'meta_path',
                }.contains(data?['stage'])
                ? data!['stage'] as String
                : null,
            status: data?['httpStatus'] is int
                ? data!['httpStatus'] as int
                : null,
          );
        }
        if (task == 'meta' &&
            chaoxingHosts.contains(data?['documentHost']) &&
            data?['documentPath'] is String &&
            RegExp(r'^/[a-zA-Z0-9_./-]{0,160}$')
                .hasMatch(data!['documentPath'] as String)) {
          SsoDiagnostics.record(
            'chaoxing',
            'document_context',
            task: task,
            location: Uri(
              scheme: 'https',
              host: data['documentHost'] as String,
              path: data['documentPath'] as String,
            ),
          );
        }
        if (data?['ok'] == true) return data!;
        if ((data == null || data['code'] == 'pending') &&
            DateTime.now().isBefore(deadline)) {
          // Re-read only the document; never re-submit login or reload a course.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        if (data?['code'] == 'auth') verified = false;
        if (data?['code'] == 'busy') {
          busyUntil = DateTime.now().add(const Duration(minutes: 15));
        }
        throw FormatException(
          data?['code'] == 'auth' ? '学习通需要重新登录或确认权限。' : '学习通页面结构未识别，请打开官方网页核对。',
        );
      }
    } finally {
      if (identical(_pending, pending)) {
        _pending = null;
        if (token == generation) await _controller?.stopLoading();
      }
    }
  }

  Future<void> verify() async {
    if (busy) return;
    busy = true;
    notice = null;
    noticeIsError = false;
    changed();
    final token = generation;
    try {
      final data = await _read(
        SchoolSites.get(SchoolSiteId.chaoxing).entry!,
        'courses',
        token,
      );
      check(token);
      _courses = (data['courses'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      verified = true;
      notice = '课程接口已验证。';
    } catch (_) {
      if (token == generation) {
        verified = false;
        noticeIsError = true;
        notice = busyUntil?.isAfter(DateTime.now()) == true
            ? '学习通请求受限，请15分钟后重试。'
            : '验证未通过，请完成官方登录后重试。';
      }
    } finally {
      if (token == generation) {
        busy = false;
        changed();
      }
    }
  }

  Future<void> refresh() async {
    if (busy || !verified) return;
    final token = generation;
    busy = true;
    notice = null;
    noticeIsError = false;
    changed();
    final next = <ChaoxingItem>[], failed = <String>[];
    final succeeded = <String>{};
    try {
      final data = await _read(
        SchoolSites.get(SchoolSiteId.chaoxing).entry!,
        'courses',
        token,
      );
      _courses = (data['courses'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      progress = '正在确认教务当前学期课程…';
      changed();
      if (currentTerm == null) {
        throw const FormatException('请先连接校园教务，以确认本学期课程。');
      }
      final scope = await currentTerm!();
      check(token);
      totalCourseCount = _courses.length;
      _courses = _courses.where(scope.includes).toList();
      selectedCourseCount = _courses.length;
      scanTerm = scope.term;
      // A different semester must not leave old tasks in this semester's list.
      final keys = _courses
          .map((c) => '${c['courseId']}:${c['classId']}')
          .toSet();
      items = items.where((item) => keys.contains(item.courseKey)).toList();
      changed();
      for (var i = 0; i < _courses.length; i++) {
        check(token);
        final c = _courses[i], title = _courses[i]['title'] as String;
        final key = '${c['courseId']}:${c['classId']}';
        progress = '${i + 1}/${_courses.length} · $title';
        changed();
        Map<String, dynamic>? meta;
        try {
          meta = await _read(
            Uri.https('mooc1.chaoxing.com', '/visit/stucoursemiddle', {
              'courseid': c['courseId'],
              'clazzid': c['classId'],
              'cpi': c['cpi'],
              'ismooc2': '1',
              'v': '2',
            }),
            'meta',
            token,
          );
        } catch (_) {
          check(token);
          failed.add('$title：课程入口未读取');
        }
        if (meta != null) {
          for (final kind in ['work', 'exam']) {
            try {
              if (kind == 'work' && meta['workEnc'] == '') {
                throw const FormatException('缺少作业入口');
              }
              final query = <String, String>{
                (kind == 'work' ? 'courseId' : 'courseid'): c['courseId'],
                (kind == 'work' ? 'classId' : 'clazzid'): c['classId'],
                'cpi': c['cpi'],
                'ut': 's',
                't': '${DateTime.now().millisecondsSinceEpoch}',
                'stuenc': meta['stuenc'],
                if (kind == 'work') 'enc': meta['workEnc'],
              };
              final result = await _read(
                Uri.https(
                  'mooc1.chaoxing.com',
                  kind == 'work'
                      ? '/mooc2/work/list'
                      : '/exam-ans/mooc2/exam/exam-list',
                  query,
                ),
                kind,
                token,
              );
              succeeded.add('$key:$kind');
              next.addAll(
                (result['items'] as List).map(
                  (e) => ChaoxingItem.fromJson(
                    Map<String, dynamic>.from(e as Map),
                    title,
                    courseKey: key,
                  ),
                ),
              );
            } catch (_) {
              check(token);
              failed.add('$title：${kind == 'work' ? '作业' : '考试'}未读取');
            }
            if (!verified || busyUntil?.isAfter(DateTime.now()) == true) break;
          }
        }
        if (!verified || busyUntil?.isAfter(DateTime.now()) == true) break;
        if (i + 1 < _courses.length) {
          await Future<void>.delayed(courseGap);
        }
      }
      check(token);
      // Replace only successfully read lists; failed/unvisited lists keep cache.
      items = failed.isEmpty
          ? next
          : [
              ...items.where(
                (item) => !succeeded.contains('${item.courseKey}:${item.kind}'),
              ),
              ...next,
            ];
      if (succeeded.isNotEmpty || failed.isEmpty) updatedAt = DateTime.now();
      noticeIsError = failed.isNotEmpty;
      notice = failed.isEmpty
          ? (selectedCourseCount == 0 ? '本学期课程名单未匹配到学习通课程，未扫描历史课程。' : null)
          : '部分项目未更新，失败项保留旧数据。${failed.join('；')}';
      if (busyUntil?.isAfter(DateTime.now()) == true) {
        noticeIsError = true;
        notice = '学习通请求受限，请15分钟后重试。${notice ?? ''}';
      }
    } on FormatException catch (e) {
      if (token == generation) {
        noticeIsError = true;
        notice = e.message;
      }
    } catch (_) {
      if (token == generation) {
        noticeIsError = true;
        notice = '刷新失败，保留上次结果。请检查登录或稍后重试。';
      }
    } finally {
      if (token == generation) {
        busy = false;
        progress = '';
        changed();
      }
    }
  }

  Future<void> close({bool clearCookies = false}) async {
    generation++;
    verified = false;
    busy = false;
    items = [];
    _courses = [];
    scanTerm = null;
    totalCourseCount = 0;
    selectedCourseCount = 0;
    notice = null;
    updatedAt = null;
    progress = '';
    if (_pending?.isCompleted == false) {
      _pending!.complete();
    }
    _pending = null;
    final view = _view;
    _view = null;
    _controller = null;
    await view?.dispose();
    if (clearCookies && supported) {
      for (final host in chaoxingHosts) {
        await CookieManager.instance().deleteCookies(
          url: WebUri('https://$host/'),
        );
      }
      await CookieManager.instance().deleteCookies(
        url: WebUri('https://chaoxing.com/'),
        domain: '.chaoxing.com',
      );
    }
    changed();
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(close());
    super.dispose();
  }
}
