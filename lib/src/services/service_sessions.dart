import 'script_result.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'navigation.dart';
import 'site_registry.dart';
import 'sso_diagnostics.dart';

class CardApplicationRejected extends FormatException {
  const CardApplicationRejected() : super(description);
  static const description = '学校统一认证拒绝了一卡通入口（应用未注册），请稍后重试；重新登录无法解决此问题。';
}

abstract class ServiceSession {
  bool get available;
  Future<Map<String, dynamic>> query(
    String task,
    Map<String, dynamic> arguments,
  );
  Future<void> close();
}

/// One live WebView per service. All views share the native CAS cookie jar;
/// each service keeps its own origin-local token. No JWT crosses into Dart.
class NativeServiceSession implements ServiceSession {
  NativeServiceSession({
    required this.site,
    this.connectionTimeout = const Duration(seconds: 45),
  });
  Future<void> Function()? beforeConnect;
  Future<bool> Function()? renewAuthentication;
  final Duration connectionTimeout;
  final SchoolSite site;
  bool get card => site.id == SchoolSiteId.campusCard;
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Future<void>? _connecting;
  Completer<bool>? _pending;
  Future<void> _queue = Future.value();
  int _generation = 0;
  bool _ready = false;
  @override
  bool get available =>
      InAppWebViewPlatform.instance != null &&
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  static const academicTasks = {
    'roomsOptions',
    'rooms',
    'grades',
    'gradeAnalysis',
    'exams',
    'studentProfile',
    'creditPlans',
    'credits',
  };
  Future<void> _prepareTask(String task) async {
    if (site.id != SchoolSiteId.teaching || !academicTasks.contains(task)) {
      return;
    }
    final featureId = switch (task) {
      'roomsOptions' => 'rooms',
      'creditPlans' => 'credits',
      _ => task,
    };
    final feature = site.features.singleWhere((f) => f.id == featureId);
    final entry = Uri.parse(feature.entry!);
    final current = await _controller!.getUrl();
    if (current?.host != entry.host ||
        current?.path != entry.path ||
        current?.fragment != entry.fragment) {
      await _controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(entry.toString())),
      );
    }
    final until = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(until)) {
      final controller = _controller;
      if (controller == null) throw const FormatException('账号状态已变化，请重试。');
      final url = await controller.getUrl();
      if (url?.host == entry.host &&
          url?.scheme == 'https' &&
          url?.path == entry.path &&
          url?.fragment == entry.fragment) {
        final ready = await controller
            .evaluateJavascript(
              source:
                  'location.origin === ${jsonEncode('https://${entry.host}')} && location.pathname === ${jsonEncode(entry.path)} && '
                  'location.hash === ${jsonEncode(entry.hasFragment ? '#${entry.fragment}' : '')} && '
                  'document.readyState === "complete" && document.querySelector(${jsonEncode(feature.readySelector)}) !== null && '
                  'typeof window.flutter_inappwebview === "object" && typeof window.flutter_inappwebview.callHandler === "function"',
            )
            .timeout(const Duration(seconds: 2));
        if (ready == true) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw const FormatException('教务页面需要人工验证，请通过右上角打开原网页。');
  }

  Future<Map<String, dynamic>> _execute(
    String task,
    Map<String, dynamic> arguments,
  ) async {
    final controller = _controller;
    final url = await controller?.getUrl();
    SsoDiagnostics.record(
      site.id.name,
      'context',
      location: url == null ? null : Uri.tryParse(url.toString()),
      ok: controller != null,
    );
    if (controller == null ||
        !site.acceptsProbeLocation(
          url == null ? null : Uri.tryParse(url.toString()),
        )) {
      throw const FormatException('需要重新连接校园账号。');
    }
    SsoDiagnostics.record(
      site.id.name,
      'execute',
      task: task,
      location: url == null ? null : Uri.tryParse(url.toString()),
    );
    final body = await rootBundle.loadString(
      site.id == SchoolSiteId.teaching && academicTasks.contains(task)
          ? 'assets/js/nuist_academic.js'
          : site.asset!,
    );
    final response = await controller
        .callAsyncJavaScript(
          functionBody: schoolScriptBody(body),
          arguments: {...arguments, 'task': task},
        )
        .timeout(const Duration(seconds: 120));
    final value = response?.value;
    SsoDiagnostics.record(
      site.id.name,
      'script_result',
      task: task,
      type: value.runtimeType.toString(),
      ok: response?.error == null && value != null,
    );
    if (response?.error != null || value == null) {
      throw const FormatException('学校服务未能返回数据。');
    }
    return Map<String, dynamic>.from(
      (value is String ? jsonDecode(value) : value) as Map,
    );
  }

  Future<void> _connect() async {
    if (_ready) return;
    if (_connecting != null) return _connecting;
    final future = _open();
    _connecting = future;
    try {
      await future;
    } finally {
      if (identical(_connecting, future)) _connecting = null;
    }
  }

  Future<void> _open() async {
    final generation = _generation;
    await beforeConnect?.call();
    if (generation != _generation) throw const FormatException('账号状态已变化，请重试。');
    SsoDiagnostics.record(
      site.id.name,
      'availability',
      ok: available,
      type: defaultTargetPlatform.name,
    );
    if (!available) throw const FormatException('请在支持 WebView 的客户端连接校园服务。');
    SsoDiagnostics.record(site.id.name, 'connect_start', location: site.entry);
    final connected = Completer<bool>();
    _pending = connected;
    String failure = '自动连接超时，请重新连接校园账号；如学校要求验证，请在官方页面完成。';
    bool probing = false;
    bool authStarted = site.sessionEntry == null;
    bool documentReady = false;
    bool renewalAttempted = false;
    bool applicationRejected = false;
    Future<void> probe() async {
      if (probing ||
          !documentReady ||
          connected.isCompleted ||
          generation != _generation) {
        return;
      }
      probing = true;
      try {
        final uri = await _controller?.getUrl();
        final location = uri == null ? null : Uri.tryParse(uri.toString());
        if (card &&
            SchoolNavigation.trusted(location, {'authserver.nuist.edu.cn'}) &&
            {'/authserver', '/authserver/login'}.contains(location!.path)) {
          final stateScript = await rootBundle.loadString(
            'assets/js/nuist_auth_page_state.js',
          );
          final pageState = await _controller!
              .evaluateJavascript(source: '(function() {\n$stateScript\n})()')
              .timeout(const Duration(seconds: 2));
          if (pageState == 'unregistered') {
            applicationRejected = true;
            if (!connected.isCompleted) connected.complete(false);
            SsoDiagnostics.record(
              site.id.name,
              'application_unregistered',
              ok: false,
            );
            return;
          }
          if (renewAuthentication == null ||
              renewalAttempted ||
              pageState != 'login') {
            return;
          }
          SsoDiagnostics.record(site.id.name, 'cas_login_form', ok: true);
          renewalAttempted = true;
          final renewed = await renewAuthentication!();
          if (generation != _generation || connected.isCompleted) return;
          SsoDiagnostics.record(site.id.name, 'cas_renewal', ok: renewed);
          if (!renewed) {
            failure = '一卡通需要重新认证，请在账号绑定中登录或开启通行密钥自动登录。';
            connected.complete(false);
            return;
          }
          documentReady = false;
          await _controller!.loadUrl(
            urlRequest: URLRequest(
              url: WebUri((site.authEntry ?? site.entry!).toString()),
            ),
          );
          return;
        }
        if (!site.acceptsProbeLocation(location)) return;
        // A late onLoadStop can refer to a document that is being replaced.
        // evaluateJavascript returns directly via native code, so this check
        // cannot hang waiting for an old document's async JavaScript bridge.
        final stable = await _controller!
            .evaluateJavascript(
              source:
                  'location.origin === ${jsonEncode('https://${site.host}')} && document.readyState === "complete" && '
                  'typeof window.flutter_inappwebview === "object" && typeof window.flutter_inappwebview.callHandler === "function"',
            )
            .timeout(const Duration(seconds: 2));
        if (stable != true) {
          SsoDiagnostics.record(
            site.id.name,
            'document_gate',
            ok: false,
            type: stable.runtimeType.toString(),
          );
          return;
        }
        final data = await _execute(
          site.probeTask!,
          {},
        ).timeout(const Duration(seconds: 15));
        SsoDiagnostics.record(
          site.id.name,
          'probe',
          ok: data['ok'] == true,
          ready: site.isReady(data),
        );
        if (site.isReady(data) && !connected.isCompleted) {
          connected.complete(true);
        } else if (!authStarted && generation == _generation) {
          // Validate the existing business session before starting another CAS
          // flow. Its official callback initializes per-WebView frontend state.
          authStarted = true;
          documentReady = false;
          await _controller!.loadUrl(
            urlRequest: URLRequest(url: WebUri(site.authEntry!.toString())),
          );
        }
      } catch (error) {
        SsoDiagnostics.record(
          site.id.name,
          'probe_error',
          type: error.runtimeType.toString(),
        );
        /* Redirects can replace the document during a probe. */
      } finally {
        probing = false;
      }
    }

    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(
          (site.sessionEntry ?? site.authEntry ?? site.entry!).toString(),
        ),
      ),
      initialSettings: InAppWebViewSettings(
        // CAS redirects can contain a single-use ticket. Never replay a cached
        // card authentication redirect when rebuilding its origin-local token.
        cacheEnabled: !card,
        cacheMode: card ? CacheMode.LOAD_NO_CACHE : CacheMode.LOAD_DEFAULT,
        javaScriptEnabled: true,
        useHybridComposition: false,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        useShouldOverrideUrlLoading: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        isInspectable: false,
      ),
      onWebViewCreated: (controller) {
        SsoDiagnostics.record(site.id.name, 'webview_created');
        if (generation == _generation) _controller = controller;
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final raw = action.request.url;
        final uri = raw == null ? null : Uri.tryParse(raw.toString());
        if (SchoolNavigation.trusted(uri, {'authserver.nuist.edu.cn'}) &&
            uri!.queryParameters.containsKey('service')) {
          SsoDiagnostics.record(
            site.id.name,
            'cas_service',
            location: Uri.tryParse(uri.queryParameters['service']!),
          );
        }
        if (site.navigation!(uri) ||
            (action.isForMainFrame == false &&
                uri?.toString() == 'about:blank')) {
          return NavigationActionPolicy.ALLOW;
        }
        SsoDiagnostics.record(
          site.id.name,
          'navigation_blocked',
          location: uri,
          mainFrame: action.isForMainFrame,
        );
        final secure = SchoolNavigation.httpsUpgrade(uri, site.navigation!);
        if (secure != null) {
          SsoDiagnostics.record(
            site.id.name,
            'navigation_upgrade',
            location: secure,
          );
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(secure.toString())),
          );
        } else if (action.isForMainFrame != false && !connected.isCompleted) {
          failure = '学校登录跳转未完成：${SchoolNavigation.safeLocation(uri)}';
          connected.complete(false);
        }
        return NavigationActionPolicy.CANCEL;
      },
      onReceivedServerTrustAuthRequest:
          defaultTargetPlatform == TargetPlatform.android
          ? (_, challenge) async {
              final host = challenge.protectionSpace.host;
              final code =
                  challenge.protectionSpace.sslError?.code.toString() ??
                  'unknown';
              SsoDiagnostics.record(
                site.id.name,
                'tls_error',
                location: Uri(scheme: 'https', host: host),
                type: code,
                ok: false,
              );
              if ({
                    site.host,
                    'authserver.nuist.edu.cn',
                    'i.nuist.edu.cn',
                  }.contains(host) &&
                  !connected.isCompleted) {
                failure = '学校站点证书校验未通过（$host，$code），请检查网络或稍后重试。';
                connected.complete(false);
              }
              return null; // Preserve Android's default cancellation; never bypass TLS.
            }
          : null,
      onLoadStart: (_, url) {
        documentReady = false;
        SsoDiagnostics.record(
          site.id.name,
          'load_start',
          location: url == null ? null : Uri.tryParse(url.toString()),
        );
      },
      onLoadStop: (_, url) async {
        final location = url == null ? null : Uri.tryParse(url.toString());
        documentReady =
            site.acceptsProbeLocation(location) ||
            (card &&
                SchoolNavigation.trusted(location, {
                  'authserver.nuist.edu.cn',
                }) &&
                {'/authserver', '/authserver/login'}.contains(location!.path));
        SsoDiagnostics.record(
          site.id.name,
          'load_stop',
          ready: documentReady,
          location: url == null ? null : Uri.tryParse(url.toString()),
        );
        await probe();
      },
      onUpdateVisitedHistory: (_, _, _) => probe(),
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != true) return;
        if (site.networkRouting && !connected.isCompleted) {
          failure = '公告访问路径不可达，请检查校园网或 VPN。';
          connected.complete(false);
        }
        SsoDiagnostics.record(
          site.id.name,
          'load_error',
          location: Uri.tryParse(request.url.toString()),
          type: error.type.toString(),
          mainFrame: true,
        );
      },
      onReceivedHttpError: (_, request, response) {
        if (request.isForMainFrame != true) return;
        if (site.id == SchoolSiteId.library && !connected.isCompleted) {
          failure = '图书馆认证入口暂不可用，请在官方页面确认登录后重试。';
          connected.complete(false);
        }
        SsoDiagnostics.record(
          site.id.name,
          'http_error',
          location: Uri.tryParse(request.url.toString()),
          status: response.statusCode,
          mainFrame: true,
        );
      },
    );
    _view = view;
    // Bounded readiness checks cover SPA token initialization after loadStop.
    final timer = Timer.periodic(const Duration(seconds: 1), (_) => probe());
    try {
      await view.run();
      SsoDiagnostics.record(site.id.name, 'webview_running');
      final success = await connected.future.timeout(
        connectionTimeout,
        onTimeout: () => false,
      );
      SsoDiagnostics.record(
        site.id.name,
        'connect_result',
        ready: success && generation == _generation,
      );
      if (!success || generation != _generation) {
        if (applicationRejected && generation == _generation) {
          throw const CardApplicationRejected();
        }
        throw FormatException(failure);
      }
      _ready = true;
    } catch (_) {
      if (identical(_view, view)) {
        _view = null;
        _controller = null;
        await view.dispose();
      }
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<Map<String, dynamic>> query(
    String task,
    Map<String, dynamic> arguments,
  ) {
    final generation = _generation;
    final operation = _queue.catchError((Object _) {}).then((_) async {
      if (generation != _generation) {
        throw const FormatException('账号状态已变化，请重试。');
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        await _connect();
        if (generation != _generation) {
          throw const FormatException('账号状态已变化，请重试。');
        }
        Map<String, dynamic> result;
        try {
          await _prepareTask(task);
          if (generation != _generation) {
            throw const FormatException('账号状态已变化，请重试。');
          }
          result = await _execute(task, arguments);
        } catch (_) {
          if (attempt == 1 || generation != _generation) rethrow;
          result = {'ok': false};
        }
        if (generation != _generation) {
          throw const FormatException('账号状态已变化，请重试。');
        }
        if (result['ok'] == true &&
            (task != 'probe' || site.isReady(result)) &&
            (task != 'sync' ||
                ['wallet', 'bills', 'electricity'].any(result.containsKey))) {
          return result;
        }
        if (attempt == 1) {
          throw FormatException(result['error'] as String? ?? '校园服务查询失败。');
        }
        // Queries are read-only: rebuild the service session once through CAS.
        _ready = false;
        final old = _view;
        _view = null;
        _controller = null;
        await old?.dispose();
      }
      throw const FormatException('校园服务连接失败。');
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<void> close() async {
    _generation++;
    _connecting = null;
    _queue = Future.value();
    if (_pending?.isCompleted == false) _pending!.complete(false);
    _pending = null;
    _ready = false;
    final old = _view;
    _view = null;
    _controller = null;
    await old?.dispose();
  }
}
